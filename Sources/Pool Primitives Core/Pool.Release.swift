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
internal import Ownership_Primitives

extension Pool {
    /// Effect performed when releasing a resource back to a pool.
    ///
    /// This effect represents a request to release a resource. Handlers
    /// can intercept releases for testing, logging, or cleanup.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// struct ReleaseTracker: Effect.Handler.Protocol {
    ///     typealias Handled = Pool.Release<Connection>
    ///
    ///     var releases: [Pool.ID] = []
    ///
    ///     func handle(
    ///         _ effect: Handled,
    ///         continuation: consuming Effect.Continuation.One<Void, Never>
    ///     ) async {
    ///         releases.append(effect.id)
    ///         await continuation.resume()
    ///     }
    /// }
    /// ```
    public struct Release<Resource: ~Copyable & Sendable>: Effect.`Protocol` {
        public typealias Arguments = Pool.ID
        public typealias Value = Void
        public typealias Failure = Never

        /// The resource identifier being released.
        public let id: Pool.ID

        /// The arguments for this effect (the resource ID).
        public var arguments: Pool.ID { id }

        /// Creates a release effect for the given resource.
        ///
        /// - Parameter id: The identifier of the resource to release.
        @inlinable
        public init(id: Pool.ID) {
            self.id = id
        }
    }
}
