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

internal import Dimension_Primitives

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Namespace for acquire operations with optional timeout.
    ///
    /// Provides:
    /// - `pool.acquire { ... }` — async acquire (non-embedded)
    /// - `pool.acquire.timeout(.seconds(5)) { ... }` — async acquire with timeout
    /// - `pool.acquire.try { ... }` — non-blocking acquire
    /// - `pool.acquire.callback(...) { ... }` — callback-based acquire (embedded-friendly)
    public struct Acquire: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        init(pool: Pool.Bounded<Resource>) {
            self.pool = pool
        }
    }
}

// MARK: - Accessor

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Accessor for acquire operations.
    ///
    /// ```swift
    /// // Without timeout (same as calling pool directly)
    /// let result = try await pool.acquire { resource in ... }
    ///
    /// // With timeout
    /// let result = try await pool.acquire.timeout(.seconds(5)) { resource in ... }
    /// ```
    public var acquire: Acquire {
        Acquire(pool: self)
    }
}

// MARK: - Variant Constructors

extension Pool.Bounded.Acquire where Resource: ~Copyable & Sendable {
    /// Acquires a resource with a timeout.
    ///
    /// - Parameter duration: Maximum time to wait for a resource.
    /// - Returns: A timeout acquire accessor.
    @inlinable
    public func timeout(_ duration: Duration) -> Timeout {
        Timeout(pool: pool, timeout: duration)
    }
}

#if !hasFeature(Embedded)
extension Pool.Bounded.Acquire where Resource: ~Copyable & Sendable {
    // MARK: - Sync Body

    /// Acquires a resource and executes a body (no timeout).
    ///
    /// Equivalent to calling `pool { ... }` directly.
    @inlinable
    nonisolated(nonsending)
    public func callAsFunction<T>(
        _ body: (inout Resource) -> T
    ) async throws(Pool.Lifecycle.Error) -> sending T {
        try await pool(body)
    }

    /// Acquires a resource and executes a throwing body (no timeout).
    ///
    /// Equivalent to calling `pool { ... }` directly.
    @inlinable
    nonisolated(nonsending)
    public func callAsFunction<T, E: Error>(
        _ body: (inout Resource) throws(E) -> T
    ) async throws(Pool.Lifecycle.Error) -> sending Result<T, E> {
        try await pool(body)
    }

    // MARK: - Async Body

    /// Acquires a resource and executes an async body (no timeout).
    ///
    /// Equivalent to calling `pool { ... }` directly with an async closure.
    @inlinable
    nonisolated(nonsending)
    public func callAsFunction<T>(
        _ body: nonisolated(nonsending) (inout Resource) async -> sending T
    ) async throws(Pool.Lifecycle.Error) -> sending T {
        try await pool(body)
    }

    /// Acquires a resource and executes a throwing async body (no timeout).
    ///
    /// Equivalent to calling `pool { ... }` directly with an async closure.
    @inlinable
    nonisolated(nonsending)
    public func callAsFunction<T, E: Error>(
        _ body: nonisolated(nonsending) (inout Resource) async throws(E) -> T
    ) async throws(Pool.Lifecycle.Error) -> sending Result<T, E> {
        try await pool(body)
    }
}
#endif
