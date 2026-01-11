extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Reference-based creator for lazy policy.
    ///
    /// Class avoids ~Copyable closure storage issues under Swift 6.2.
    @usableFromInline
    final class Creator: @unchecked Sendable {
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
}
