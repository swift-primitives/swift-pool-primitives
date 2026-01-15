extension Pool.Lifecycle {
    /// Lifecycle errors that can occur during pool operations.
    ///
    /// These have higher precedence than operational errors.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// The pool is shutting down or has shut down.
        case shutdown

        /// The operation was cancelled.
        case cancelled

        /// The acquisition timed out.
        case timeout

        /// Resource creation failed (lazy policy only).
        case creationFailed

        /// No resource available for non-blocking acquisition.
        ///
        /// Only returned by `acquire.try` operations.
        case exhausted
    }
}
