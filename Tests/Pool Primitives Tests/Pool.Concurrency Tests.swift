import Async_Mutex_Primitives
import Fixed_Primitives
import Synchronization
import Testing

@testable import Pool_Bounded_Primitives
@_spi(Internal) @testable import Pool_Primitives_Core

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
    func bump() { _ = raw.wrappingAdd(1, ordering: .relaxed) }
    var value: Int { raw.load(ordering: .sequentiallyConsistent) }
}

private final class Flag: Sendable {
    let raw = Atomic<Bool>(false)
    func raise() { raw.store(true, ordering: .sequentiallyConsistent) }
    var isRaised: Bool { raw.load(ordering: .sequentiallyConsistent) }
}

@Suite("Pool concurrency (W3 rider)")
struct PoolConcurrencyTests {

    @Test(arguments: [8, 24])
    func `capacity-1 hand-off chain: every waiter resumes exactly once`(width: Int) async throws {
        let pool = makePrefilled(7)
        let bodies = Counter()
        let results = await withTaskGroup(of: Int?.self, returning: [Int?].self) { group in
            for _ in 0..<width {
                group.addTask {
                    try? await pool.acquire { resource in
                        bodies.bump()
                        await Task.yield()               // hold the slot across a suspension
                        return resource &* 2
                    }
                }
            }
            var out: [Int?] = []
            for await r in group { out.append(r) }
            return out
        }
        #expect(results.count == width)
        #expect(results.allSatisfy { $0 == 14 })         // everyone saw THE resource
        #expect(bodies.value == width)                   // no lost, no double hand-off
        let metrics = pool.metrics
        #expect(metrics.acquisitions == UInt64(width))
        #expect(metrics.releases == UInt64(width))
        #expect(metrics.outstanding.current == 0)
        let after = try await pool.acquire { $0 &+ 1 }   // still serviceable
        #expect(after == 8)
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
                return resource
            }
        }
        while !occupantRunning.isRaised { await Task.yield() }

        let completions = Counter()
        let cancellations = Counter()
        var waiters: [Task<Void, Never>] = []
        for _ in 0..<12 {
            waiters.append(Task {
                do {
                    _ = try await pool.acquire { resource in resource }
                    completions.bump()
                } catch {
                    cancellations.bump()
                }
            })
        }
        for _ in 0..<50 { await Task.yield() }           // let waiters queue
        for (index, waiter) in waiters.enumerated() where index % 2 == 0 {
            waiter.cancel()                              // cancel half, racing the queue
        }
        release.raise()                                  // hand-off chain starts
        for waiter in waiters { await waiter.value }
        _ = try await occupant.value

        // Precedence makes per-waiter outcomes racy (cancelled-after-resumed may
        // complete); the EVERY-interleaving invariants:
        #expect(completions.value + cancellations.value == 12)
        #expect(completions.value >= 6)                  // uncancelled waiters always complete
        let metrics = pool.metrics
        #expect(metrics.releases == metrics.acquisitions)
        #expect(metrics.outstanding.current == 0)
        let after = try await pool.acquire { $0 &* 10 }  // the resource survived the storm
        #expect(after == 30)
    }

    @Test
    func `shutdown drains every pending waiter and completes after the holder releases`() async throws {
        let pool = makePrefilled(5)
        let release = Flag()
        let occupantRunning = Flag()
        let occupant = Task {
            try await pool.acquire { resource in
                occupantRunning.raise()
                while !release.isRaised { await Task.yield() }
                return resource
            }
        }
        while !occupantRunning.isRaised { await Task.yield() }

        let drained = Counter()
        let unexpected = Counter()
        var waiters: [Task<Void, Never>] = []
        for _ in 0..<10 {
            waiters.append(Task {
                do {
                    _ = try await pool.acquire { resource in resource }
                    unexpected.bump()                    // no slot can ever reach them
                } catch {
                    drained.bump()
                }
            })
        }
        for _ in 0..<50 { await Task.yield() }           // let waiters queue

        pool.shutdown()                                  // drain the resumption arrays
        for waiter in waiters { await waiter.value }     // liveness: nobody is stranded
        #expect(drained.value == 10)
        #expect(unexpected.value == 0)

        release.raise()                                  // holder releases into shutdown
        let held = try await occupant.value
        #expect(held == 5)
        await pool.shutdown.wait()                       // full drain completes

        do {
            _ = try await pool.acquire { resource in resource }
            #expect(Bool(false), "acquire after shutdown must throw")
        } catch {
            #expect(Bool(true))
        }
        let metrics = pool.metrics
        #expect(metrics.outstanding.current == 0)
    }
}
