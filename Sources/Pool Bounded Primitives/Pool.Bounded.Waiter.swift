#if POOL_CONCURRENCY
    public import Async_Primitives
    public import Async_Waiter_Primitives
    internal import Dimension_Primitives

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        typealias Outcome = Result<(Slot.Index, Pool.ID), Pool.Lifecycle.Error>

        @usableFromInline
        enum Waiter {}
    }
    extension Pool.Bounded.Waiter where Resource: ~Copyable {

        @usableFromInline
        typealias Entry = Async.Waiter.Entry<Pool.Bounded<Resource>.Outcome, Metadata>

        @usableFromInline
        typealias Flagged = Async.Waiter.Queue.Flagged<Pool.Bounded<Resource>.Outcome, Metadata>
    }
#endif
