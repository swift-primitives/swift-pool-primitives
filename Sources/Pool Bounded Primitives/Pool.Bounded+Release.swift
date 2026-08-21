#if POOL_CONCURRENCY
    internal import Array_Primitive
    internal import Array_Primitives
    internal import Async_Mutex_Primitives
    internal import Async_Primitives
    internal import Async_Waiter_Primitives
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

        @usableFromInline
        func release(
            _ resource: consuming sending Resource,
            from slotIndex: Slot.Index,
            id: Pool.ID,
            as disposition: Release.Disposition
        ) async -> Pool.Lifecycle.Error? {
            var resource = resource
            let isReusable: Bool
            switch disposition {
            case .reusable:
                if let check = _check {
                    isReusable = check(&resource)
                } else {
                    isReusable = true
                }

            case .invalid:
                isReusable = false
            }

            guard isReusable else {
                _state.withLock { state in
                    guard case .out(let currentId) = state.slots[slotIndex].state,
                        currentId == id
                    else {
                        preconditionFailure("Release called with mismatched slot state or ID")
                    }
                    state.metrics.releases += 1
                    state.transition(slot: slotIndex, to: .disposing(id))
                }

                await destructor(resource)
                await complete(disposalAt: slotIndex)
                return _state.withLock { state in
                    state.lifecycle.shutdown.isActive ? .shutdown : nil
                }
            }

            entries.underlying[slotIndex.retag(Entry.self)].move.in(resource)

            let action: Release.Action = _state.withLock { state in

                guard case .out(let currentId) = state.slots[slotIndex].state,
                    currentId == id
                else {
                    preconditionFailure("Release called with mismatched slot state or ID")
                }

                state.metrics.releases += 1

                var skipped = [Async.Waiter.Resumption](initialCapacity: 0)

                if let waiter = state.dequeueEligibleWaiter(skipped: &skipped) {

                    state.metrics.acquisitions += 1
                    let resumption = waiter.resumption(with: .success((slotIndex, id)))
                    return .handOff(resumption, skipped: skipped)
                } else if state.lifecycle.shutdown.isActive {
                    state.transition(slot: slotIndex, to: .disposing(id))
                    return .dispose(skipped: skipped)
                } else {
                    state.transition(slot: slotIndex, to: .available(id))
                    state.pushAvailable(slotIndex)
                    return .returnToPool(skipped: skipped)
                }
            }

            switch consume action {
            case .handOff(let resumption, var skipped):
                skipped.drain { $0.resume() }

                perform(.waiter(.resume(resumption)))

            case .returnToPool(var skipped):
                skipped.drain { $0.resume() }

                let effect: Effect = _state.withLock { state in
                    state.checkShutdownComplete()
                }
                perform(effect)

            case .dispose(var skipped):
                skipped.drain { $0.resume() }

                let resource = entries.underlying[slotIndex.retag(Entry.self)].move.out

                await destructor(resource)

                let effect: Effect = _state.withLock { state in
                    state.transition(slot: slotIndex, to: .empty)
                    state.metrics.closed += 1
                    return state.checkShutdownComplete()
                }
                perform(effect)
                return .shutdown
            }

            return nil
        }

        @usableFromInline
        func complete(disposalAt slotIndex: Slot.Index) async {
            let replacement: (Slot.Index, Pool.ID)? = _state.withLock { state in
                state.transition(slot: slotIndex, to: .empty)
                state.metrics.closed += 1

                guard !state.lifecycle.shutdown.isActive,
                    case .lazy = policy,
                    state.metrics.waiters > 0
                else {
                    return nil
                }

                let id = state.nextID(scope: scope)
                state.transition(slot: slotIndex, to: .creating(id))
                return (slotIndex, id)
            }

            let effect = _state.withLock { state in
                state.checkShutdownComplete()
            }
            perform(effect)

            if let (slotIndex, id) = replacement {
                await replace(slot: slotIndex, id: id)
            }
        }
    }

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        func pumpWaiters() {

            var pending: [Async.Waiter.Resumption] = _state.withLock { state in
                state.reapFlaggedWaiters()
            }

            pending.drain { $0.resume() }
        }
    }
#endif
