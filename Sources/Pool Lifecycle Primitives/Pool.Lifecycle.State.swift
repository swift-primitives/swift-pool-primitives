public import Async_Primitives

extension Pool.Lifecycle {

    public typealias State = Async.Lifecycle.State
}

extension Pool.Lifecycle.State {

    @inlinable
    public var isAccepting: Bool {
        isOpen
    }
}
