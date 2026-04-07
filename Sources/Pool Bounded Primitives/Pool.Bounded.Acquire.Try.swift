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
internal import Dimension_Primitives
internal import Ownership_Primitives
internal import Array_Fixed_Primitives

// MARK: - Try

extension Pool.Bounded.Acquire where Resource: ~Copyable & Sendable {
    /// Non-blocking acquire operations.
    ///
    /// Attempts to acquire a resource immediately without waiting.
    /// Returns immediately with a result or throws `.exhausted`.
    ///
    /// Works on all platforms including embedded Swift.
    public struct Try: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        init(pool: Pool.Bounded<Resource>) {
            self.pool = pool
        }
    }
}

// MARK: - Try Accessor

extension Pool.Bounded.Acquire where Resource: ~Copyable & Sendable {
    /// Access non-blocking acquire operations.
    ///
    /// ```swift
    /// // Try to acquire, throws .exhausted if none available
    /// let result = try pool.acquire.try { resource in
    ///     // use resource
    /// }
    /// ```
    public var `try`: Try {
        Try(pool: pool)
    }
}

// MARK: - Try Operations

extension Pool.Bounded.Acquire.Try where Resource: ~Copyable & Sendable {
    /// Acquires a resource immediately or throws `.exhausted`.
    ///
    /// This is a non-blocking operation that returns immediately.
    /// If no resource is available, throws `Pool.Lifecycle.Error.exhausted`.
    ///
    /// Works on all platforms including embedded Swift.
    ///
    /// - Parameter body: Closure receiving exclusive mutable access to resource.
    /// - Returns: The result of the body closure.
    /// - Throws: `Pool.Lifecycle.Error.shutdown` if pool is shutting down,
    ///           `Pool.Lifecycle.Error.exhausted` if no resource available.
    public func callAsFunction<T>(
        _ body: (inout Resource) -> T
    ) throws(Pool.Lifecycle.Error) -> T {
        // Phase 1: Try immediate acquisition under lock
        let action: Action = pool._state.withLock { state in
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
                return .acquired(slotIndex, id)
            }

            // No resource available - unlike async acquire, we don't wait
            return .exhausted
        }

        // Phase 2: Handle action OUTSIDE lock
        switch action {
        case .shutdown:
            throw .shutdown

        case .exhausted:
            throw .exhausted

        case .acquired(let slotIndex, let id):
            // Use resource OUTSIDE lock
            defer { pool.releaseSlot(slotIndex, id: id) }

            var resource = pool.entries[slotIndex].move.out
            let result = body(&resource)
            pool.entries[slotIndex].move.in(resource)

            return result
        }
    }

    /// Acquires a resource immediately or throws `.exhausted` (throwing body).
    ///
    /// This is a non-blocking operation that returns immediately.
    /// If no resource is available, throws `Pool.Lifecycle.Error.exhausted`.
    ///
    /// Works on all platforms including embedded Swift.
    ///
    /// - Parameter body: Throwing closure receiving exclusive mutable access.
    /// - Returns: `Result.success(T)` on body success, `Result.failure(E)` on body error.
    /// - Throws: `Pool.Lifecycle.Error.shutdown` if pool is shutting down,
    ///           `Pool.Lifecycle.Error.exhausted` if no resource available.
    public func callAsFunction<T, E: Error>(
        _ body: (inout Resource) throws(E) -> T
    ) throws(Pool.Lifecycle.Error) -> Result<T, E> {
        // Phase 1: Try immediate acquisition under lock
        let action: Action = pool._state.withLock { state in
            guard !state.lifecycle.shutdown.isActive else {
                return .shutdown
            }

            if let slotIndex = state.popAvailable() {
                guard case .available(let id) = state.slots[slotIndex].state else {
                    preconditionFailure("Available ring contains non-available slot")
                }

                state.transition(slot: slotIndex, to: .out(id))
                state.metrics.acquisitions += 1
                return .acquired(slotIndex, id)
            }

            return .exhausted
        }

        // Phase 2: Handle action OUTSIDE lock
        switch action {
        case .shutdown:
            throw .shutdown

        case .exhausted:
            throw .exhausted

        case .acquired(let slotIndex, let id):
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
    }

    /// Acquires a resource immediately, returning nil if none available.
    ///
    /// This is a non-blocking operation that returns immediately.
    /// Returns `nil` if no resource is available (does not throw).
    ///
    /// Works on all platforms including embedded Swift.
    ///
    /// - Parameter body: Closure receiving exclusive mutable access to resource.
    /// - Returns: The result of the body closure, or nil if no resource available.
    /// - Throws: `Pool.Lifecycle.Error.shutdown` if pool is shutting down.
    public func optional<T>(
        _ body: (inout Resource) -> T
    ) throws(Pool.Lifecycle.Error) -> T? {
        do {
            return try self(body)
        } catch .exhausted {
            return nil
        }
    }

    /// Acquires a resource immediately, returning nil if none available (throwing body).
    ///
    /// This is a non-blocking operation that returns immediately.
    /// Returns `nil` if no resource is available (does not throw).
    ///
    /// Works on all platforms including embedded Swift.
    ///
    /// - Parameter body: Throwing closure receiving exclusive mutable access.
    /// - Returns: Result of body, or nil if no resource available.
    /// - Throws: `Pool.Lifecycle.Error.shutdown` if pool is shutting down.
    public func optional<T, E: Error>(
        _ body: (inout Resource) throws(E) -> T
    ) throws(Pool.Lifecycle.Error) -> Result<T, E>? {
        do {
            return try self(body)
        } catch .exhausted {
            return nil
        }
    }
}
