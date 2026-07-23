#if POOL_CONCURRENCY
    // ===----------------------------------------------------------------------===//
    //
    // This source file is part of the swift-pools open source project
    //
    // Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-pools project authors
    // Licensed under Apache License v2.0
    //
    // See LICENSE for license information
    //
    // ===----------------------------------------------------------------------===//

    internal import Array_Primitive
    internal import Array_Primitives
    internal import Async_Mutex_Primitives
    internal import Async_Primitives
    internal import Async_Promise_Primitives
    internal import Async_Waiter_Primitives
    internal import Dimension_Primitives
    internal import Ownership_Primitives
    internal import Queue_Primitive
    internal import Queue_Primitives
    internal import Tagged_Collection_Primitives

    internal import Synchronization
    internal import Column_Primitives
    internal import Fixed_Primitives
    internal import Buffer_Linear_Bounded_Primitive
    internal import Buffer_Linear_Primitive
    internal import Ownership_Shared_Primitive
    internal import Storage_Contiguous_Primitives
    internal import Memory_Heap_Primitives
    internal import Memory_Allocator_Primitive
    internal import Buffer_Primitive

    // MARK: - Shutdown Accessor

    extension Pool.Bounded where Resource: ~Copyable {
        /// Accessor for shutdown operations.
        public var shutdown: Shutdown {
            Shutdown(pool: self)
        }
    }

    // MARK: - Shutdown Type

    extension Pool.Bounded where Resource: ~Copyable {
        /// Namespace for pool shutdown operations.
        public struct Shutdown: Sendable {
            @usableFromInline
            let pool: Pool.Bounded<Resource>

            @usableFromInline
            init(pool: Pool.Bounded<Resource>) {
                self.pool = pool
            }
        }
    }

    // MARK: - Shutdown Operations

    extension Pool.Bounded.Shutdown where Resource: ~Copyable {
        /// Initiates graceful shutdown.
        ///
        /// After calling this:
        /// - New acquisitions are rejected with `.shutdown`
        /// - New fills are rejected with `.shutdown`
        /// - Outstanding checkouts become terminal when their bodies complete
        /// - Resources are destroyed as they are returned
        ///
        /// Every caller joins the same shutdown and returns only after all tracked
        /// creation and disposal work has completed.
        nonisolated(nonsending)
            public func callAsFunction() async
        {
            // Phase 1: Begin shutdown and collect what needs to be done
            // All side-outputs embedded in Drain to avoid capturing
            // mutable variables across the withLock sending boundary.
            let action: Drain = pool._state.withLock { state in
                // Begin shutdown (idempotent)
                guard state.lifecycle.shutdown.begin() else {
                    return .alreadyShuttingDown
                }

                // Collect slots to drain
                var slotsToDrain: [(Pool.Bounded<Resource>.Slot.Index, Pool.ID)] = []
                while let slotIndex = state.popAvailable() {
                    guard case .available(let id) = state.slots[slotIndex].state else {
                        continue
                    }
                    // Mark for disposal under lock
                    state.transition(slot: slotIndex, to: .disposing(id))
                    slotsToDrain.append((slotIndex, id))
                }

                // Drain all waiters with shutdown error (local array, no external capture)
                // reason: `[T]` sugar always means Swift.Array (requires Copyable);
                // this module's `Array<E: ~Copyable>` (Array_Primitive front door) is
                // what `Async.Waiter.Resumption` (~Copyable) actually needs — sugar
                // breaks the build here ("does not conform to protocol 'Copyable'").
                // swift-format-ignore: UseShorthandTypeNames
                // swiftlint:disable:next syntactic_sugar
                var resumptions = Array<Async.Waiter.Resumption>(initialCapacity: 0)
                state.waiters.drain { entry in
                    resumptions.append(entry.resumption(with: .failure(.shutdown)))
                }
                state.metrics.waiters = 0

                return .drain(slotsToDrain, resumptions: resumptions)
            }

            // Phase 2: Execute action OUTSIDE lock
            switch consume action {
            case .alreadyShuttingDown:
                await pool.shutdownGate.wait()
                return

            case .drain(let slotsToDrain, var resumptions):
                // Resume all waiters with shutdown error OUTSIDE lock
                resumptions.drain { $0.resume() }

                // Dispose each resource OUTSIDE lock (strict stance)
                for (slotIndex, _) in slotsToDrain {
                    // Move resource out OUTSIDE lock
                    let resource = pool.entries.underlying[slotIndex.retag(Pool.Bounded<Resource>.Entry.self)].move.out

                    // Destroy resource OUTSIDE lock
                    await pool.destructor(resource)

                    // Complete disposal and check shutdown
                    let effect: Pool.Bounded<Resource>.Effect = pool._state.withLock { state in
                        state.transition(slot: slotIndex, to: .empty)
                        state.metrics.closed += 1
                        return state.checkShutdownComplete()
                    }
                    pool.perform(effect)
                }

                // Final shutdown completion check (for case with no available slots)
                if slotsToDrain.isEmpty {
                    let effect: Pool.Bounded<Resource>.Effect = pool._state.withLock { state in
                        state.checkShutdownComplete()
                    }
                    pool.perform(effect)
                }

                await pool.shutdownGate.wait()
            }
        }
    }
#endif
