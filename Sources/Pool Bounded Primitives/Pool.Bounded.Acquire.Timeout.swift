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

internal import Dimension_Primitives
internal import Ownership_Primitives
internal import Array_Fixed_Primitives

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

// MARK: - Operations

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

#endif  // !hasFeature(Embedded)
