extension Pool.Bounded where Resource: ~Copyable {
    /// Resource creation policy.
    ///
    /// Stores closures directly — no `Ownership.Shared` wrap. The eager
    /// case stores the destructor; the lazy case stores both factory and
    /// destructor (via `Creation`).
    @usableFromInline
    enum Policy: Sendable {
        /// Resources created only via `fill()`. Acquire waits for available.
        case eager(Destructor)

        #if !hasFeature(Embedded)
            /// Resources created on-demand up to capacity.
            ///
            /// - Note: Only available on non-embedded platforms because
            ///   lazy creation requires async.
            case lazy(Creation)
        #endif
    }
}
