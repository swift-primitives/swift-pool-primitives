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
    internal import Async_Waiter_Primitives
    internal import Fixed_Primitives
    internal import Ownership_Primitives
    internal import Tagged_Collection_Primitives

    internal import Synchronization

    // MARK: - Slot Acquisition (Non-Embedded Only)
    //
    // The single waiting path. Pool no longer carries a deadline parameter or
    // internal timer machinery; non-blocking and timeout semantics compose
    // externally via Task cancellation.

    extension Pool.Bounded where Resource: ~Copyable {
        /// Acquires a slot, waiting indefinitely or until the calling Task is
        /// cancelled.
        ///
        /// ## Flow (Action Pattern)
        /// 1. Compute action under lock (pure value)
        /// 2. Execute action outside lock
        /// 3. For lazy create: two-phase commit (create → recheck lifecycle → install → commit)
        ///
        /// - Returns: Tuple of (slot index, Pool.ID for return validation).
        /// - Throws: `Pool.Lifecycle.Error` on shutdown or cancellation.
        @usableFromInline
        func acquireSlot() async throws(Pool.Lifecycle.Error) -> (Slot.Index, Pool.ID) {
            guard !Task.isCancelled else {
                throw .cancelled
            }

            // Phase 1: Compute action under lock
            let action: Acquire.Action = _state.withLock { state in
                // Check lifecycle
                guard !state.lifecycle.shutdown.isActive else {
                    return .shutdown
                }

                // Try immediate acquisition (LIFO for cache locality)
                if let slotIndex = state.popAvailable() {
                    guard case .available(let id) = state.slots[slotIndex].state else {
                        preconditionFailure("Available ring contains non-available slot")
                    }

                    // Mark as out under lock
                    state.transition(slot: slotIndex, to: .out(id))
                    state.metrics.acquisitions += 1
                    return .immediate(slotIndex, id)
                }

                // For lazy policy: try to reserve an empty slot for creation
                if case .lazy = policy {
                    if let slotIndex = state.findEmptySlot() {
                        let id = state.nextID(scope: scope)
                        state.transition(slot: slotIndex, to: .creating(id))
                        return .create(slotIndex, id)
                    }
                }

                // Must wait
                return .suspend
            }

            // Phase 2: Execute action OUTSIDE lock
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

        /// Creates a resource lazily using two-phase commit.
        ///
        /// ## Two-Phase Commit (Strict Stance)
        /// 1. Create resource OUTSIDE lock (user code)
        /// 2. Recheck lifecycle under lock
        /// 3. Install resource OUTSIDE lock
        /// 4. Commit state transition under lock
        @usableFromInline
        func createLazyResource(slotIndex: Slot.Index, id: Pool.ID) async throws(Pool.Lifecycle.Error) -> (Slot.Index, Pool.ID) {
            // Get creator from policy
            guard case .lazy(let creation) = policy else {
                preconditionFailure("createLazyResource called with non-lazy policy")
            }

            // Phase 1: Create resource OUTSIDE lock (user code).
            // The factory closure throws Pool.Lifecycle.Error directly per the
            // documented contract — the user wraps domain errors at the boundary.
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

        /// Replaces a terminal lazy resource before any queued acquisition resumes.
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

                // swift-format-ignore: UseShorthandTypeNames
                // swiftlint:disable:next syntactic_sugar
                var skipped = Array<Async.Waiter.Resumption>(initialCapacity: 0)
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

        /// Suspends waiting for a slot to become available.
        ///
        /// Cooperates with Task cancellation: when the calling Task is cancelled,
        /// the waiter flag is set and `pumpWaiters` reaps the waiter, throwing
        /// `.cancelled`. There is no internal timeout machinery — non-blocking
        /// and timeout semantics compose externally.
        @usableFromInline
        func suspendForSlot() async throws(Pool.Lifecycle.Error) -> (Slot.Index, Pool.ID) {
            let flag = Flag()

            // Suspend via checked continuation with cancellation handler
            let outcome: Outcome = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    // Re-check under lock before enqueueing. The `.suspend`
                    // decision was made under an EARLIER lock acquisition;
                    // shutdown, cancellation, or a release may have raced into
                    // the window between decision and enqueue:
                    //
                    // - Shutdown began: its drain already ran, so enqueueing
                    //   now would strand this waiter forever.
                    // - Cancellation fired: the pump saw an empty queue and
                    //   the monotonic flag never pumps again, so a flagged
                    //   entry enqueued now would never be reaped.
                    // - A release found no waiter and returned the slot to the
                    //   free-list instead of handing it off.
                    //
                    // The immediate resumption is computed under lock and
                    // executed outside via the single `perform` funnel.
                    let immediate: Async.Waiter.Resumption? = _state.withLock { state in
                        let waiter = Waiter.Entry(
                            continuation: Async.Continuation(continuation),
                            flag: flag,
                            metadata: Waiter.Metadata()
                        )

                        // Precedence: shutdown > cancellation > success.
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

                        // Lazy sibling of the release race: a disposal
                        // completed in the window with no queued waiter, so
                        // `complete(disposalAt:)` saw no demand and left the
                        // slot `.empty` without a replacement. Claim it for
                        // creation on this waiter's behalf (mirroring the
                        // lazy arm of the decision phase); the resumption
                        // carries the `.creating` reservation, which the
                        // post-await path completes via `createLazyResource`.
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
                // Only set flag, enqueue pump - never resume directly
                if flag.cancel() {
                    self.pumpWaiters()
                }
            }

            // Handle outcome
            switch outcome {
            case .success(let pair):
                // A success may carry a claimed `.creating` reservation
                // (see the pre-enqueue re-check) rather than an `.out`
                // hand-off. Only this waiter's own claim can pair this slot
                // with this ID in `.creating`, so the state read is
                // unambiguous; complete the creation before returning.
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
