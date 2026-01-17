// Creation requires async closure - only available on non-embedded platforms.
#if !hasFeature(Embedded)
public import Reference_Primitives

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Closures for lazy resource creation policy.
    ///
    /// Contains both the factory closure for creating resources on-demand
    /// and the destructor closure for disposing them.
    @usableFromInline
    struct Creation: Sendable {
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
    /// Uses `Reference.Box` for standardized immutable heap storage with
    /// explicit Sendable semantics.
    ///
    /// - Note: Only available on non-embedded platforms because the create
    ///   closure is async.
    @usableFromInline
    typealias Creator = Reference.Box<Creation>
}
#endif
