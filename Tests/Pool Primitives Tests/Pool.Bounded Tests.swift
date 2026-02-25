import Testing
import Synchronization
import Async_Primitives
import Pool_Primitives_Test_Support

@testable import Pool_Primitives

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
            pool.entries[0].move.in(42)
            state.transition(slot: 0, to: .available(id))
            state.pushAvailable(0)
        }

        let result = try await pool { resource in
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
            pool.entries[0].move.in(100)
            state.transition(slot: 0, to: .available(id))
            state.pushAvailable(0)
        }

        _ = try await pool { $0 }

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
            pool.entries[0].move.in(0)
            state.transition(slot: 0, to: .available(id))
            state.pushAvailable(0)
        }

        _ = try await pool { resource in
            resource += 10
        }

        let value = try await pool { resource in
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

        let value = try await pool { $0 }
        #expect(value == 42)
    }

    @Test
    func `fill hands off to waiting acquirer`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        let task = Task {
            try await pool { resource -> Int in
                resource
            }
        }

        await waiterEnqueued.wait()

        try pool.fill(99)

        let result = try await task.value
        #expect(result == 99)
    }

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
            _ = state.lifecycle.beginShutdown()
        }

        await #expect(throws: Pool.Lifecycle.Error.shutdown) {
            try await pool { _ in }
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
            _ = state.lifecycle.beginShutdown()
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

    @Test
    func `shutdown wakes waiting acquirers`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        let task = Task {
            do {
                _ = try await pool { $0 }
                return false
            } catch is Pool.Lifecycle.Error {
                return true
            } catch {
                return false
            }
        }

        await waiterEnqueued.wait()

        pool.shutdown()
        await pool.shutdown.wait()

        let gotShutdownError = await task.value
        #expect(gotShutdownError)
    }
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

        let value = try await pool { $0 }
        #expect(value == 42)
        #expect(createCount.withLock { $0 } == 1)

        _ = try await pool { $0 }
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

        let v1 = try await pool { $0 }
        #expect(v1 == 42)
        #expect(createCount.withLock { $0 } == 1)

        let v2 = try await pool { $0 }
        #expect(v2 == 42)
        #expect(createCount.withLock { $0 } == 1)
    }

    @Test
    func `lazy pool creates up to capacity concurrently`() async throws {
        let createCount = Mutex(0)
        let barrier = Async.Barrier(parties: 2)

        let pool = Pool.Bounded<Int>(
            capacity: 2,
            create: {
                await barrier.arrive()
                return createCount.withLock { c in
                    c += 1
                    return c
                }
            },
            destroy: { _ in }
        )

        async let r1 = pool { $0 }
        async let r2 = pool { $0 }

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

        _ = try await pool { $0 }

        let created = pool._state.withLock { state in
            state.metrics.created
        }

        #expect(created == 1)
    }
}

// MARK: - Timeout Tests

extension PoolBoundedTests.Unit {
    @Test
    func `acquire with timeout succeeds when resource available`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        try pool.fill(42)

        let result = try await pool.acquire.timeout(.seconds(1))({ $0 })
        #expect(result == 42)
    }

    @Test
    func `acquire with timeout times out when no resource`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        await #expect(throws: Pool.Lifecycle.Error.timeout) {
            try await pool.acquire.timeout(.nanoseconds(1))({ $0 })
        }
    }

    @Test
    func `acquire with timeout optional returns nil on timeout`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let result = try await pool.acquire.timeout(.nanoseconds(1)).optional({ $0 })
        #expect(result == nil)
    }

    @Test
    func `acquire with timeout optional returns value when available`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        try pool.fill(99)

        let result = try await pool.acquire.timeout(.seconds(1)).optional({ $0 })
        #expect(result == 99)
    }

    @Test
    func `timeout increments metrics`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        _ = try? await pool.acquire.timeout(.nanoseconds(1))({ $0 })

        let metrics = pool.metrics
        #expect(metrics.timeouts == 1)
    }

    @Test
    func `acquire succeeds before timeout expires`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        let task = Task {
            try await pool.acquire.timeout(.seconds(60))({ $0 })
        }

        await waiterEnqueued.wait()

        try pool.fill(42)

        let result = try await task.value
        #expect(result == 42)

        #expect(pool.metrics.timeouts == 0)
    }
}

extension PoolBoundedTests.EdgeCase {
    @Test
    func `shutdown wins over timeout`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        let task = Task {
            do {
                _ = try await pool.acquire.timeout(.seconds(60))({ $0 })
                return Pool.Lifecycle.Error?.none
            } catch let error as Pool.Lifecycle.Error {
                return error
            } catch {
                return nil
            }
        }

        await waiterEnqueued.wait()

        pool.shutdown()
        await pool.shutdown.wait()

        let error = await task.value
        #expect(error == .shutdown)
    }

    @Test
    func `cancellation wins over timeout`() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        let task = Task {
            do {
                _ = try await pool.acquire.timeout(.seconds(60))({ $0 })
                return Pool.Lifecycle.Error?.none
            } catch let error as Pool.Lifecycle.Error {
                return error
            } catch {
                return nil
            }
        }

        await waiterEnqueued.wait()

        task.cancel()

        let error = await task.value
        #expect(error == .cancelled)
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
            pool.entries[0].move.in(0)
            state.transition(slot: 0, to: .available(id))
            state.pushAvailable(0)
        }

        // Warmup
        for _ in 0..<10 {
            _ = try await pool { $0 }
        }

        // Measured
        for _ in 0..<100 {
            _ = try await pool { $0 }
        }
    }
}
