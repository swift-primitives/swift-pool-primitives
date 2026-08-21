#if POOL_CONCURRENCY
    internal import Array_Primitive
    internal import Array_Primitives
    public import Async_Mutex_Primitives
    internal import Async_Primitives
    public import Async_Promise_Primitives
    internal import Async_Waiter_Primitives
    internal import Ownership_Primitives
    @_spi(Internal) internal import Pool_Capacity_Primitives
    @_spi(Internal) internal import Pool_Scope_Primitives
    internal import Tagged_Collection_Primitives

    internal import Synchronization
    internal import Column_Primitives
    internal import Fixed_Primitives
    internal import Buffer_Linear_Bounded_Primitive
    internal import Buffer_Linear_Primitive
    internal import Ownership_Shared_Primitive
    internal import Storage_Contiguous_Primitives
    internal import Memory_Heap_Primitives
    internal import Memory_Allocator_Primitive
    internal import Buffer_Primitive

    extension Pool {

        public final class Bounded<Resource: ~Copyable>: Sendable {

            @usableFromInline
            let _state: Async.Mutex<State>

            @usableFromInline
            let shutdownGate: Async.Gate

            @usableFromInline
            let scope: Pool.Scope

            @usableFromInline
            let policy: Policy

            @usableFromInline
            let _check: (@Sendable (inout Resource) -> Bool)?

            let entries: Tagged<Slot, Fixed<Entry>>

            #if DEBUG

                let enqueue = Mutex<(@Sendable () -> Void)?>(nil)
            #endif

            public init(
                capacity: Pool.Capacity,
                check: (@Sendable (inout Resource) -> Bool)? = nil,
                destroy: @escaping @Sendable (consuming Resource) async -> Void
            ) {
                self._state = Async.Mutex(State(capacity: capacity.value))
                self.shutdownGate = Async.Gate()
                self.scope = Pool.Scope()
                self.policy = .eager(destroy)
                self._check = check

                do {
                    self.entries = Tagged<Slot, Fixed<Entry>>(
                        try Fixed<Entry>(
                            count: Index<Entry>.Count(capacity.value),
                            initializingWith: { _ in Entry() }
                        )
                    )
                } catch {
                    preconditionFailure(
                        """
                        Pool.Bounded entry storage could not be sized \
                        for capacity \(capacity.value): \(error)
                        """
                    )
                }
            }

            public init(
                capacity: Pool.Capacity,
                check: (@Sendable (inout Resource) -> Bool)? = nil,
                create:
                    @escaping @Sendable () async throws(Pool.Lifecycle.Error) -> sending Resource,
                destroy: @escaping @Sendable (consuming Resource) async -> Void
            ) {
                self._state = Async.Mutex(State(capacity: capacity.value))
                self.shutdownGate = Async.Gate()
                self.scope = Pool.Scope()
                self.policy = .lazy(Creation(create: create, destroy: destroy))
                self._check = check

                do {
                    self.entries = Tagged<Slot, Fixed<Entry>>(
                        try Fixed<Entry>(
                            count: Index<Entry>.Count(capacity.value),
                            initializingWith: { _ in Entry() }
                        )
                    )
                } catch {
                    preconditionFailure(
                        """
                        Pool.Bounded entry storage could not be sized \
                        for capacity \(capacity.value): \(error)
                        """
                    )
                }
            }

            deinit {
                let isSafeToDeinitialize = _state.withLock { state in
                    state.lifecycle == .closed
                        || (state.lifecycle == .open
                            && state.metrics.available == 0
                            && state.outstanding == 0
                            && state.creating == 0
                            && state.disposing == 0)
                }
                precondition(
                    isSafeToDeinitialize,
                    "Pool.Bounded with live resources must complete shutdown before deinitialization"
                )
            }
        }
    }

    extension Pool.Bounded where Resource: ~Copyable {

        public var metrics: Pool.Metrics {
            _state.withLock { $0.metrics }
        }
    }

    extension Pool.Bounded where Resource: ~Copyable {

        @inline(always)
        func perform(_ effect: consuming Effect) {
            switch effect {
            case .none:
                return

            case .gate(.open):
                _ = shutdownGate.open()

            case .waiter(.resume(let resumption)):
                resumption.resume()

            case .waiter(.batch(var resumptions)):
                resumptions.drain { $0.resume() }
            }
        }
    }

#endif
