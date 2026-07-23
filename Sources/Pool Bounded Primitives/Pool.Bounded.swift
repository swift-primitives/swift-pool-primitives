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
        // MARK: - Sendability Contract
        //
        // Pool.Bounded conforms to plain `Sendable` (NOT `@unchecked`). Each
        // stored property is itself Sendable; the type-system check passes
        // without requiring an unchecked escape hatch. Safety mechanisms:
        //
        // 1. _state: Async.Mutex<State> — Mutex is Sendable; all mutable
        //    bookkeeping is protected
        // 2. entries: Tagged<Slot, Fixed<Entry>> — `let`-bound storage
        //    of Ownership.Slot references (Slot atomically serializes its own
        //    state machine via release/acquire CAS)
        // 3. Slot ownership (state .out(id)) implies exclusive Entry access
        // 4. User closures never execute under lock (strict stance)
        // 5. Waiters resumed only after removal from queue and outside lock
        // 6. Cancellation handlers flag and synchronously reap queued waiters
        // 7. Entry access (move.in/move.out) happens outside the lock
        // 8. Gate.open() and resume() only called via perform(_:) outside lock

        /// Fixed-capacity resource pool with FIFO fairness.
        ///
        /// Supports two policies:
        /// - **Eager**: Resources created only via `fill()`. Acquire waits for available.
        /// - **Lazy**: Resources created on-demand up to capacity.
        ///
        /// ## Sendable Contract
        ///
        /// `Resource` is `~Copyable` only — no `Sendable` constraint. Exclusive
        /// ownership transfers through `sending` parameters and the pool's
        /// synchronized slots; the resource is never shared concurrently.
        public final class Bounded<Resource: ~Copyable>: Sendable {
            /// Protected internal state wrapped in Async.Mutex.
            @usableFromInline
            let _state: Async.Mutex<State>

            /// Shutdown notification gate (async, non-blocking).
            @usableFromInline
            let shutdownGate: Async.Gate

            /// Pool scope for ID validation.
            @usableFromInline
            let scope: Pool.Scope

            /// Resource creation/destruction policy.
            @usableFromInline
            let policy: Policy

            /// Optional resource validation closure.
            ///
            /// Closure is stored across acquire-release cycles. Captures must be
            /// safely sharable, hence `@Sendable`. The Resource borrow is local
            /// to the call site.
            @usableFromInline
            let _check: (@Sendable (inout Resource) -> Bool)?

            /// Immutable fixed-capacity storage for resources.
            ///
            /// Each Entry wraps a single resource slot. The array never changes
            /// after initialization. Slot ownership (state `.out(id)`) implies
            /// exclusive access to the corresponding entry.
            ///
            /// **Strict Stance:** Entry access (move.in/move.out) is an external
            /// effect and must happen OUTSIDE the pool lock.
            let entries: Tagged<Slot, Fixed<Entry>>

            #if DEBUG
                /// Test hook called immediately after a waiter is enqueued.
                ///
                /// Use for deterministic test synchronization instead of polling.
                let enqueue = Mutex<(@Sendable () -> Void)?>(nil)
            #endif

            /// Creates a fixed-capacity pool with eager policy.
            ///
            /// Resources must be added with `await fill(...)` before `acquire` can succeed.
            ///
            /// - Parameters:
            ///   - capacity: Maximum number of resources.
            ///   - check: Optional validation closure.
            ///   - destroy: Asynchronous consuming closure that disposes resources.
            ///     Captures are stored on the pool and must be `Sendable`; the
            ///     resource itself is not required to be `Sendable`. Every disposal
            ///     is awaited before its lifecycle operation completes.
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
                // force_try is safe: capacity.value is a validated Cardinal count,
                // so Fixed<Entry>(count:initializingWith:) cannot fail here.
                // swift-format-ignore: NeverUseForceTry
                self.entries = Tagged<Slot, Fixed<Entry>>(
                    try! Fixed<Entry>(
                        count: Index<Entry>.Count(capacity.value),
                        initializingWith: { _ in Entry() }
                    )
                )
            }

            /// Creates a fixed-capacity pool with lazy policy.
            ///
            /// Resources are created on-demand up to capacity.
            ///
            /// - Parameters:
            ///   - capacity: Maximum number of resources.
            ///   - check: Optional validation closure.
            ///   - create: Factory closure that produces a new resource.
            ///     Throws `Pool.Lifecycle.Error` directly — the user wraps any
            ///     domain errors at the boundary (typically as `.creationFailed`).
            ///     The factory's captures must be `Sendable` because the closure
            ///     is stored on the pool; the Resource it produces is `sending`
            ///     (transferred into the pool, not shared).
            ///   - destroy: Asynchronous consuming closure that disposes resources.
            public init(
                capacity: Pool.Capacity,
                check: (@Sendable (inout Resource) -> Bool)? = nil,
                create: @escaping @Sendable () async throws(Pool.Lifecycle.Error) -> sending Resource,
                destroy: @escaping @Sendable (consuming Resource) async -> Void
            ) {
                self._state = Async.Mutex(State(capacity: capacity.value))
                self.shutdownGate = Async.Gate()
                self.scope = Pool.Scope()
                self.policy = .lazy(Creation(create: create, destroy: destroy))
                self._check = check
                // force_try is safe: capacity.value is a validated Cardinal count,
                // so Fixed<Entry>(count:initializingWith:) cannot fail here.
                // swift-format-ignore: NeverUseForceTry
                self.entries = Tagged<Slot, Fixed<Entry>>(
                    try! Fixed<Entry>(
                        count: Index<Entry>.Count(capacity.value),
                        initializingWith: { _ in Entry() }
                    )
                )
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

    // MARK: - Metrics Snapshot

    extension Pool.Bounded where Resource: ~Copyable {
        /// Returns a point-in-time snapshot of pool metrics.
        ///
        /// This is the only safe way to read metrics externally.
        /// Reading `_state.metrics` directly without synchronization is undefined behavior.
        public var metrics: Pool.Metrics {
            _state.withLock { $0.metrics }
        }
    }

    // MARK: - Effect Execution

    extension Pool.Bounded where Resource: ~Copyable {
        /// Execute effect outside lock.
        ///
        /// Single resumption funnel.
        ///
        /// **CRITICAL:** This is the ONLY location where `shutdownGate.open()`
        /// and `resumption.resume()` may appear. Any other occurrence is a
        /// pattern violation.
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
