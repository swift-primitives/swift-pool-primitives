import Async_Mutex_Primitives
import Either_Primitives
import Fixed_Primitives
import Synchronization
import Testing

@testable import Pool_Bounded_Primitives
@_spi(Internal) @testable import Pool_Error_Primitives

// W3 rider — POOL's own composition under concurrency (arc-1,
// GOAL-tower-arc-shared-soundness §W3): the W5-3 leg (`e4d8e6c`) carries waiter
// hand-off through DIRECT-column resumption arrays
// (`Array<Column.Heap<Async.Waiter.Resumption>>`), mutated under `_state.withLock`
// and executed after unlock. The rider hammers exactly that lane: capacity-1
// hand-off chains, cancellation racing resumption (Pool.Lifecycle.Precedence),
// and shutdown draining pending waiters — with `pool.metrics` as the exact
// accounting oracle. Race-TOLERANT assertions where precedence makes either
// outcome lawful (a waiter cancelled after being resumed may complete); the
// invariants asserted are the ones that must hold under EVERY interleaving.

private typealias TestPool = Pool.Bounded<Int>

/// Prefills a capacity-1 pool (the Pool.Bounded.AsyncBody Tests idiom).
private func makePrefilled(_ value: Int) -> TestPool {
    let pool = TestPool(capacity: 1, destroy: { _ in })
    pool._state.withLock { state in
        let id = state.nextID(scope: pool.scope)
        pool.entries.underlying[0].move.in(value)
        state.transition(slot: 0, to: .available(id))
        state.pushAvailable(0)
    }
    return pool
}

/// Reference-typed atomic carriers (move-only `Atomic` cannot be captured by
/// multiple escaping closures directly).
private final class Counter: Sendable {
    let raw = Atomic<Int>(0)
}

extension Counter {
    func bump() { _ = raw.wrappingAdd(1, ordering: .relaxed) }
    var value: Int { raw.load(ordering: .sequentiallyConsistent) }
}

private final class Flag: Sendable {
    let raw = Atomic<Bool>(false)
}

extension Flag {
    func raise() { raw.store(true, ordering: .sequentiallyConsistent) }
    var isRaised: Bool { raw.load(ordering: .sequentiallyConsistent) }
}

extension `Pool.Bounded Tests` {

    @Test(arguments: [8, 24])
    func `capacity-1 hand-off chain: every waiter resumes exactly once`(width: Int) async throws {
        let pool = makePrefilled(7)
        let bodies = Counter()
        let results = await withTaskGroup(of: Int?.self, returning: [Int?].self) { group in
            for _ in 0..<width {
                group.addTask {
                    do throws(Either<Pool.Lifecycle.Error, Never>) {
                        return try await pool.acquire { resource in
                            bodies.bump()
                            await Task.yield()  // hold the slot across a suspension
                            return .reusable(resource &* 2)
                        }
                    } catch {
                        return nil
                    }
                }
            }
            var out: [Int?] = []
            for await r in group { out.append(r) }
            return out
        }
        #expect(results.count == width)
        #expect(results.allSatisfy { $0 == 14 })  // everyone saw THE resource
        #expect(bodies.value == width)  // no lost, no double hand-off
        let metrics = pool.metrics
        #expect(metrics.acquisitions == UInt64(width))
        #expect(metrics.releases == UInt64(width))
        #expect(metrics.outstanding.current == 0)
        let after = try await pool.acquire { .reusable($0 &+ 1) }  // still serviceable
        #expect(after == 8)
        await pool.shutdown()
    }

    @Test
    func `cancellation races resumption without losing the resource`() async throws {
        let pool = makePrefilled(3)
        let release = Flag()
        let occupantRunning = Flag()
        let occupant = Task {
            try await pool.acquire { resource in
                occupantRunning.raise()
                while !release.isRaised { await Task.yield() }
                return .reusable(resource)
            }
        }
        while !occupantRunning.isRaised { await Task.yield() }

        let completions = Counter()
        let cancellations = Counter()
        let queued = Counter()
        pool.enqueue.withLock { $0 = { queued.bump() } }
        var waiters: [Task<Void, Never>] = []
        for _ in 0..<12 {
            waiters.append(
                Task {
                    do throws(Either<Pool.Lifecycle.Error, Never>) {
                        _ = try await pool.acquire { resource in .reusable(resource) }
                        completions.bump()
                    } catch {
                        cancellations.bump()
                    }
                }
            )
        }
        while queued.value < 12 { await Task.yield() }  // deterministic: enqueue hook
        for (index, waiter) in waiters.enumerated() where index % 2 == 0 {
            waiter.cancel()  // cancel half, racing the queue
        }
        release.raise()  // hand-off chain starts
        for waiter in waiters { await waiter.value }
        _ = try await occupant.value

        // Precedence makes per-waiter outcomes racy (cancelled-after-resumed may
        // complete); the EVERY-interleaving invariants:
        #expect(completions.value + cancellations.value == 12)
        #expect(completions.value >= 6)  // uncancelled waiters always complete
        let metrics = pool.metrics
        #expect(metrics.releases == metrics.acquisitions)
        #expect(metrics.outstanding.current == 0)
        let after = try await pool.acquire { .reusable($0 &* 10) }  // the resource survived the storm
        #expect(after == 30)
        await pool.shutdown()
    }

