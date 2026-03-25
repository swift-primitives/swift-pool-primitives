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
public import Dimension_Primitives
public import Async_Primitives
internal import Ownership_Primitives
public import Array_Primitives

// MARK: - Async Acquire (Non-Embedded Only)

#if !hasFeature(Embedded)
extension Pool.Bounded where Resource: ~Copyable & Sendable {
    // MARK: - Core Acquire (Non-throwing Body)

    /// Acquires a resource and executes a body with exclusive access.
    ///
    /// ## Invariants Upheld
    /// - **No user code under lock**: Body executes outside lock
    /// - **Single resumption site**: All waiter outcomes via `perform(_:)`
    /// - **Resume after removal**: Waiter resumed only after queue removal
    /// - **Entry access outside lock**: Strict stance - move.in/out outside lock
    /// - **Return is total**: Resource always returned via defer
    ///
    /// ## Error Semantics
    /// - Pool failure → `throws Pool.Lifecycle.Error`
    /// - Body never throws in this overload
    ///
    /// - Note: Only available on non-embedded platforms. On embedded, use
    ///   `acquire.try` or `acquire.callback` instead.
    ///
    /// - Parameter body: Closure receiving exclusive mutable access to resource.
    /// - Returns: The result of the body closure.
    /// - Throws: `Pool.Lifecycle.Error` on shutdown or cancellation.
    public func callAsFunction<T: Sendable>(
        _ body: (inout Resource) -> T
    ) async throws(Pool.Lifecycle.Error) -> T {
        // Phase 1: Acquire slot (may suspend)
        let (slotIndex, id) = try await acquireSlot()

        // Phase 2: Use resource OUTSIDE lock (strict stance)
        // INVARIANT: Return is total - defer ensures resource always returned
        defer { releaseSlot(slotIndex, id: id) }

        // Extract resource to local (OUTSIDE lock)
        var resource = entries[slotIndex].move.out

        // Phase 3: Execute body (NO LOCK HELD)
        // INVARIANT: No user code under lock
        let result = body(&resource)

        // Move resource back to entry (OUTSIDE lock)
        entries[slotIndex].move.in(resource)

        return result
    }

    // MARK: - Core Acquire (Throwing Body)

    /// Acquires a resource and executes a throwing body with exclusive access.
    ///
    /// ## Error Semantics (Strict Separation)
    /// - Pool failure → `throws Pool.Lifecycle.Error`
    /// - Body failure → `returns .failure(E)`
    /// - Body success → `returns .success(T)`
    ///
    /// **Never** represent pool failures as `Result.failure` - that breaks typed failure determinism.
    ///
    /// - Note: Only available on non-embedded platforms. On embedded, use
    ///   `acquire.try` or `acquire.callback` instead.
    ///
    /// - Parameter body: Throwing closure receiving exclusive mutable access.
    /// - Returns: `Result.success(T)` on body success, `Result.failure(E)` on body error.
    /// - Throws: `Pool.Lifecycle.Error` on shutdown or cancellation.
    public func callAsFunction<T: Sendable, E: Error>(
        _ body: (inout Resource) throws(E) -> T
    ) async throws(Pool.Lifecycle.Error) -> Result<T, E> {
        // Phase 1: Acquire slot (may suspend)
        let (slotIndex, id) = try await acquireSlot()

        // Phase 2: Use resource OUTSIDE lock
        defer { releaseSlot(slotIndex, id: id) }

        var resource = entries[slotIndex].move.out

        // Phase 3: Execute body, capture result
        let result: Result<T, E>
        do {
            let value = try body(&resource)
            result = .success(value)
        } catch let error {
            result = .failure(error)
        }

        entries[slotIndex].move.in(resource)

        return result
    }
}
#endif

// MARK: - Acquire Action

extension Pool.Bounded.Acquire where Resource: ~Copyable & Sendable {
    /// Actions computed under lock for slot acquisition.
    @usableFromInline
    enum Action: Sendable {
        /// Slot immediately available - return to caller.
        case immediate(Pool.Bounded<Resource>.Slot.Index, Pool.ID)

