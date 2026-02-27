extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Resource creation policy.
    @usableFromInline
    enum Policy: Sendable {
        /// Resources created only via `fill()`. Acquire waits for available.
        case eager(Destructor)

        #if !hasFeature(Embedded)
        /// Resources created on-demand up to capacity.
        ///
        /// - Note: Only available on non-embedded platforms because
        ///   lazy creation requires async.
        case lazy(Creator)
        #endif
    }
}
