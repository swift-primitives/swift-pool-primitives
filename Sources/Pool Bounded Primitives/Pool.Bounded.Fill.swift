#if POOL_CONCURRENCY
    internal import Array_Primitive
    internal import Array_Primitives
    internal import Async_Mutex_Primitives
    internal import Async_Primitives
    internal import Async_Waiter_Primitives
    internal import Dimension_Primitives
    public import Index_Primitives
    internal import Ownership_Primitives
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

    extension Pool.Bounded where Resource: ~Copyable {

        public var fill: Fill {
            Fill(pool: self)
        }
    }

    extension Pool.Bounded where Resource: ~Copyable {

        public struct Fill: Sendable {
            @usableFromInline
            let pool: Pool.Bounded<Resource>

            @usableFromInline
            init(pool: Pool.Bounded<Resource>) {
                self.pool = pool
            }
        }
    }

    extension Pool.Bounded.Fill where Resource: ~Copyable {

        nonisolated(nonsending)
            public func callAsFunction(
                _ resource: consuming sending Resource
            ) async throws(Pool.Bounded<Resource>.Fill.Error)
        {

            let action: Action = pool._state.withLock { state in

                guard case .eager = pool.policy else {
                    state.disposing += 1
                    return .notEager
                }

                guard !state.lifecycle.shutdown.isActive else {
                    if state.lifecycle == .closing {
                        state.disposing += 1
                    }
                    return .shutdown
                }

                guard let slotIndex = state.findEmptySlot() else {
                    state.disposing += 1
                    return .full
                }

                let id = state.nextID(scope: pool.scope)
                state.transition(slot: slotIndex, to: .creating(id))
                return .install(slotIndex, id)
            }

            switch action {
            case .notEager:
                await pool.destructor(resource)
                let effect = pool._state.withLock { state in
                    state.disposing -= 1
                    return state.checkShutdownComplete()
                }
                pool.perform(effect)
                throw .notEager

            case .shutdown:
                await pool.destructor(resource)
                let effect = pool._state.withLock { state in
                    if state.lifecycle == .closing {
                        state.disposing -= 1
                    }
                    return state.checkShutdownComplete()
                }
                pool.perform(effect)
                throw .shutdown

            case .full:
                await pool.destructor(resource)
                let effect = pool._state.withLock { state in
                    state.disposing -= 1
                    return state.checkShutdownComplete()
                }
                pool.perform(effect)
                throw .full

            case .install(let slotIndex, let id):
                var resource = resource

                if let check = pool._check, !check(&resource) {
                    pool._state.withLock { state in
                        state.transition(slot: slotIndex, to: .disposing(id))
                    }
                    await pool.destructor(resource)
                    let effect = pool._state.withLock { state in
                        state.transition(slot: slotIndex, to: .empty)
                        state.metrics.closed += 1
                        return state.checkShutdownComplete()
                    }
                    pool.perform(effect)
                    throw .invalid
                }

                let entryIndex = slotIndex.retag(Pool.Bounded<Resource>.Entry.self)
                pool.entries.underlying[entryIndex].move.in(resource)

                let commitAction: Commit = pool._state.withLock { state in
                    guard !state.lifecycle.shutdown.isActive else {
                        state.transition(slot: slotIndex, to: .disposing(id))
                        return .dispose
                    }

                    state.transition(slot: slotIndex, to: .available(id))
                    state.metrics.fills += 1

                    var skipped = [Async.Waiter.Resumption](initialCapacity: 0)

                    guard let waiter = state.dequeueEligibleWaiter(skipped: &skipped) else {

                        state.pushAvailable(slotIndex)
                        let effect = state.checkShutdownComplete()
                        return .addToPool(effect: effect, skipped: skipped)
                    }

                    state.transition(slot: slotIndex, to: .out(id))
                    state.metrics.acquisitions += 1
                    let resumption = waiter.resumption(with: .success((slotIndex, id)))
                    return .handOff(resumption, skipped: skipped)
                }

                switch consume commitAction {
                case .addToPool(let effect, var skipped):
                    skipped.drain { $0.resume() }
                    pool.perform(effect)

                case .handOff(let resumption, var skipped):
                    skipped.drain { $0.resume() }
                    pool.perform(.waiter(.resume(resumption)))

                case .dispose:
                    let entryIndex = slotIndex.retag(Pool.Bounded<Resource>.Entry.self)
                    let resource = pool.entries.underlying[entryIndex].move.out
                    await pool.destructor(resource)
                    let effect = pool._state.withLock { state in
                        state.transition(slot: slotIndex, to: .empty)
                        state.metrics.closed += 1
                        return state.checkShutdownComplete()
                    }
                    pool.perform(effect)
                    throw .shutdown
                }
            }
        }
    }

    extension Pool.Bounded.Fill where Resource: ~Copyable {

        nonisolated(nonsending)
            public func batch(
                _ produce: () -> Resource?
            ) async throws(Pool.Bounded<Resource>.Fill.Error) -> Index<Resource>.Count
        {
            var count: Index<Resource>.Count = .zero

            while let resource = produce() {
                do throws(Pool.Bounded<Resource>.Fill.Error) {
                    try await self(resource)
                    count += .one
                } catch .full {

                    break
                } catch {
                    throw error
                }
            }

            return count
        }
    }
#endif
