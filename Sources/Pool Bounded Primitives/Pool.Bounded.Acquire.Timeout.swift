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

// Timeout acquire requires async suspension - only available on non-embedded platforms.
#if !hasFeature(Embedded)

import Synchronization
public import Dimension_Primitives
internal import Async_Primitives
internal import Ownership_Primitives
internal import Array_Primitives

// MARK: - Acquire Accessor

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Accessor for acquire operations with timeout support.
    ///
    /// ```swift
    /// // Without timeout (same as calling pool directly)
    /// let result = try await pool.acquire { resource in ... }
    ///
    /// // With timeout
    /// let result = try await pool.acquire.timeout(.seconds(5)) { resource in ... }
    ///
    /// // With timeout, nil on timeout instead of throwing
    /// let result = try await pool.acquire.timeout(.seconds(5)).optional { resource in ... }
    /// ```
    public var acquire: Acquire {
        Acquire(pool: self)
    }
}

// MARK: - Acquire Type

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Namespace for acquire operations with optional timeout.
    public struct Acquire: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        init(pool: Pool.Bounded<Resource>) {
            self.pool = pool
        }
    }
}

// MARK: - Acquire Operations

extension Pool.Bounded.Acquire where Resource: ~Copyable & Sendable {
    /// Acquires a resource with a timeout.
    ///
    /// - Parameter duration: Maximum time to wait for a resource.
    /// - Returns: A timeout acquire accessor.
    @inlinable
    public func timeout(_ duration: Duration) -> Timeout {
        Timeout(pool: pool, timeout: duration)
    }

    /// Acquires a resource and executes a body (no timeout).
    ///
    /// Equivalent to calling `pool { ... }` directly.
    @inlinable
    public func callAsFunction<T: Sendable>(
        _ body: (inout Resource) -> T
    ) async throws(Pool.Lifecycle.Error) -> T {
        try await pool(body)
    }

    /// Acquires a resource and executes a throwing body (no timeout).
    ///
    /// Equivalent to calling `pool { ... }` directly.
    @inlinable
    public func callAsFunction<T: Sendable, E: Error>(
        _ body: (inout Resource) throws(E) -> T
    ) async throws(Pool.Lifecycle.Error) -> Result<T, E> {
        try await pool(body)
    }
}

// MARK: - Timeout

extension Pool.Bounded.Acquire where Resource: ~Copyable & Sendable {
    /// Acquire operation with timeout.
    public struct Timeout: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        let timeout: Duration

        @usableFromInline
        init(pool: Pool.Bounded<Resource>, timeout: Duration) {
            self.pool = pool
            self.timeout = timeout
        }
    }
}

// MARK: - Timeout Operations

extension Pool.Bounded.Acquire.Timeout where Resource: ~Copyable & Sendable {
    /// Acquires a resource with timeout and executes a body.
    ///
    /// - Parameter body: Closure receiving exclusive mutable access to resource.
    /// - Returns: The result of the body closure.
    /// - Throws: `Pool.Lifecycle.Error.timeout` if timeout expires,
    ///           or other lifecycle errors (shutdown, cancelled).
    public func callAsFunction<T: Sendable>(
        _ body: (inout Resource) -> T
    ) async throws(Pool.Lifecycle.Error) -> T {
        // Phase 1: Acquire slot with timeout (may suspend)
        let (slotIndex, id) = try await pool.acquireSlotWithTimeout(timeout)

        // Phase 2: Use resource OUTSIDE lock
        defer { pool.releaseSlot(slotIndex, id: id) }

        var resource = pool.entries[slotIndex].move.out
        let result = body(&resource)
        pool.entries[slotIndex].move.in(resource)

        return result
    }

    /// Acquires a resource with timeout and executes a throwing body.
    ///
    /// - Parameter body: Throwing closure receiving exclusive mutable access.
    /// - Returns: `Result.success(T)` on body success, `Result.failure(E)` on body error.
    /// - Throws: `Pool.Lifecycle.Error.timeout` if timeout expires,
    ///           or other lifecycle errors (shutdown, cancelled).
    public func callAsFunction<T: Sendable, E: Error>(
        _ body: (inout Resource) throws(E) -> T
    ) async throws(Pool.Lifecycle.Error) -> Result<T, E> {
        let (slotIndex, id) = try await pool.acquireSlotWithTimeout(timeout)

        defer { pool.releaseSlot(slotIndex, id: id) }

        var resource = pool.entries[slotIndex].move.out

        let result: Result<T, E>
        do {
            let value = try body(&resource)
            result = .success(value)
        } catch let error {
            result = .failure(error)
        }

        pool.entries[slotIndex].move.in(resource)

        return result
    }

    /// Acquires a resource with timeout, returning nil on timeout.
    ///
    /// Only timeout results in nil. Other errors (shutdown, cancelled) still throw.
    ///
    /// - Parameter body: Closure receiving exclusive mutable access to resource.
    /// - Returns: The result of the body, or nil if timeout expired.
    /// - Throws: `Pool.Lifecycle.Error.shutdown` or `.cancelled` (not `.timeout`).
    public func optional<T: Sendable>(
        _ body: (inout Resource) -> T
    ) async throws(Pool.Lifecycle.Error) -> T? {
        do {
            return try await self(body)
        } catch .timeout {
            return nil
        }
    }

    /// Acquires a resource with timeout, returning nil on timeout (throwing body).
    ///
    /// Only timeout results in nil. Other errors (shutdown, cancelled) still throw.
    ///
    /// - Parameter body: Throwing closure receiving exclusive mutable access.
    /// - Returns: Result of body, or nil if timeout expired.
    /// - Throws: `Pool.Lifecycle.Error.shutdown` or `.cancelled` (not `.timeout`).
    public func optional<T: Sendable, E: Error>(
        _ body: (inout Resource) throws(E) -> T
    ) async throws(Pool.Lifecycle.Error) -> Result<T, E>? {
        do {
            return try await self(body)
        } catch .timeout {
            return nil
        }
    }
}

// MARK: - Slot Acquisition with Timeout

extension Pool.Bounded where Resource: ~Copyable & Sendable {
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
                self.onWaiterEnqueued?()
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

#endif  // !hasFeature(Embedded)
