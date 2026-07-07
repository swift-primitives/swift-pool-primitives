extension Pool {
    /// Operational errors from pool operations.
    ///
    /// These are leaf errors that do not involve lifecycle state.
    /// For lifecycle errors, see `Pool.Lifecycle.Error`.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// Invalid capacity value (must be > 0).
        case capacity(Int)

        /// All resources are in use and none available (non-waiting path).
        ///
        /// This error is returned by non-waiting acquisition variants (for example, `.try`)
        /// when no resource is immediately available. The standard waiting path
        /// uses `Pool.Lifecycle.Error.timeout` or waits indefinitely.
        case exhausted

        /// The ID belongs to a different pool scope.
        case scope(Pool.Scope)

        /// The ID is not valid (released or never acquired).
        case id(Pool.ID)
    }
}
