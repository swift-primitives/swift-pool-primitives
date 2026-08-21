#if POOL_CONCURRENCY

    internal import Array_Primitive
    internal import Array_Primitives
    internal import Async_Mutex_Primitives
    internal import Async_Primitives
    internal import Async_Waiter_Primitives
    internal import Fixed_Primitives
    internal import Ownership_Primitives
    internal import Tagged_Collection_Primitives

    internal import Synchronization

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        func acquireSlot() async throws(Pool.Lifecycle.Error) -> (Slot.Index, Pool.ID) {
            guard !Task.isCancelled else {
                throw .cancelled
            }

            let action: Acquire.Action = _state.withLock { state in

                guard !state.lifecycle.shutdown.isActive else {
                    return .shutdown
                }

                if let slotIndex = state.popAvailable() {
                    guard case .available(let id) = state.slots[slotIndex].state else {
                        preconditionFailure("Available ring contains non-available slot")
                    }

                    state.transition(slot: slotIndex, to: .out(id))
                    state.metrics.acquisitions += 1
                    return .immediate(slotIndex, id)
                }

                if case .lazy = policy {
                    if let slotIndex = state.findEmptySlot() {
                        let id = state.nextID(scope: scope)
                        state.transition(slot: slotIndex, to: .creating(id))
                        return .create(slotIndex, id)
                    }
                }

                return .suspend
            }

            switch action {
            case .immediate(let slotIndex, let id):
                return (slotIndex, id)

            case .shutdown:
                throw .shutdown

            case .create(let slotIndex, let id):
                return try await createLazyResource(slotIndex: slotIndex, id: id)

            case .suspend:
                return try await suspendForSlot()
            }
        }

        @usableFromInline
        func createLazyResource(
            slotIndex: Slot.Index,
            id: Pool.ID
        ) async throws(Pool.Lifecycle.Error) -> (Slot.Index, Pool.ID) {

            guard case .lazy(let creation) = policy else {
                preconditionFailure("createLazyResource called with non-lazy policy")
            }

            let created: Resource
            do throws(Pool.Lifecycle.Error) {
                created = try await creation.create()
            } catch {
                var pending = _state.withLock { state in
                    state.transition(slot: slotIndex, to: .empty)
                    return state.fail(
                        waitersWith: state.lifecycle.shutdown.isActive ? .shutdown : error
                    )
                }
                pending.drain { $0.resume() }
                let effect = _state.withLock { state in state.checkShutdownComplete() }
                perform(effect)
                throw _state.withLock { state in
                    state.lifecycle.shutdown.isActive ? .shutdown : error
                }
            }

            var resource = created
            if let check = _check, !check(&resource) {
                _state.withLock { state in
                    state.transition(slot: slotIndex, to: .disposing(id))
                }
                await destructor(resource)
                await complete(disposalAt: slotIndex)
                throw _state.withLock { state in
                    state.lifecycle.shutdown.isActive ? .shutdown : .creationFailed
                }
            }

            entries.underlying[slotIndex.retag(Entry.self)].move.in(resource)

            let shouldDispose = _state.withLock { state in
                guard !state.lifecycle.shutdown.isActive else {
                    state.transition(slot: slotIndex, to: .disposing(id))
                    return true
                }
                state.transition(slot: slotIndex, to: .out(id))
                state.metrics.created += 1
                state.metrics.acquisitions += 1
                return false
            }

            if shouldDispose {
                let resource = entries.underlying[slotIndex.retag(Entry.self)].move.out
                await destructor(resource)
                await complete(disposalAt: slotIndex)
                throw .shutdown
            }

            return (slotIndex, id)
        }

        @usableFromInline
        func replace(slot slotIndex: Slot.Index, id: Pool.ID) async {
            guard case .lazy(let creation) = policy else {
                preconditionFailure("replace called with non-lazy policy")
            }

            let created: Resource
            do throws(Pool.Lifecycle.Error) {
                created = try await creation.create()
            } catch {
                var pending = _state.withLock { state in
                    state.transition(slot: slotIndex, to: .empty)
                    return state.fail(
                        waitersWith: state.lifecycle.shutdown.isActive ? .shutdown : error
                    )
                }
                pending.drain { $0.resume() }
                let effect = _state.withLock { state in state.checkShutdownComplete() }
                perform(effect)
                return
            }

            var resource = created
            if let check = _check, !check(&resource) {
                _state.withLock { state in
                    state.transition(slot: slotIndex, to: .disposing(id))
                }
                await destructor(resource)
                var pending = _state.withLock { state in
                    state.transition(slot: slotIndex, to: .empty)
                    state.metrics.closed += 1
                    return state.fail(
                        waitersWith: state.lifecycle.shutdown.isActive ? .shutdown : .creationFailed
                    )
                }
                pending.drain { $0.resume() }
                let effect = _state.withLock { state in state.checkShutdownComplete() }
                perform(effect)
                return
            }

            entries.underlying[slotIndex.retag(Entry.self)].move.in(resource)

            let commit: Fill.Commit = _state.withLock { state in
                guard !state.lifecycle.shutdown.isActive else {
                    state.transition(slot: slotIndex, to: .disposing(id))
                    return .dispose
                }

                var skipped = [Async.Waiter.Resumption](initialCapacity: 0)
                guard let waiter = state.dequeueEligibleWaiter(skipped: &skipped) else {
                    state.transition(slot: slotIndex, to: .available(id))
                    state.pushAvailable(slotIndex)
                    state.metrics.created += 1
                    return .addToPool(effect: .none, skipped: skipped)
                }

                state.transition(slot: slotIndex, to: .out(id))
                state.metrics.created += 1
                state.metrics.acquisitions += 1
                return .handOff(
                    waiter.resumption(with: .success((slotIndex, id))),
                    skipped: skipped
                )
            }

            switch consume commit {
            case .addToPool(let effect, var skipped):
                skipped.drain { $0.resume() }
                perform(effect)

            case .handOff(let resumption, var skipped):
                skipped.drain { $0.resume() }
                perform(.waiter(.resume(resumption)))

            case .dispose:
                let resource = entries.underlying[slotIndex.retag(Entry.self)].move.out
                await destructor(resource)
                await complete(disposalAt: slotIndex)
            }
        }

        @usableFromInline
        func suspendForSlot() async throws(Pool.Lifecycle.Error) -> (Slot.Index, Pool.ID) {
            let flag = Flag()

            let outcome: Outcome = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in

                    let immediate: Async.Waiter.Resumption? = _state.withLock { state in
                        let waiter = Waiter.Entry(
                            continuation: Async.Continuation(continuation),
                            flag: flag,
                            metadata: Waiter.Metadata()
                        )

                        guard !state.lifecycle.shutdown.isActive else {
                            return waiter.resumption(with: .failure(.shutdown))
                        }

                        guard !flag.isFlagged else {
                            return waiter.resumption(with: .failure(.cancelled))
                        }

                        if let slotIndex = state.popAvailable() {
                            guard case .available(let id) = state.slots[slotIndex].state else {
                                preconditionFailure("Available ring contains non-available slot")
                            }
                            state.transition(slot: slotIndex, to: .out(id))
                            state.metrics.acquisitions += 1
                            return waiter.resumption(with: .success((slotIndex, id)))
                        }

                        if case .lazy = policy, let slotIndex = state.findEmptySlot() {
                            let id = state.nextID(scope: scope)
                            state.transition(slot: slotIndex, to: .creating(id))
                            return waiter.resumption(with: .success((slotIndex, id)))
                        }

                        state.addWaiter(waiter)
                        return nil
                    }

                    switch consume immediate {
                    case .some(let resumption):
                        perform(.waiter(.resume(resumption)))

                    case .none:
                        #if DEBUG
                            let enqueue = self.enqueue.withLock { $0 }
                            enqueue?()
                        #endif
                    }
                }
            } onCancel: {

                if flag.cancel() {
                    self.pumpWaiters()
                }
            }

            switch outcome {
            case .success(let pair):

                if case .lazy = policy {
                    let mustCreate = _state.withLock { state in
                        if case .creating(let id) = state.slots[pair.0].state, id == pair.1 {
                            return true
                        }
                        return false
                    }
                    if mustCreate {
                        return try await createLazyResource(slotIndex: pair.0, id: pair.1)
                    }
                }
                return pair

            case .failure(let error):
                throw error
            }
        }
    }
#endif
