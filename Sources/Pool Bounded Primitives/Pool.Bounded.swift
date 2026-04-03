#if !hasFeature(Embedded)
public import Synchronization
#endif
public import Async_Primitives_Core
internal import Array_Primitives_Core
internal import Ownership_Primitives
@_spi(Internal) internal import Pool_Primitives_Core

extension Pool {
    // MARK: - Sendability Contract
    //
    // Pool.Bounded is @unchecked Sendable. Safety is guaranteed by:
    //
    // 1. All mutable bookkeeping (_state) is protected by Mutex
    // 2. entries is immutable fixed-capacity storage (let)
    // 3. Slot ownership (state .out(id)) implies exclusive Entry access
    // 4. User closures never execute under lock
    // 5. Waiters are resumed only after removal from queue and outside lock
    // 6. Cancellation handlers are lock-free (schedule via Task)
    // 7. Entry access (move.in/move.out) is an external effect - outside lock
    // 8. Gate.open() and resume() only called via perform(_:) - outside lock

    /// Fixed-capacity resource pool with FIFO fairness.
    ///
    /// Supports two policies:
    /// - **Eager**: Resources created only via `fill()`. Acquire waits for available.
    /// - **Lazy**: Resources created on-demand up to capacity.
    public final class Bounded<Resource: ~Copyable & Sendable>: @unchecked Sendable {
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
        let entries: Array<Entry>.Fixed.Indexed<Slot>

        #if DEBUG
        /// Test hook called immediately after a waiter is enqueued.
        /// Use for deterministic test synchronization instead of polling.
        public var onWaiterEnqueued: (@Sendable () -> Void)?
        #endif

        /// Creates a fixed-capacity pool with eager policy.
        ///
        /// Resources must be created via `fill()` before `acquire` can succeed.
        ///
        /// - Parameters:
        ///   - capacity: Maximum number of resources.
        ///   - destroy: Destructor closure to dispose resources.
        ///   - check: Optional validation closure.
        public init(
            capacity: Pool.Capacity,
            destroy: @Sendable @escaping (consuming Resource) -> Void,
            check: (@Sendable (inout Resource) -> Bool)? = nil
        ) {
            self._state = Async.Mutex(State(capacity: capacity.value))
            self.shutdownGate = Async.Gate()
            self.scope = Pool.Scope()
            self.policy = .eager(Destructor(destroy))
            self._check = check
            self.entries = Array<Entry>.Fixed.Indexed(
                try! Array<Entry>.Fixed(
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
        ///   - create: Factory closure to create new resources.
        ///   - destroy: Destructor closure to dispose resources.
        ///   - check: Optional validation closure.
        public init(
            capacity: Pool.Capacity,
            create: @Sendable @escaping () async throws -> Resource,
            destroy: @Sendable @escaping (consuming Resource) -> Void,
            check: (@Sendable (inout Resource) -> Bool)? = nil
        ) {
            self._state = Async.Mutex(State(capacity: capacity.value))
            self.shutdownGate = Async.Gate()
            self.scope = Pool.Scope()
            self.policy = .lazy(Creator(Creation(create: create, destroy: destroy)))
            self._check = check
            self.entries = Array<Entry>.Fixed.Indexed(
                try! Array<Entry>.Fixed(
                    count: Index<Entry>.Count(capacity.value),
                    initializingWith: { _ in Entry() }
                )
            )
        }
        #endif
    }
}

// MARK: - Metrics Snapshot

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Returns a point-in-time snapshot of pool metrics.
    ///
    /// This is the only safe way to read metrics externally.
    /// Reading `_state.metrics` directly without synchronization is undefined behavior.
    public var metrics: Pool.Metrics {
        _state.withLock { $0.metrics }
    }
}

// MARK: - Effect Execution

extension Pool.Bounded where Resource: ~Copyable & Sendable {
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

extension Pool.Bounded where Resource: ~Copyable & Sendable {
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
