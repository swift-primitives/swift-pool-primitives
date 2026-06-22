public import Async_Primitives

extension Pool.Lifecycle {
    /// Precedence rules for error handling.
    ///
    /// Order (highest to lowest):
    /// 1. shutdown dominates all
    /// 2. cancellation dominates timeout and success
    /// 3. timeout dominates success
    /// 4. success/outcome as-is
    public enum Precedence {}
}

extension Pool.Lifecycle.Precedence {
    /// Applies precedence rules to determine final outcome.
    ///
    /// Uses `Async.Precedence.resolve` as the underlying implementation.
    ///
    /// ## Precedence Order
    /// 1. **Shutdown** dominates ALL
    /// 2. **Cancellation** dominates success
    /// 3. **Outcome** returned as-is
    ///
    /// - Parameters:
    ///   - lifecycle: Current lifecycle state
    ///   - cancelled: Whether the waiter was cancelled
    ///   - outcome: The raw outcome (success or operational error)
    /// - Returns: Final outcome after applying precedence rules
    @inlinable
    public static func apply<Success>(
        lifecycle: Pool.Lifecycle.State,
        cancelled: Bool,
        outcome: Result<Success, Pool.Lifecycle.Error>
    ) -> Result<Success, Pool.Lifecycle.Error> {
        Async.Precedence.resolve(
            shutdown: !lifecycle.isOpen,
            cancelled: cancelled,
            timedOut: false,
            success: outcome,
            onShutdown: .failure(.shutdown),
            onCancelled: .failure(.cancelled),
            onTimeout: .failure(.cancelled)  // unused — kept for upstream API compat
        )
    }
}
