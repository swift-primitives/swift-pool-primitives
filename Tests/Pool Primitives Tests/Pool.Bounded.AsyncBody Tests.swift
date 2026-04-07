import Testing
import Synchronization
import Async_Primitives
import Pool_Primitives_Test_Support

@_spi(Internal) @testable import Pool_Primitives_Core
@testable import Pool_Bounded_Primitives
import Pool_Primitives
import Array_Primitives

// Tests for the async-body callAsFunction overloads added in
// `ownership-transfer-conventions`. These exercise the double-nonsending
// pattern: the function is `nonisolated(nonsending)`, the body parameter is
// `nonisolated(nonsending) (inout Resource) async -> sending T`, and the
// return is `sending T`.
//
// Inline closures are used so Swift can infer the closure type from the
// matching async-body overload (otherwise an explicit type annotation
// without `sending` would force a type-conversion error).

@Suite(.serialized)
struct PoolBoundedAsyncBodyTests {
    @Suite struct Direct {}
    @Suite struct Timeout {}
    @Suite struct Try {}
    @Suite struct Acquire {}
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

// MARK: - Direct Acquire (pool { ... })

extension PoolBoundedAsyncBodyTests.Direct {
    @Test
    func `async body completes and returns`() async throws {
        let pool = makePrefilled(42)

        let result: Int = try await pool { (resource: inout Int) async -> Int in
            await Task.yield()
            return resource * 2
        }

        #expect(result == 84)
    }

    @Test
    func `async body holds slot across Task sleep`() async throws {
        let pool = makePrefilled(7)

        let result: Int = try await pool { (resource: inout Int) async -> Int in
            try? await Task.sleep(for: .milliseconds(10))
            resource += 1
            return resource
        }

        #expect(result == 8)
    }

    @Test
    func `async body persists mutation`() async throws {
        let pool = makePrefilled(0)

        let _: Void = try await pool { (resource: inout Int) async -> Void in
            await Task.yield()
            resource = 99
        }

        let snapshot: Int = try await pool { (resource: inout Int) -> Int in resource }
        #expect(snapshot == 99)
    }

    @Test
    func `throwing async body returns Result failure`() async throws {
        let pool = makePrefilled(1)

        let result: Result<Int, TestError> = try await pool { (resource: inout Int) async throws(TestError) -> Int in
            throw TestError()
        }

        switch result {
        case .success:
            Issue.record("Expected failure")
        case .failure(let error):
            #expect(error == TestError())
        }
    }

    @Test
    func `throwing async body returns Result success`() async throws {
        let pool = makePrefilled(5)

        let result: Result<Int, TestError> = try await pool { (resource: inout Int) async throws(TestError) -> Int in
            try? await Task.sleep(for: .milliseconds(5))
            return resource + 100
        }

        switch result {
        case .success(let value):
            #expect(value == 105)
        case .failure:
            Issue.record("Expected success")
        }
    }

    @Test
    func `async body resource is borrowed across await`() async throws {
        // Verify inout Resource composes with await — the slot is held for
        // the entire body, including across the suspension point.
        let pool = makePrefilled(10)

        let result: Int = try await pool { (resource: inout Int) async -> Int in
            let before = resource
            try? await Task.sleep(for: .milliseconds(5))
            resource = before * 3
            return resource
        }

        #expect(result == 30)
    }
}

// MARK: - Acquire pass-through (pool.acquire { ... })

extension PoolBoundedAsyncBodyTests.Acquire {
    @Test
    func `acquire async body completes`() async throws {
        let pool = makePrefilled(11)

        let result: Int = try await pool.acquire { (resource: inout Int) async -> Int in
            await Task.yield()
            return resource + 1
        }

        #expect(result == 12)
    }

    @Test
    func `acquire async body throwing returns Result`() async throws {
        let pool = makePrefilled(0)

        let result: Result<Int, TestError> = try await pool.acquire { (_: inout Int) async throws(TestError) -> Int in
            throw TestError()
        }

        if case .success = result {
            Issue.record("Expected failure")
        }
    }
}

// MARK: - Acquire.Timeout

extension PoolBoundedAsyncBodyTests.Timeout {
    @Test
    func `timeout async body succeeds when resource available`() async throws {
        let pool = makePrefilled(50)

        let timeoutOp = pool.acquire.timeout(.seconds(1))
        let result: Int = try await timeoutOp { (resource: inout Int) async -> Int in
            try? await Task.sleep(for: .milliseconds(5))
            return resource * 2
        }

        #expect(result == 100)
    }

    @Test
    func `timeout async body times out when no resource`() async throws {
        let pool = TestPool(capacity: 1, destroy: { _ in })

        let timeoutOp = pool.acquire.timeout(.nanoseconds(1))
        await #expect(throws: Pool.Lifecycle.Error.timeout) {
            let _: Int = try await timeoutOp { (_: inout Int) async -> Int in
                999
            }
        }
    }

    @Test
    func `timeout async optional returns nil on timeout`() async throws {
        let pool = TestPool(capacity: 1, destroy: { _ in })

        let timeoutOp = pool.acquire.timeout(.nanoseconds(1))
        let result: Int? = try await timeoutOp.optional { (_: inout Int) async -> Int in
            42
        }

        #expect(result == nil)
    }

    @Test
    func `timeout async optional returns value when available`() async throws {
        let pool = makePrefilled(7)

        let timeoutOp = pool.acquire.timeout(.seconds(1))
        let result: Int? = try await timeoutOp.optional { (resource: inout Int) async -> Int in
            try? await Task.sleep(for: .milliseconds(5))
            return resource + 1
        }

        #expect(result == 8)
    }

    @Test
    func `timeout async body throwing returns Result`() async throws {
        let pool = makePrefilled(1)

        let timeoutOp = pool.acquire.timeout(.seconds(1))
        let result: Result<Int, TestError> = try await timeoutOp { (_: inout Int) async throws(TestError) -> Int in
            throw TestError()
        }

        if case .success = result {
            Issue.record("Expected failure")
        }
    }
}

// MARK: - Acquire.Try

extension PoolBoundedAsyncBodyTests.Try {
    @Test
    func `try async body acquires when available`() async throws {
        let pool = makePrefilled(10)

        let result: Int = try await pool.acquire.try { (resource: inout Int) async -> Int in
            try? await Task.sleep(for: .milliseconds(2))
            return resource + 5
        }

        #expect(result == 15)
    }

    @Test
    func `try async body throws exhausted when empty`() async throws {
        let pool = TestPool(capacity: 1, destroy: { _ in })

        await #expect(throws: Pool.Lifecycle.Error.exhausted) {
            let _: Int = try await pool.acquire.try { (_: inout Int) async -> Int in
                999
            }
        }
    }

    @Test
    func `try async optional returns nil when exhausted`() async throws {
        let pool = TestPool(capacity: 1, destroy: { _ in })

        let result: Int? = try await pool.acquire.try.optional { (_: inout Int) async -> Int in
            42
        }

        #expect(result == nil)
    }

    @Test
    func `try async body throwing returns Result`() async throws {
        let pool = makePrefilled(1)

        let result: Result<Int, TestError> = try await pool.acquire.try { (_: inout Int) async throws(TestError) -> Int in
            throw TestError()
        }

        if case .success = result {
            Issue.record("Expected failure")
        }
    }
}
