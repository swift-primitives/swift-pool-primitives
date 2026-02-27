public import Async_Primitives

extension Pool.Lifecycle {
    /// Pool lifecycle state machine.
    ///
    /// Re-exported from `Async.Lifecycle.State`.
    public typealias State = Async.Lifecycle.State
}

extension Pool.Lifecycle.State {
    /// Whether new acquisitions are accepted.
    ///
    /// Alias for `isOpen` with Pool-specific naming.
    @inlinable
    public var isAccepting: Bool {
        isOpen
    }
}
