public import Async_Primitives
public import Dimension_Primitives

extension Pool.Fixed where Resource: ~Copyable & Sendable {
    /// Outcome type for waiter continuation pattern.
    ///
    /// Returns (slot index, Pool.ID) on success, lifecycle error on failure.
    /// Carries both values to avoid unlocked state reads after await.
    @usableFromInline
    typealias Outcome = Result<(Slot.Index, Pool.ID), Pool.Lifecycle.Error>

    /// Waiter entry type for the FIFO queue.
    ///
    /// Uses `Async.Waiter.Queue.Entry` directly as the substrate.
    /// No wrapper - Pool exercises the primitive in production.
    @usableFromInline
    typealias Waiter = Async.Waiter.Queue<Outcome>.Entry
}
