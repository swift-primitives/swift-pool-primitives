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

internal import Array_Primitives
internal import Array_Fixed_Primitives
internal import Array_Primitive
internal import Tagged_Collection_Primitives
internal import Async_Mutex_Primitives
public import Async_Primitives_Core
internal import Async_Waiter_Primitives
internal import Ownership_Primitives

#if !hasFeature(Embedded)
    internal import Synchronization
#endif

// MARK: - Slot Acquisition (Non-Embedded Only)
//
// The single waiting path. Pool no longer carries a deadline parameter or
// internal timer machinery; non-blocking and timeout semantics compose
// externally via Task cancellation.

#if !hasFeature(Embedded)
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
            let resource: Resource
            do throws(Pool.Lifecycle.Error) {
                resource = try await creation.create()
            } catch {
                // Creation failed - release reservation, check shutdown
                let effect: Effect = _state.withLock { state in
                    state.transition(slot: slotIndex, to: .empty)
                    return state.checkShutdownComplete()
                }
                perform(effect)
                throw error
            }

            // Phase 2: Recheck lifecycle before commit
            let shouldInstall: Bool = _state.withLock { state in
                if state.lifecycle.shutdown.isActive {
                    // Shutdown began during create - will dispose
                    state.transition(slot: slotIndex, to: .empty)
                    return false
                }
                return true
            }

            if !shouldInstall {
                // Destroy resource we just created (OUTSIDE lock)
                destructor(resource)
                // Check shutdown completion
                let effect: Effect = _state.withLock { state in
                    state.checkShutdownComplete()
                }
                perform(effect)
                throw .shutdown
            }

            // Phase 3: Install resource OUTSIDE lock (strict stance)
            entries[slotIndex].move.in(resource)

            // Phase 4: Commit state transition under lock
            _state.withLock { state in
                state.transition(slot: slotIndex, to: .out(id))
                state.metrics.created += 1
                state.metrics.acquisitions += 1
            }

            return (slotIndex, id)
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
                    _state.withLock { state in
                        let waiter = Waiter.Entry(
                            continuation: Async.Continuation(continuation),
                            flag: flag,
                            metadata: Waiter.Metadata()
                        )
                        state.addWaiter(waiter)
                    }

                    #if DEBUG
                        self.onEnqueue?()
                    #endif
                }
            } onCancel: {
                // Only set flag, enqueue pump - never resume directly
                if flag.cancel() {
                    Task { self.pumpWaiters() }
                }
            }

            // Handle outcome
            switch outcome {
            case .success(let pair):
                return pair

            case .failure(let error):
                throw error
            }
        }
    }
#endif
