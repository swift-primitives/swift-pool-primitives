internal import Array_Primitives
internal import Array_Primitive
internal import Tagged_Collection_Primitives
public import Async_Mutex_Primitives
public import Async_Primitives_Core
public import Async_Promise_Primitives
internal import Async_Waiter_Primitives
internal import Ownership_Primitives
@_spi(Internal) internal import Pool_Primitives_Core

#if !hasFeature(Embedded)
    internal import Synchronization
    internal import Column_Primitives
    internal import Fixed_Primitives
    internal import Buffer_Linear_Bounded_Primitive
    internal import Buffer_Linear_Primitive
    internal import Shared_Primitive
    internal import Storage_Contiguous_Primitives
    internal import Memory_Heap_Primitives
    internal import Memory_Allocator_Primitive
    internal import Buffer_Primitive
#endif

extension Pool {
    // MARK: - Sendability Contract
    //
    // Pool.Bounded conforms to plain `Sendable` (NOT `@unchecked`). Each
    // stored property is itself Sendable; the type-system check passes
    // without requiring an unchecked escape hatch. Safety mechanisms:
    //
    // 1. _state: Async.Mutex<State> — Mutex is Sendable; all mutable
    //    bookkeeping is protected
    // 2. entries: Tagged<Slot, Fixed<Column.Bounded<Entry>>> — `let`-bound storage
    //    of Ownership.Slot references (Slot atomically serializes its own
    //    state machine via release/acquire CAS)
    // 3. Slot ownership (state .out(id)) implies exclusive Entry access
    // 4. User closures never execute under lock (strict stance)
    // 5. Waiters resumed only after removal from queue and outside lock
    // 6. Cancellation handlers are lock-free (schedule via Task)
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
    /// `Resource` is `~Copyable` only — no `Sendable` constraint. Per the
    /// closure-only anti-pattern fix (`ownership-transfer-conventions.md`
    /// §3): the type parameter does not need `Sendable` because the resource
    /// never crosses an isolation boundary directly — it transits via the
    /// slot, under the pool's Mutex.
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
        let entries: Tagged<Slot, Fixed<Column.Bounded<Entry>>>

        #if DEBUG
            /// Test hook called immediately after a waiter is enqueued.
            ///
            /// Use for deterministic test synchronization instead of polling.
            /// Marked `nonisolated(unsafe)` because it's a `var` that exists
            /// solely so test code can set the hook after construction. The
            /// scope of unsafe-shared mutation is exactly this one property,
            /// not the entire class.
            nonisolated(unsafe) public var onEnqueue: (@Sendable () -> Void)?
        #endif

        /// Creates a fixed-capacity pool with eager policy.
        ///
        /// Resources must be created via `fill()` before `acquire` can succeed.
        ///
        /// - Parameters:
        ///   - capacity: Maximum number of resources.
        ///   - destroy: Destructor closure to dispose resources. Captures
        ///     are stored on the pool and must be `Sendable`; the Resource
        ///     itself is not required to be Sendable.
        ///   - check: Optional validation closure.
        public init(
            capacity: Pool.Capacity,
            destroy: @escaping @Sendable (consuming Resource) -> Void,
            check: (@Sendable (inout Resource) -> Bool)? = nil
        ) {
            self._state = Async.Mutex(State(capacity: capacity.value))
            self.shutdownGate = Async.Gate()
            self.scope = Pool.Scope()
            self.policy = .eager(destroy)
            self._check = check
            self.entries = Tagged<Slot, Fixed<Column.Bounded<Entry>>>(
                try! Fixed<Column.Bounded<Entry>>(
                    count: Index<Entry>.Count(capacity.value),
                    initializingWith: { _ in Entry() }
                )
            )
        }

        #if !hasFeature(Embedded)
            /// Creates a fixed-capacity pool with lazy policy.
            ///
            /// Resources are created on-demand up to capacity.
            ///
            /// - Note: Only available on non-embedded platforms because
            ///   lazy creation requires async.
            ///
            /// - Parameters:
            ///   - capacity: Maximum number of resources.
            ///   - create: Factory closure that produces a new resource.
            ///     Throws `Pool.Lifecycle.Error` directly — the user wraps any
            ///     domain errors at the boundary (typically as `.creationFailed`).
            ///     The factory's captures must be `Sendable` because the closure
            ///     is stored on the pool; the Resource it produces is `sending`
            ///     (transferred into the pool, not shared).
            ///   - destroy: Destructor closure to dispose resources.
            ///   - check: Optional validation closure.
            public init(
                capacity: Pool.Capacity,
                create: @escaping @Sendable () async throws(Pool.Lifecycle.Error) -> sending Resource,
                destroy: @escaping @Sendable (consuming Resource) -> Void,
                check: (@Sendable (inout Resource) -> Bool)? = nil
            ) {
                self._state = Async.Mutex(State(capacity: capacity.value))
                self.shutdownGate = Async.Gate()
                self.scope = Pool.Scope()
                self.policy = .lazy(Creation(create: create, destroy: destroy))
                self._check = check
                self.entries = Tagged<Slot, Fixed<Column.Bounded<Entry>>>(
                    try! Fixed<Column.Bounded<Entry>>(
                        count: Index<Entry>.Count(capacity.value),
                        initializingWith: { _ in Entry() }
                    )
                )
            }
        #endif
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
    /// Execute effect outside lock. Single resumption funnel.
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

// MARK: - Manual Waiter Pumping

extension Pool.Bounded where Resource: ~Copyable {
    /// Pumps waiters manually.
    ///
    /// Required on embedded platforms for callback-based acquire when using
    /// timeout or cancellation flags. On non-embedded platforms, this is
    /// called automatically via Task scheduling.
    ///
    /// Call this periodically from your embedded event loop to process
    /// waiters that have been flagged for timeout or cancellation.
    public func poll() {
        pumpWaiters()
    }
}
