// Creation requires async closure - only available on non-embedded platforms.
#if !hasFeature(Embedded)
public import Ownership_Primitives

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Closures for lazy resource creation policy.
    ///
    /// Contains both the factory closure for creating resources on-demand
    /// and the destructor closure for disposing them.
    @usableFromInline
    struct Creation: Sendable {
        // DESIGN: Untyped `throws` is intentional. The user's factory closure throws
        // domain-specific errors (e.g., database, network). The pool catches any error
        // and erases it to `Pool.Lifecycle.Error.creationFailed`. Making this
        // `throws(Pool.Error)` would force callers to wrap their errors unnecessarily.
        @usableFromInline
        let create: @Sendable () async throws -> Resource

        @usableFromInline
        let destroy: @Sendable (consuming Resource) -> Void

        @usableFromInline
        init(
            create: @Sendable @escaping () async throws -> Resource,
            destroy: @Sendable @escaping (consuming Resource) -> Void
        ) {
            self.create = create
            self.destroy = destroy
        }
    }

    /// Reference-based creator for lazy policy.
    ///
    /// Uses `Ownership.Shared` for standardized immutable heap storage with
    /// explicit Sendable semantics.
    ///
    /// - Note: Only available on non-embedded platforms because the create
    ///   closure is async.
    @usableFromInline
    typealias Creator = Ownership.Shared<Creation>
}
#endif
