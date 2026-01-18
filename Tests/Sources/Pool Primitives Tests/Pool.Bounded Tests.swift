import Async_Primitives
import Container_Primitives
import Dimension_Primitives
import Reference_Primitives
import Test_Primitives
import Testing
import Buffer_Primitives
import Synchronization
import Testing

@testable import Pool_Primitives

// Pool.Bounded is generic, so we test via a concrete helper namespace
// .serialized required because async tests may use shared executors
@Suite(.serialized)
enum PoolFixedTests {
    #Tests
}

// MARK: - Type Aliases

private typealias TestPool = Pool.Bounded<Int>

// MARK: - Test Helpers

private typealias SlotIndex = TestPool.Slot.Index
private typealias SlotState = TestPool.Slot.State

// MARK: - Unit Tests

extension PoolFixedTests.Test.Unit {
    @Test("eager pool acquires filled resource")
    func eagerPoolAcquiresFilledResource() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Fill the pool with a resource
        pool._state.withLock { state in
            let id = state.nextID(scope: pool.scope)
            pool.entries[0].move.in(42)
            state.transition(slot: SlotIndex(0), to: .available(id))
            state.pushAvailable(SlotIndex(0))
        }

        // Acquire and verify
        let result = try await pool { resource in
            resource
        }

        #expect(result == 42)
    }

    @Test("acquire increments metrics")
    func acquireIncrementsMetrics() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Fill the pool
        pool._state.withLock { state in
            let id = state.nextID(scope: pool.scope)
            pool.entries[0].move.in(100)
            state.transition(slot: SlotIndex(0), to: .available(id))
            state.pushAvailable(SlotIndex(0))
        }

        // Acquire
        _ = try await pool { $0 }

        let (acquisitions, releases) = pool._state.withLock { state in
            (state.metrics.acquisitions, state.metrics.releases)
        }

        #expect(acquisitions == 1)
        #expect(releases == 1)
    }

    @Test("resource mutation persists")
    func resourceMutationPersists() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Fill with initial value
        pool._state.withLock { state in
            let id = state.nextID(scope: pool.scope)
            pool.entries[0].move.in(0)
            state.transition(slot: SlotIndex(0), to: .available(id))
            state.pushAvailable(SlotIndex(0))
        }

        // Mutate
        _ = try await pool { resource in
            resource += 10
        }

        // Verify mutation persisted
        let value = try await pool { resource in
            resource
        }

        #expect(value == 10)
    }
}

// MARK: - Fill Tests

extension PoolFixedTests.Test.Unit {
    @Test("fill adds resource to empty slot")
    func fillAddsResourceToEmptySlot() async throws {
        let pool = TestPool(
            capacity: 2,
            destroy: { _ in }
        )

        // Fill one slot
        try pool.fill(42)

        // Verify we can acquire it
        let value = try await pool { $0 }
        #expect(value == 42)
    }

    @Test("fill hands off to waiting acquirer")
    func fillHandsOffToWaitingAcquirer() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Set up deterministic synchronization
        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        // Start acquire in background (will wait since pool is empty)
        let task = Task {
            try await pool { resource -> Int in
                resource
            }
        }

        // Wait until waiter is registered (deterministic rendezvous)
        await waiterEnqueued.wait()

        // Fill should hand off directly to waiter
        try pool.fill(99)

        // Task should complete with the filled value
        let result = try await task.value
        #expect(result == 99)
    }

    @Test("fill increments metrics")
    func fillIncrementsMetrics() throws {
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

// MARK: - Edge Cases

extension PoolFixedTests.Test.EdgeCase {
    @Test("shutdown rejects new acquisitions")
    func shutdownRejectsNewAcquisitions() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Start shutdown
        pool._state.withLock { state in
            _ = state.lifecycle.beginShutdown()
        }

        // Attempt acquire should fail
        await #expect(throws: Pool.Lifecycle.Error.shutdown) {
            try await pool { _ in }
        }
    }

    @Test("fill rejects when pool is full")
    func fillRejectsWhenPoolIsFull() throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        try pool.fill(1)

        #expect(throws: TestPool.Fill.Error.full) {
            try pool.fill(2)
        }
    }

    @Test("fill rejects during shutdown")
    func fillRejectsDuringShutdown() throws {
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

    @Test("shutdown drains available resources")
    func shutdownDrainsAvailableResources() async throws {
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

    @Test("shutdown wakes waiting acquirers")
    func shutdownWakesWaitingAcquirers() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Set up deterministic synchronization
        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        // Start an acquire that will wait (pool is empty)
        let task = Task {
            do {
                _ = try await pool { $0 }
                return false // Should not succeed
            } catch is Pool.Lifecycle.Error {
                return true // Expected: shutdown error
            } catch {
                return false
            }
        }

        // Wait until waiter is registered (deterministic rendezvous)
        await waiterEnqueued.wait()

        // Shutdown should wake the waiter
        pool.shutdown()
        await pool.shutdown.wait()

        let gotShutdownError = await task.value
        #expect(gotShutdownError)
    }
}

// MARK: - Lazy Policy Tests

extension PoolFixedTests.Test.Unit {
    @Test("lazy pool creates resource on demand")
    func lazyPoolCreatesResourceOnDemand() async throws {
        let createCount = Mutex(0)
        let pool = Pool.Bounded<Int>(
            capacity: 2,
            create: {
                createCount.withLock { $0 += 1 }
                return 42
            },
            destroy: { _ in }
        )

        // First acquire should create a resource
        let value = try await pool { $0 }
        #expect(value == 42)
        #expect(createCount.withLock { $0 } == 1)

        // Second acquire should reuse the returned resource
        _ = try await pool { $0 }
        #expect(createCount.withLock { $0 } == 1)
    }

