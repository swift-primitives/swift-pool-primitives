#if POOL_CONCURRENCY
    public import Async_Primitives
    public import Async_Waiter_Primitives

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        typealias Flag = Async.Waiter.Flag
    }
#endif
