// Creator requires async closure - only available on non-embedded platforms.
#if !hasFeature(Embedded)
extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Reference-based creator for lazy policy.
    ///
    /// Class avoids ~Copyable closure storage issues under Swift 6.2.
    ///
    /// - Note: Only available on non-embedded platforms because the create
    ///   closure is async.
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
#endif
