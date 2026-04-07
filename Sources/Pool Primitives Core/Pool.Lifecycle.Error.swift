extension Pool.Lifecycle {
    /// Lifecycle errors that can occur during pool operations.
    ///
    /// Pool.Bounded waits indefinitely for a slot or until the calling Task
    /// is cancelled. Timeout and "try" semantics are not built into the pool —
    /// they are composed externally via Task cancellation.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The pool is shutting down or has shut down.
        case shutdown

        /// The calling Task was cancelled while waiting for or holding a slot.
        ///
        /// Callers wanting timeout or non-blocking semantics compose these
        /// via Task cancellation; the pool surfaces both as `.cancelled`.
        case cancelled

        /// Resource creation failed (lazy policy only).
        case creationFailed
    }
}
