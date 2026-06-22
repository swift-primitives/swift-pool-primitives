public import Async_Primitives
public import Async_Waiter_Primitives

extension Pool.Bounded where Resource: ~Copyable {
    /// External flags for cancellation and timeout.
    ///
    /// Re-exported from `Async.Waiter.Flag` with atomic operations.
    ///
    /// ## Cancellation/Timeout Contract
    ///
    /// The cancellation handler MUST:
    /// 1. Call `flag.cancel()` (returns `true` only for first setter)
    /// 2. If `cancel()` returned `true`, call `pumpWaiters()`
    ///
    /// The timeout handler MUST:
    /// 1. Call `flag.timeout()` (returns `true` only for first setter)
    /// 2. If `timeout()` returned `true`, call `pumpWaiters()`
    ///
    /// Both handlers MUST NOT:
    /// - Remove waiter from deque
    /// - Resume the continuation
    ///
    /// Resumption happens only after the waiter is removed from the queue
    /// under lock, via `Async.Waiter.Resumption` executed after unlock.
    ///
    /// ## Precedence
    ///
    /// shutdown > cancellation > timeout > success
    ///
    /// If both cancelled and timedOut are set, cancellation wins.
    @usableFromInline
    typealias Flag = Async.Waiter.Flag
}