    @Test
    func `shutdown drains every pending waiter and completes after the holder releases`() async throws {
        let pool = makePrefilled(5)
        let release = Flag()
        let occupantRunning = Flag()
        let occupant = Task {
            do throws(Either<Pool.Lifecycle.Error, Never>) {
                let value = try await pool.acquire { resource in
                    occupantRunning.raise()
                    while !release.isRaised { await Task.yield() }
                    return .reusable(resource)
                }
                return Result<Int, Pool.Lifecycle.Error>.success(value)
            } catch {
                switch error {
                case .left(let lifecycle):
                    return .failure(lifecycle)
                }
            }
        }
        while !occupantRunning.isRaised { await Task.yield() }

        let drained = Counter()
        let unexpected = Counter()
        let queued = Counter()
        pool.enqueue.withLock { $0 = { queued.bump() } }
        var waiters: [Task<Void, Never>] = []
        for _ in 0..<10 {
            waiters.append(
                Task {
                    do throws(Either<Pool.Lifecycle.Error, Never>) {
                        _ = try await pool.acquire { resource in .reusable(resource) }
                        unexpected.bump()  // no slot can ever reach them
                    } catch {
                        drained.bump()
                    }
                }
            )
        }
        while queued.value < 10 { await Task.yield() }  // deterministic: enqueue hook

        let shutdown = Task { await pool.shutdown() }
        for waiter in waiters { await waiter.value }  // liveness: nobody is stranded
        #expect(drained.value == 10)
        #expect(unexpected.value == 0)

        release.raise()  // holder releases into shutdown
        switch await occupant.value {
        case .failure(.shutdown):
            break

        case .failure(let other):
            Issue.record("Expected shutdown, got \(other)")

        case .success:
            Issue.record("Expected concurrent shutdown")
        }
        await shutdown.value

        do throws(Either<Pool.Lifecycle.Error, Never>) {
            _ = try await pool.acquire { resource in .reusable(resource) }
            #expect(Bool(false), "acquire after shutdown must throw")
        } catch {
            #expect(Bool(true))
        }
        let metrics = pool.metrics
        #expect(metrics.outstanding.current == 0)
    }

    @Test
    func `suspend racing disposal completion claims the empty lazy slot`() async throws(Pool.Lifecycle.Error) {
        // Lazy sibling of the lost-wakeup window: an acquirer decides `.suspend`
        // while the only slot is busy; the disposal then completes with no
        // queued waiter, so `complete(disposalAt:)` sees no demand and leaves
        // the slot `.empty` with no replacement. The acquirer's pre-enqueue
        // re-check must claim the empty slot and create on its own behalf —
        // enqueueing would strand it until unrelated future traffic.
        let created = Counter()
        let pool = TestPool(
            capacity: 1,
            create: { () throws(Pool.Lifecycle.Error) -> Int in
                created.bump()
                return created.value &* 10
            },
            destroy: { _ in }
        )

        // Produce the post-window state through a real disposal: the acquire
        // creates the resource, `.invalid` disposes it, and with zero queued
        // waiters `complete(disposalAt:)` declines replacement — the slot is
        // left `.empty`.
        let first: Int
        do throws(Either<Pool.Lifecycle.Error, Never>) {
            first = try await pool.acquire { resource in .invalid(resource) }
        } catch {
            switch error {
            case .left(let lifecycle):
                throw lifecycle
            }
        }
        #expect(first == 10)
        #expect(created.value == 1)

        // The rescued acquirer must claim, never enqueue.
        let enqueued = Flag()
        pool.enqueue.withLock { $0 = { enqueued.raise() } }

        // Drive the suspension path directly: this IS the acquirer whose
        // `.suspend` decision predates the disposal completion above (the
        // decision arm mutates no state, so the pool cannot distinguish).
        let (slot, id) = try await pool.suspendForSlot()
        let value = pool.entries.underlying[0].move.out
        #expect(value == 20)  // created on the waiter's own behalf
        #expect(enqueued.isRaised == false)  // rescued via claim, not enqueue
        #expect(created.value == 2)
        _ = await pool.release(value, from: slot, id: id, as: .reusable)

        let metrics = pool.metrics
        #expect(metrics.acquisitions == 2)
        #expect(metrics.outstanding.current == 0)
        await pool.shutdown()
    }
}