    @Test("lazy pool reuses returned resource")
    func lazyPoolReusesReturnedResource() async throws {
        let createCount = Mutex(0)
        let pool = Pool.Bounded<Int>(
            capacity: 2,
            create: {
                createCount.withLock { $0 += 1 }
                return 42
            },
            destroy: { _ in }
        )

        // First acquire creates
        let v1 = try await pool { $0 }
        #expect(v1 == 42)
        #expect(createCount.withLock { $0 } == 1)

        // Second acquire reuses (no new creation)
        let v2 = try await pool { $0 }
        #expect(v2 == 42)
        #expect(createCount.withLock { $0 } == 1)
    }

    @Test("lazy pool creates up to capacity concurrently")
    func lazyPoolCreatesUpToCapacityConcurrently() async throws {
        let createCount = Mutex(0)
        // Barrier ensures both creates have started before either completes
        let barrier = Async.Barrier(parties: 2)

        let pool = Pool.Bounded<Int>(
            capacity: 2,
            create: {
                // Wait for both creates to start (proves concurrency)
                await barrier.arrive()
                return createCount.withLock { c in
                    c += 1
                    return c
                }
            },
            destroy: { _ in }
        )

        // Both tasks start concurrently
        async let r1 = pool { $0 }
        async let r2 = pool { $0 }

        let results = try await [r1, r2]
        #expect(Set(results) == Set([1, 2]))
        #expect(createCount.withLock { $0 } == 2)
    }

    @Test("lazy pool increments created metric")
    func lazyPoolIncrementsCreatedMetric() async throws {
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

extension PoolFixedTests.Test.Unit {
    @Test("acquire with timeout succeeds when resource available")
    func acquireWithTimeoutSucceedsWhenResourceAvailable() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        try pool.fill(42)

        let result = try await pool.acquire.timeout(.seconds(1))({ $0 })
        #expect(result == 42)
    }

    @Test("acquire with timeout times out when no resource")
    func acquireWithTimeoutTimesOutWhenNoResource() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Pool is empty - should timeout (use very short timeout)
        await #expect(throws: Pool.Lifecycle.Error.timeout) {
            try await pool.acquire.timeout(.nanoseconds(1))({ $0 })
        }
    }

    @Test("acquire with timeout optional returns nil on timeout")
    func acquireWithTimeoutOptionalReturnsNilOnTimeout() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Pool is empty - should return nil (use very short timeout)
        let result = try await pool.acquire.timeout(.nanoseconds(1)).optional({ $0 })
        #expect(result == nil)
    }

    @Test("acquire with timeout optional returns value when available")
    func acquireWithTimeoutOptionalReturnsValueWhenAvailable() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        try pool.fill(99)

        let result = try await pool.acquire.timeout(.seconds(1)).optional({ $0 })
        #expect(result == 99)
    }

    @Test("timeout increments metrics")
    func timeoutIncrementsMetrics() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Pool is empty - will timeout (use very short timeout)
        _ = try? await pool.acquire.timeout(.nanoseconds(1))({ $0 })

        let metrics = pool.metrics
        #expect(metrics.timeouts == 1)
    }

    @Test("acquire succeeds before timeout expires")
    func acquireSucceedsBeforeTimeoutExpires() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Set up deterministic synchronization
        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        // Start acquire with long timeout
        let task = Task {
            try await pool.acquire.timeout(.seconds(60))({ $0 })
        }

        // Wait until waiter is registered (deterministic rendezvous)
        await waiterEnqueued.wait()

        // Fill the pool - should satisfy the waiting acquire
        try pool.fill(42)

        let result = try await task.value
        #expect(result == 42)

        // Should not have timed out
        #expect(pool.metrics.timeouts == 0)
    }
}

extension PoolFixedTests.Test.EdgeCase {
    @Test("shutdown wins over timeout")
    func shutdownWinsOverTimeout() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Set up deterministic synchronization
        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        // Start acquire with long timeout
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

        // Wait until waiter is registered (deterministic rendezvous)
        await waiterEnqueued.wait()

        // Shutdown should wake with shutdown error (wins over timeout)
        pool.shutdown()
        await pool.shutdown.wait()

        let error = await task.value
        #expect(error == .shutdown)
    }

    @Test("cancellation wins over timeout")
    func cancellationWinsOverTimeout() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Set up deterministic synchronization
        let waiterEnqueued = Async.Gate()
        pool.onWaiterEnqueued = { waiterEnqueued.open() }

        // Start acquire with long timeout
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

        // Wait until waiter is registered (deterministic rendezvous)
        await waiterEnqueued.wait()

        // Cancel should wake with cancelled error (wins over timeout)
        task.cancel()

        let error = await task.value
        #expect(error == .cancelled)
    }
}

// MARK: - Performance

extension PoolFixedTests.Test.Performance {
    @Test("acquire-release throughput", .timed(iterations: 100, warmup: 10))
    func acquireReleaseThroughput() async throws {
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in }
        )

        // Fill pool
        pool._state.withLock { state in
            let id = state.nextID(scope: pool.scope)
            pool.entries[0].move.in(0)
            state.transition(slot: SlotIndex(0), to: .available(id))
            state.pushAvailable(SlotIndex(0))
        }

        // Measure acquire-release cycles
        for _ in 0..<100 {
            _ = try await pool { $0 }
        }
    }
}
