extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Resource creation policy.
    @usableFromInline
    enum Policy: Sendable {
        /// Resources created only via `fill()`. Acquire waits for available.
        case eager(Destructor)

        /// Resources created on-demand up to capacity.
        case lazy(Creator)
    }
}
