import Array_Primitives
import Fixed_Primitives
import Tagged_Collection_Primitives
import Async_Primitives
import Either_Primitives
import Pool_Primitives
import Pool_Primitives_Test_Support
import Synchronization
import Testing

@testable import Pool_Bounded_Primitives
@_spi(Internal) @testable import Pool_Error_Primitives

// Pool.Bounded is generic — parallel namespace per [TEST-004]
@Suite(.serialized)
struct PoolBoundedTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
    @Suite(.serialized) struct Performance {}
}

// MARK: - Type Aliases

private typealias TestPool = Pool.Bounded<Int>

// MARK: - Acquire Tests

extension PoolBoundedTests.Unit {
    @Test
    func `eager pool acquires filled resource`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        pool._state.withLock { state in
            let id = state.nextID(scope: pool.scope)
            pool.entries.underlying[0].move.in(42)
            state.transition(slot: 0, to: .available(id))
            state.pushAvailable(0)
        }

        let result: Int = try await pool.acquire { resource in
            resource
        }

        #expect(result == 42)
    }

    @Test
    func `acquire increments metrics`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        pool._state.withLock { state in
            let id = state.nextID(scope: pool.scope)
            pool.entries.underlying[0].move.in(100)
            state.transition(slot: 0, to: .available(id))
            state.pushAvailable(0)
        }

        let _: Int = try await pool.acquire { $0 }

        let (acquisitions, releases) = pool._state.withLock { state in
            (state.metrics.acquisitions, state.metrics.releases)
        }

        #expect(acquisitions == 1)
        #expect(releases == 1)
    }

    @Test
    func `resource mutation persists`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        pool._state.withLock { state in
            let id = state.nextID(scope: pool.scope)
            pool.entries.underlying[0].move.in(0)
            state.transition(slot: 0, to: .available(id))
            state.pushAvailable(0)
        }

        try await pool.acquire { (resource: inout sending Int) async in
            resource += 10
        }

        let value: Int = try await pool.acquire { resource in
            resource
        }

        #expect(value == 10)
    }
}

// MARK: - Fill Tests

extension PoolBoundedTests.Unit {
    @Test
    func `fill adds resource to empty slot`() async throws {
        let pool = TestPool(
            capacity: 2,
            destroy: { _ in }
        )

        try pool.fill(42)

        let value: Int = try await pool.acquire { $0 }
        #expect(value == 42)
    }

    #if DEBUG
    @Test
    func `fill hands off to waiting acquirer`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        unsafe pool.onEnqueue = { waiterEnqueued.open() }

        let task = Task {
            try await pool.acquire { (resource: inout sending Int) async -> Int in
                resource
            }
        }

        await waiterEnqueued.wait()

        try pool.fill(99)

        let result = try await task.value
        #expect(result == 99)
    }
    #endif

    @Test
    func `fill increments metrics`() throws {
        let pool = TestPool(
            capacity: 2,
            destroy: { _ in }
        )

        try pool.fill(1)
        try pool.fill(2)

        let fills = pool._state.withLock { state in
            state.metrics.fills
        }

        #expect(fills == 2)
    }
}

// MARK: - Entry Independence (Regression: repeating-reference-type-aliasing)

extension PoolBoundedTests.Unit {
    @Test
    func `entries are independent objects`() throws {
        let pool = TestPool(
            capacity: 3,
            destroy: { _ in }
        )

        try pool.fill(10)
        try pool.fill(20)
        try pool.fill(30)

        #expect(pool.metrics.fills == 3)
    }
}

// MARK: - Edge Cases

extension PoolBoundedTests.EdgeCase {
    @Test
    func `shutdown rejects new acquisitions`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        pool._state.withLock { state in
            _ = state.lifecycle.shutdown.begin()
        }

        // Per [IMPL-075]: do throws(E) { } catch { } — no cast.
        do throws(Either<Pool.Lifecycle.Error, Never>) {
            try await pool.acquire { (_: inout sending Int) async in }
            Issue.record("Expected shutdown")
        } catch {
            switch error {
            case .left(.shutdown):
                break  // Expected

            case .left(let other):
                Issue.record("Expected .shutdown, got \(other)")
            }
        }
    }

    @Test
    func `fill rejects when pool is full`() throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        try pool.fill(1)

        #expect(throws: TestPool.Fill.Error.full) {
            try pool.fill(2)
        }
    }

    @Test
    func `fill rejects during shutdown`() throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        pool._state.withLock { state in
            _ = state.lifecycle.shutdown.begin()
        }

        #expect(throws: TestPool.Fill.Error.shutdown) {
            try pool.fill(1)
        }
    }

    @Test
    func `shutdown drains available resources`() async throws {
        let destroyCount = Mutex(0)
        let pool = TestPool(
            capacity: 2,
            destroy: { _ in destroyCount.withLock { $0 += 1 } }
        )

        try pool.fill(1)
        try pool.fill(2)

        pool.shutdown()
        await pool.shutdown.wait()

        #expect(destroyCount.withLock { $0 } == 2)

        let lifecycle = pool._state.withLock { state in
            state.lifecycle
        }
        #expect(lifecycle == .closed)
    }

    #if DEBUG
    @Test
    func `shutdown wakes waiting acquirers`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        unsafe pool.onEnqueue = { waiterEnqueued.open() }

        let task: Task<Bool, Never> = Task {
            do throws(Either<Pool.Lifecycle.Error, Never>) {
                let _: Int = try await pool.acquire { $0 }
                return false
            } catch {
                switch error {
                case .left:
                    return true
                }
            }
        }

        await waiterEnqueued.wait()

        pool.shutdown()
        await pool.shutdown.wait()

        let gotShutdownError = await task.value
        #expect(gotShutdownError)
    }
    #endif
}

