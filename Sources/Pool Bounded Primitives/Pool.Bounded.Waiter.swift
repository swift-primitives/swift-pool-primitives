#if POOL_CONCURRENCY
    public import Async_Primitives
    public import Async_Waiter_Primitives
    internal import Dimension_Primitives

    extension Pool.Bounded where Resource: ~Copyable {
        /// Outcome type for waiter continuation pattern.
        ///
        /// Returns (slot index, Pool.ID) on success, lifecycle error on failure.
        /// Carries both values to avoid unlocked state reads after await.
        @usableFromInline
        typealias Outcome = Result<(Slot.Index, Pool.ID), Pool.Lifecycle.Error>

        /// Namespace for waiter-related types.
        @usableFromInline
        enum Waiter {}
    }
    extension Pool.Bounded.Waiter where Resource: ~Copyable {
        /// Waiter entry type for the FIFO queue.
        ///
        /// Uses `Async.Waiter.Entry` directly as the substrate.
        /// No wrapper - Pool exercises the primitive in production.
        @usableFromInline
        typealias Entry = Async.Waiter.Entry<Pool.Bounded<Resource>.Outcome, Metadata>

        /// Flagged waiter type for reaping.
        @usableFromInline
        typealias Flagged = Async.Waiter.Queue.Flagged<Pool.Bounded<Resource>.Outcome, Metadata>
    }
#endif
