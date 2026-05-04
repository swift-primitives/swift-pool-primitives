import Array_Primitives
import Async_Primitives
import Pool_Primitives
import Pool_Primitives_Test_Support
import Synchronization
import Testing

@testable import Pool_Bounded_Primitives
@_spi(Internal) @testable import Pool_Primitives_Core

// Tests for the unified `pool.acquire { body }` API.
//
// One method, one shape: typed throws over the body's `E`, returning
// `Either<Pool.Lifecycle.Error, E>`. Sync closures promote to async.
// Non-throwing bodies infer `E = Never`. No `.try`, no `.timeout(_:)`,
// no deadline parameter — non-blocking and timeout semantics compose
// externally via Task cancellation.

@Suite(.serialized)
struct PoolBoundedAsyncBodyTests {
    @Suite struct Direct {}
    @Suite struct Cancellation {}
    @Suite struct Borrowing {}
}

private typealias TestPool = Pool.Bounded<Int>

private struct TestError: Swift.Error, Equatable {}

// Helper: prefill a pool of capacity 1 with the given value.
private func makePrefilled(_ value: Int) -> TestPool {
    let pool = TestPool(capacity: 1, destroy: { _ in })
    pool._state.withLock { state in
        let id = state.nextID(scope: pool.scope)
        pool.entries[0].move.in(value)
        state.transition(slot: 0, to: .available(id))
        state.pushAvailable(0)
    }
    return pool
}

// MARK: - Direct Acquire

extension PoolBoundedAsyncBodyTests.Direct {
    @Test
    func `async body completes and returns`() async throws {
        let pool = makePrefilled(42)

        let result: Int = try await pool.acquire { resource in
            await Task.yield()
            return resource * 2
        }

        #expect(result == 84)
    }

    @Test
    func `sync body promotes to async overload`() async throws {
        let pool = makePrefilled(7)

        // Sync closure passed to the single async overload — Swift promotes.
        let result: Int = try await pool.acquire { resource in
            return resource + 1
        }

        #expect(result == 8)
    }

    @Test
    func `async body persists mutation`() async throws {
        let pool = makePrefilled(0)

        try await pool.acquire { (resource: inout sending Int) async -> Void in
            await Task.yield()
            resource = 99
        }

        let snapshot: Int = try await pool.acquire { resource in resource }
        #expect(snapshot == 99)
    }

    @Test
    func `throwing body surfaces as Either right`() async throws {
        let pool = makePrefilled(1)

        // Per [IMPL-075]: do throws(E) { … } catch { … }, no cast.
        do throws(Either<Pool.Lifecycle.Error, TestError>) {
            try await pool.acquire { (_: inout sending Int) async throws(TestError) -> Int in
                throw TestError()
            }
            Issue.record("Expected throw")
        } catch {
            // `error` is Either<Pool.Lifecycle.Error, TestError> implicitly
            switch error {
            case .left(let lifecycleError):
                Issue.record("Expected body failure, got \(lifecycleError)")
            case .right(let bodyError):
                #expect(bodyError == TestError())
            }
        }
    }

    @Test
    func `throwing body that succeeds returns value`() async throws {
        let pool = makePrefilled(5)

        do throws(Either<Pool.Lifecycle.Error, TestError>) {
            let result: Int = try await pool.acquire { (resource: inout sending Int) async throws(TestError) -> Int in
                try? await Task.sleep(for: .milliseconds(5))
                return resource + 100
            }
            #expect(result == 105)
        } catch {
            Issue.record("Expected success, got \(error)")
        }
    }
}

// MARK: - Cancellation

extension PoolBoundedAsyncBodyTests.Cancellation {
    @Test
    func `cancellation while waiting throws cancelled`() async throws {
        let pool = TestPool(capacity: 1, destroy: { _ in })
        // Pool is empty — acquire will block waiting

        let waiterEnqueued = Async.Gate()
        pool.onEnqueue = { waiterEnqueued.open() }

        // The Task returns the lifecycle error directly. Because the
        // do/catch is INSIDE the Task closure (not crossing the Task
        // boundary), the implicit `error` binding inside catch is typed
        // as Either<...> per [IMPL-075] — no cast, no Mutex capture.
        let task = Task {
            do throws(Either<Pool.Lifecycle.Error, Never>) {
                let _: Int = try await pool.acquire { (resource: inout sending Int) async -> Int in
                    resource
                }
                return Pool.Lifecycle.Error?.none
            } catch {
                switch error {
                case .left(let lifecycleError):
                    return lifecycleError
                }
            }
        }

        await waiterEnqueued.wait()
        task.cancel()

        #expect(await task.value == .cancelled)
    }

    @Test
    func `task cancellation observed inside body via .cancelled`() async throws {
        // The body is responsible for honouring Task.checkCancellation; the
        // pool surfaces external cancellation as `.cancelled` only at the
        // wait stage. Once the body holds the slot, body-level cancellation
        // is the body's responsibility.
        let pool = makePrefilled(1)

        let result: Int = try await pool.acquire { (resource: inout sending Int) async -> Int in
            return resource
        }
        #expect(result == 1)
    }
}

// MARK: - Borrowing

extension PoolBoundedAsyncBodyTests.Borrowing {
    @Test
    func `inout resource borrowed across await`() async throws {
        // Verify inout Resource composes with await — the slot is held for
        // the entire body, including across the suspension point.
        let pool = makePrefilled(10)

        let result: Int = try await pool.acquire { (resource: inout sending Int) async -> Int in
            let before = resource
            try? await Task.sleep(for: .milliseconds(5))
            resource = before * 3
            return resource
        }

        #expect(result == 30)
    }

    @Test
    func `slot returned after body throws`() async throws {
        let pool = makePrefilled(1)

        // First call — body throws
        do throws(Either<Pool.Lifecycle.Error, TestError>) {
            try await pool.acquire { (_: inout sending Int) async throws(TestError) -> Int in
                throw TestError()
            }
        } catch {
            // Expected; .right
        }

        // Second call — slot must be available
        let result: Int = try await pool.acquire { resource in resource }
        #expect(result == 1)
    }
}