// MARK: - Lazy Policy Tests

extension PoolBoundedTests.Unit {
    @Test
    func `lazy pool creates resource on demand`() async throws {
        let createCount = Mutex(0)
        let pool = Pool.Bounded<Int>(
            capacity: 2,
            create: {
                createCount.withLock { $0 += 1 }
                return 42
            },
            destroy: { _ in }
        )

        let value: Int = try await pool.acquire { $0 }
        #expect(value == 42)
        #expect(createCount.withLock { $0 } == 1)

        let _: Int = try await pool.acquire { $0 }
        #expect(createCount.withLock { $0 } == 1)
    }

    @Test
    func `lazy pool reuses returned resource`() async throws {
        let createCount = Mutex(0)
        let pool = Pool.Bounded<Int>(
            capacity: 2,
            create: {
                createCount.withLock { $0 += 1 }
                return 42
            },
            destroy: { _ in }
        )

        let v1: Int = try await pool.acquire { $0 }
        #expect(v1 == 42)
        #expect(createCount.withLock { $0 } == 1)

        let v2: Int = try await pool.acquire { $0 }
        #expect(v2 == 42)
        #expect(createCount.withLock { $0 } == 1)
    }

    @Test
    func `lazy pool creates up to capacity concurrently`() async throws {
        let createCount = Mutex(0)
        let barrier = Async.Barrier(parties: 2)

        @Sendable
        func makeOne() async throws(Pool.Lifecycle.Error) -> sending Int {
            do {
                try await barrier.arrive()
            } catch {
                throw Pool.Lifecycle.Error.creationFailed
            }
            return createCount.withLock { c in
                c += 1
                return c
            }
        }

        let pool = Pool.Bounded<Int>(
            capacity: 2,
            create: makeOne,
            destroy: { _ in }
        )

        async let r1: Int = pool.acquire { $0 }
        async let r2: Int = pool.acquire { $0 }

        let results = try await [r1, r2]
        #expect(Set(results) == Set([1, 2]))
        #expect(createCount.withLock { $0 } == 2)
    }

    @Test
    func `lazy pool increments created metric`() async throws {
        let pool = Pool.Bounded<Int>(
            capacity: 1,
            create: { 42 },
            destroy: { _ in }
        )

        let _: Int = try await pool.acquire { $0 }

        let created = pool._state.withLock { state in
            state.metrics.created
        }

        #expect(created == 1)
    }
}

// MARK: - Cancellation (replaces Timeout tests; deadlines compose externally)

extension PoolBoundedTests.EdgeCase {
    #if DEBUG
    @Test
    func `cancellation while waiting throws cancelled`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        unsafe pool.onEnqueue = { waiterEnqueued.open() }

        // The Task returns the lifecycle error directly. Because the
        // do/catch is INSIDE the Task closure, the implicit `error` binding
        // inside catch is typed as Either<...> per [IMPL-075] — no cast,
        // no Mutex capture, no Task<Success, Failure> erasure dance.
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
    #endif

    #if DEBUG
    @Test
    func `shutdown wins over cancellation`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        unsafe pool.onEnqueue = { waiterEnqueued.open() }

        let task: Task<Pool.Lifecycle.Error?, Never> = Task {
            do throws(Either<Pool.Lifecycle.Error, Never>) {
                let _: Int = try await pool.acquire { $0 }
                return Pool.Lifecycle.Error?.none
            } catch {
                switch error {
                case .left(let err):
                    return err
                }
            }
        }

        await waiterEnqueued.wait()

        pool.shutdown()
        await pool.shutdown.wait()

        let error = await task.value
        #expect(error == .shutdown)
    }
    #endif
}

// MARK: - Constraint Relaxation Proof
//
// Pool.Bounded<Resource> works with `Resource: ~Copyable` only — no Sendable
// constraint. This test proves the relaxation by instantiating the pool with
// a struct that is `~Copyable` and explicitly NOT Sendable.

private struct NonSendableHandle: ~Copyable {
    var value: Int
}

extension PoolBoundedTests.Unit {
    @Test
    func `pool works with non-Sendable Resource`() async throws {
        let pool = Pool.Bounded<NonSendableHandle>(
            capacity: 1,
            destroy: { _ in }
        )

        try pool.fill(NonSendableHandle(value: 7))

        let result: Int = try await pool.acquire { (handle: inout sending NonSendableHandle) async -> Int in
            handle.value += 1
            return handle.value
        }

        #expect(result == 8)

        // Mutation persisted across acquire-release.
        let after: Int = try await pool.acquire { handle in handle.value }
        #expect(after == 8)
    }
}

// MARK: - Performance

extension PoolBoundedTests.Performance {
    @Test
    func `acquire-release throughput`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        pool._state.withLock { state in
            let id = state.nextID(scope: pool.scope)
            pool.entries.underlying[0].move.in(0)
            state.transition(slot: 0, to: .available(id))
            state.pushAvailable(0)
        }

        // Warmup
        for _ in 0..<10 {
            let _: Int = try await pool.acquire { $0 }
        }

        // Measured
        for _ in 0..<100 {
            let _: Int = try await pool.acquire { $0 }
        }
    }
}
