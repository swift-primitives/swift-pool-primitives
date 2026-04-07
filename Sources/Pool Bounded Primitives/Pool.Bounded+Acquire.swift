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
public import Async_Primitives_Core
public import Async_Mutex_Primitives
public import Async_Waiter_Primitives
internal import Ownership_Primitives
public import Array_Primitives_Core
internal import Array_Dynamic_Primitives
internal import Array_Fixed_Primitives

// MARK: - Direct Acquire (Non-Embedded Only)
//
// Convention: ownership-transfer-conventions.md
// - No `T: Sendable` constraint: T flows out only via the body return; the
//   function is `nonisolated(nonsending)` so the caller's isolation is
//   preserved and `T` never crosses a boundary.
// - Returns are `sending T`: one-time ownership transfer back to the caller.
// - `nonisolated(nonsending)` is explicit (canonical form) even though
//   `NonisolatedNonsendingByDefault` is enabled.
// - Async-body overloads use the double-nonsending pattern.

#if !hasFeature(Embedded)
extension Pool.Bounded where Resource: ~Copyable & Sendable {
    // MARK: - Sync Body (Non-throwing)

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
    nonisolated(nonsending)
    public func callAsFunction<T>(
        _ body: (inout Resource) -> T
    ) async throws(Pool.Lifecycle.Error) -> sending T {
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

    // MARK: - Sync Body (Throwing)

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
    nonisolated(nonsending)
    public func callAsFunction<T, E: Error>(
        _ body: (inout Resource) throws(E) -> T
    ) async throws(Pool.Lifecycle.Error) -> sending Result<T, E> {
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

    // MARK: - Async Body (Non-throwing)

    /// Acquires a resource and executes an async body with exclusive access.
    ///
    /// The body may suspend; the slot is held across `await`. The resource is
    /// borrowed inout for the duration of the body.
    ///
    /// - Note: Only available on non-embedded platforms.
    ///
    /// - Parameter body: Async closure receiving exclusive mutable access to resource.
    /// - Returns: The result of the body closure.
    /// - Throws: `Pool.Lifecycle.Error` on shutdown or cancellation.
    nonisolated(nonsending)
    public func callAsFunction<T>(
        _ body: nonisolated(nonsending) (inout Resource) async -> sending T
    ) async throws(Pool.Lifecycle.Error) -> sending T {
        let (slotIndex, id) = try await acquireSlot()
        defer { releaseSlot(slotIndex, id: id) }
        var resource = entries[slotIndex].move.out
        let result = await body(&resource)
        entries[slotIndex].move.in(resource)
        return result
    }

    // MARK: - Async Body (Throwing)

    /// Acquires a resource and executes a throwing async body with exclusive access.
    ///
    /// - Note: Only available on non-embedded platforms.
    ///
    /// - Parameter body: Throwing async closure receiving exclusive mutable access.
    /// - Returns: `Result.success(T)` on body success, `Result.failure(E)` on body error.
    /// - Throws: `Pool.Lifecycle.Error` on shutdown or cancellation.
    nonisolated(nonsending)
    public func callAsFunction<T, E: Error>(
        _ body: nonisolated(nonsending) (inout Resource) async throws(E) -> T
    ) async throws(Pool.Lifecycle.Error) -> sending Result<T, E> {
        let (slotIndex, id) = try await acquireSlot()
        defer { releaseSlot(slotIndex, id: id) }
        var resource = entries[slotIndex].move.out
        let result: Result<T, E>
        do {
            result = .success(try await body(&resource))
        } catch let error {
            result = .failure(error)
        }
        entries[slotIndex].move.in(resource)
        return result
    }
}
#endif

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

    /// Acquires a slot with timeout, waiting if necessary.
    ///
    /// ## Flow (Action Pattern)
    /// 1. Compute action under lock (pure value)
    /// 2. Execute action outside lock
    /// 3. For lazy create: two-phase commit via `createLazyResource`
    /// 4. For suspend: use timeout-aware suspension
    ///
    /// - Parameter timeout: Maximum time to wait.
    /// - Returns: Tuple of (slot index, Pool.ID for return validation).
    /// - Throws: `Pool.Lifecycle.Error` on shutdown, cancellation, or timeout.
    @usableFromInline
    func acquireSlotWithTimeout(_ timeout: Duration) async throws(Pool.Lifecycle.Error) -> (Slot.Index, Pool.ID) {
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
            // Lazy creation has no timeout - use shared implementation
            return try await createLazyResource(slotIndex: slotIndex, id: id)

        case .suspend:
            return try await suspendForSlotWithTimeout(timeout)
        }
    }

    /// Suspends waiting for a slot to become available, with timeout.
    ///
    /// Uses a racing task to enforce the timeout:
    /// 1. Main task suspends via continuation waiting for a resource
    /// 2. Timeout task sleeps, then wakes the waiter with timeout error
    /// 3. Whichever completes first wins; the other is cancelled/ignored
    @usableFromInline
    func suspendForSlotWithTimeout(_ timeout: Duration) async throws(Pool.Lifecycle.Error) -> (Slot.Index, Pool.ID) {
        let flag = Flag()

        // Start timeout task that sets flag and triggers pump to reap
        let timeoutTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: timeout)
            } catch {
                // Cancelled because acquire completed or task cancelled
                return
            }

            // Timeout fired - set flag and pump to resume flagged waiters
            // Only pump if we were the first to set the flag
            if flag.timeout() {
                self.pumpWaiters()
            }
        }

        // Ensure timeout task is cancelled on all exit paths
        defer { timeoutTask.cancel() }

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
            // Cancel timeout task since we're being cancelled externally
            timeoutTask.cancel()
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
