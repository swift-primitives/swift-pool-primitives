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

    // MARK: - Slot Release

    extension Pool.Bounded where Resource: ~Copyable {
        /// Releases a slot back to the pool using two-phase commit.
        ///
        /// ## Two-Phase Commit (Strict Stance)
        /// 1. Decide action under lock (no entry access)
        /// 2. Execute entry access OUTSIDE lock
        /// 3. Commit completion under lock
        ///
        /// - Parameters:
        ///   - resource: Resource whose exclusive ownership is returned.
        ///   - slotIndex: The slot to release.
        ///   - id: The Pool.ID for validation.
        ///   - disposition: Whether the resource may be reused.
        /// - Returns: A terminal lifecycle error, or `nil` after a reusable return.
        @usableFromInline
        func release(
            _ resource: consuming Resource,
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

            // Phase 1: Decide what to do under lock (no entry access)
            // All side-outputs embedded in Release.Action to avoid capturing
            // mutable variables across the withLock sending boundary.
            let action: Release.Action = _state.withLock { state in
                // Validate slot state
                guard case .out(let currentId) = state.slots[slotIndex].state,
                    currentId == id
                else {
                    preconditionFailure("Release called with mismatched slot state or ID")
                }

                state.metrics.releases += 1

                // Local array for skipped resumptions (no external capture)
                // reason: `[T]` sugar always means Swift.Array (requires Copyable);
                // this module's `Array<E: ~Copyable>` (Array_Primitive front door) is
                // what `Async.Waiter.Resumption` (~Copyable) actually needs — sugar
                // breaks the build here ("does not conform to protocol 'Copyable'").
                // swift-format-ignore: UseShorthandTypeNames
                // swiftlint:disable:next syntactic_sugar
                var skipped = Array<Async.Waiter.Resumption>(initialCapacity: 0)

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
                let resource = entries.underlying[slotIndex.retag(Entry.self)].move.out

                // Destroy OUTSIDE lock
                await destructor(resource)

                // Phase 3: Complete disposal under lock
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

        /// Completes one tracked disposal and replaces an invalid lazy resource when needed.
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

    // MARK: - Pump Waiters

    extension Pool.Bounded where Resource: ~Copyable {
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
            // reason: `[T]` sugar always means Swift.Array (requires Copyable);
            // this module's `Array<E: ~Copyable>` (Array_Primitive front door) is
            // what `Async.Waiter.Resumption` (~Copyable) actually needs — sugar
            // breaks the build here ("does not conform to protocol 'Copyable'").
            // swift-format-ignore: UseShorthandTypeNames
            // swiftlint:disable:next syntactic_sugar
            var pending: Array<Async.Waiter.Resumption> = _state.withLock { state in
                state.reapFlaggedWaiters()
            }

            // Resume OUTSIDE lock via single funnel
            pending.drain { $0.resume() }
        }
    }
#endif
