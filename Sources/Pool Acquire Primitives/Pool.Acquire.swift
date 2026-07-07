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

public import Effect_Primitives
public import Ownership_Primitives

extension Pool {
    /// Effect performed when acquiring a resource from a pool.
    ///
    /// This effect represents a request to acquire a resource. Handlers
    /// can intercept acquisition for testing, logging, or custom policies.
    ///
    /// ## Value Type
    ///
    /// The effect returns `Ownership.Immutable<Resource>` rather than `Resource` directly.
    /// This is required because `Effect.Protocol` cannot currently express
    /// `associatedtype Value: ~Copyable` (awaiting Swift Evolution: Suppressed
    /// Associated Types With Defaults).
    ///
    /// `Ownership.Immutable` wraps the `~Copyable` resource in a `Sendable` reference
    /// type, preserving ownership semantics while satisfying protocol requirements.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// struct AcquisitionTracker: Effect.Handler.Protocol {
    ///     typealias Handled = Pool.Acquire<Connection>
    ///
    ///     var acquisitions: [Pool.Scope] = []
    ///
    ///     func handle(
    ///         _ effect: Handled,
    ///         continuation: consuming Effect.Continuation.One<Ownership.Immutable<Connection>, Pool.Error>
    ///     ) async {
    ///         acquisitions.append(effect.scope)
    ///         let resource = Connection()
    ///         await continuation.resume(returning: Ownership.Immutable(resource))
    ///     }
    /// }
    /// ```
    ///
    /// ## Migration Path
    ///
    /// When Swift gains `associatedtype Value: ~Copyable` support, this type
    /// will change to return `Resource` directly instead of `Ownership.Immutable<Resource>`.
    public struct Acquire<Resource: ~Copyable>: Effect.`Protocol` {
        /// The arguments type for this effect — the pool scope to acquire from.
        public typealias Arguments = Pool.Scope

        // TODO: Change to `Resource` when Swift supports `associatedtype Value: ~Copyable`
        // See: https://forums.swift.org/t/pitch-suppressed-associated-types-with-defaults/83663
        /// The result type for this effect — a shared handle to the acquired resource.
        public typealias Value = Ownership.Immutable<Resource>

        /// The failure type for this effect — surfaces `Pool.Error` (for example, shutdown).
        public typealias Failure = Pool.Error

        /// The pool scope to acquire from.
        public let scope: Pool.Scope

        /// The arguments for this effect (the pool scope).
        public var arguments: Pool.Scope { scope }

        /// Creates an acquire effect for the given pool.
        ///
        /// - Parameter scope: The scope of the pool to acquire from.
        @inlinable
        public init(scope: Pool.Scope) {
            self.scope = scope
        }
    }
}
