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

#if !hasFeature(Embedded)
import Synchronization
#endif
public import Async_Primitives_Core
public import Async_Mutex_Primitives
public import Async_Waiter_Primitives
internal import Ownership_Primitives
public import Array_Primitives_Core
internal import Array_Dynamic_Primitives
internal import Array_Fixed_Primitives

// MARK: - Slot Release

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Releases a slot back to the pool using two-phase commit.
    ///
    /// ## Two-Phase Commit (Strict Stance)
    /// 1. Decide action under lock (no entry access)
    /// 2. Execute entry access OUTSIDE lock
    /// 3. Commit completion under lock
    ///
    /// - Parameters:
    ///   - slotIndex: The slot to release.
    ///   - id: The Pool.ID for validation.
    @usableFromInline
    func releaseSlot(_ slotIndex: Slot.Index, id: Pool.ID) {
        // Phase 1: Decide what to do under lock (no entry access)
        // All side-outputs embedded in Release.Action to avoid capturing
        // mutable variables across the withLock sending boundary.
        let action: Release.Action = _state.withLock { state in
            // Validate slot state
            guard case .out(let currentId) = state.slots[slotIndex].state,
                  currentId == id else {
                preconditionFailure("Release called with mismatched slot state or ID")
            }

            state.metrics.releases += 1

            // Local array for skipped resumptions (no external capture)
            var skipped = Array<Async.Waiter.Resumption>()

            // Try to hand off to waiter
            if let waiter = state.dequeueEligibleWaiter(skipped: &skipped) {
                // Slot stays .out - waiter takes ownership
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

        // Phase 2: Execute action OUTSIDE lock
        switch consume action {
        case .handOff(let resumption, var skipped):
            skipped.drain { $0.resume() }
            // Resource stays in entry - waiter gets it
            perform(.waiter(.resume(resumption)))

        case .returnToPool(var skipped):
            skipped.drain { $0.resume() }
            // Resource stays in entry - check shutdown
            let effect: Effect = _state.withLock { state in
                state.checkShutdownComplete()
            }
            perform(effect)

        case .dispose(var skipped):
            skipped.drain { $0.resume() }
            // Move resource out OUTSIDE lock
            let resource = entries[slotIndex].move.out

            // Destroy OUTSIDE lock
            destructor(resource)

            // Phase 3: Complete disposal under lock
            let effect: Effect = _state.withLock { state in
                state.transition(slot: slotIndex, to: .empty)
                state.metrics.closed += 1
                return state.checkShutdownComplete()
            }
            perform(effect)
        }
    }
}

// MARK: - Pump Waiters

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Pumps the waiter queue, resuming any flagged waiters.
    ///
    /// This is the reaping mechanism for timeout/cancel. When a waiter's flag
    /// is set (cancelled or timedOut), `pumpWaiters()` removes it from the queue
    /// and resumes it via deferred resumption.
    ///
    /// Called by:
    /// - Timeout task after `flag.timeout()` returns `true`
    /// - Cancellation handler after `flag.cancel()` returns `true`
    @usableFromInline
    func pumpWaiters() {
        // Return resumptions from withLock (no external capture)
        var pending: Array<Async.Waiter.Resumption> = _state.withLock { state in
            state.reapFlaggedWaiters()
        }

        // Resume OUTSIDE lock via single funnel
        pending.drain { $0.resume() }
    }
}