        #if !hasFeature(Embedded)
        /// Need to create resource lazily.
        case create(Pool.Bounded<Resource>.Slot.Index, Pool.ID)
        #endif

        /// Need to suspend and wait for slot.
        case suspend

        /// Pool is shutting down.
        case shutdown
    }
}

// MARK: - Async Slot Acquisition (Non-Embedded Only)

#if !hasFeature(Embedded)
extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Acquires a slot, waiting if necessary.
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
            guard !state.lifecycle.isShuttingDown else {
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
        guard case .lazy(let creator) = policy else {
            preconditionFailure("createLazyResource called with non-lazy policy")
        }

        // Phase 1: Create resource OUTSIDE lock (user code)
        let resource: Resource
        do {
            resource = try await creator.value.create()
        } catch {
            // Creation failed - release reservation, check shutdown
            let effect: Effect = _state.withLock { state in
                state.transition(slot: slotIndex, to: .empty)
                return state.checkShutdownComplete()
            }
            perform(effect)
            throw .creationFailed
        }

        // Phase 2: Recheck lifecycle before commit
        let shouldInstall: Bool = _state.withLock { state in
            if state.lifecycle.isShuttingDown {
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
                self.onWaiterEnqueued?()
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

// MARK: - Release

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Namespace for release operations.
    @usableFromInline
    enum Release {}
}

extension Pool.Bounded.Release where Resource: ~Copyable & Sendable {
    /// Actions computed under lock for slot release.
    ///
    /// Embeds skipped resumptions into each case to avoid capturing
    /// mutable variables across the `withLock` sending boundary.
    @usableFromInline
    enum Action: ~Copyable, Sendable {
        /// Hand off to waiting waiter.
        case handOff(Async.Waiter.Resumption, skipped: Array<Async.Waiter.Resumption>)

        /// Return to available pool.
        case returnToPool(skipped: Array<Async.Waiter.Resumption>)

        /// Dispose during shutdown.
        case dispose(skipped: Array<Async.Waiter.Resumption>)
    }
}

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
            } else if state.lifecycle.isShuttingDown {
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

// MARK: - State Helpers

extension Pool.Bounded.State where Resource: ~Copyable & Sendable {
    /// Finds an empty slot for lazy creation.
    ///
    /// - Returns: The index of an empty slot, or nil if none available.
    @usableFromInline
    func findEmptySlot() -> Pool.Bounded<Resource>.Slot.Index? {
        for slot in slots {
            if case .empty = slot.state {
                return slot.index
            }
        }
        return nil
    }

    /// Dequeues the first eligible waiter (not cancelled/timed out).
    ///
    /// Skipped waiters (cancelled/timed out) have their resumptions collected
    /// for execution outside the lock.
    ///
    /// - Parameter skipped: Array to collect resumptions for skipped waiters.
    /// - Returns: First eligible waiter, or nil.
    @usableFromInline
    mutating func dequeueEligibleWaiter(
        skipped: inout Array<Async.Waiter.Resumption>
    ) -> Pool.Bounded<Resource>.Waiter.Entry? {
        // Collect flagged entries
        var flagged = Async.Waiter.Queue.Drain<Pool.Bounded<Resource>.Waiter.Flagged>()
        let entry = waiters.popEligible(flaggedInto: &flagged)

        // Process flagged entries into resumptions
        let currentLifecycle = lifecycle
        var removedCount = entry != nil ? 1 : 0
        flagged.drain { flaggedEntry in
            removedCount += 1

            // Deconstruct in one step - explicit ownership transition
            let split = flaggedEntry.split()

            // Apply Pool's precedence: shutdown > cancel > timeout
            let outcome: Pool.Bounded<Resource>.Outcome = Pool.Lifecycle.Precedence.apply(
                lifecycle: currentLifecycle,
                cancelled: split.reason == .cancelled,
                timedOut: split.reason == .timedOut,
                outcome: split.reason == .cancelled ? .failure(.cancelled) : .failure(.timeout)
            )

            // Create resumption from consumed entry
            skipped.append(split.entry.resumption(with: outcome))
        }

        // Update metrics for removed entries
        metrics.waiters -= removedCount

        return entry
    }
}
