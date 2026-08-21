public import Async_Primitives

extension Pool.Lifecycle {

    public enum Precedence {}
}

extension Pool.Lifecycle.Precedence {

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
            onTimeout: .failure(.cancelled)
        )
    }
}
