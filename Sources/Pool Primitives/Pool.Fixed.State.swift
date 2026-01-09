public import Dimension_Primitives
public import Buffer_Primitives
public import Async_Primitives

extension Pool.Fixed where Resource: ~Copyable & Sendable {
    /// Internal synchronized state for the pool.
    ///
    /// This is plain Copyable bookkeeping - NOT ~Copyable.
    /// Resource is stored ONLY in Entry (class wrapper with manual storage).
    @usableFromInline
    struct State {
        /// Fixed-capacity LIFO buffer for available slot indices.
        /// Contains indices of slots in `.available(id)` state only.
        ///
        /// Uses `Buffer.Fixed` for Copyable COW semantics with no stdlib arrays.
        @usableFromInline
        var available: Buffer.Fixed<Slot.Index>

        /// FIFO queue of waiters.
        ///
        /// Uses `Async.Waiter.Queue` as substrate for atomic flagging and
        /// deferred resumption. Pool retains ownership of metrics and precedence.
        ///
        /// **INVARIANT:** Must only be mutated via `addWaiter()`, `popWaiter()`,
        /// and `reapFlaggedWaiters()`. Direct mutation bypasses metrics tracking.
        @usableFromInline
        let waiters: Async.Waiter.Queue<Outcome>

        /// Slot states by index.
        @usableFromInline
        var slots: [Slot]

        /// Next ID counter.
        @usableFromInline
        var next: UInt64

        /// Current lifecycle state.
        @usableFromInline
        var lifecycle: Pool.Lifecycle.State

        /// Runtime metrics.
        @usableFromInline
        var metrics: Pool.Metrics

        // MARK: - Slot State Counters

        /// Number of slots in `.out` state.
        @usableFromInline
        var outstanding: Int

        /// Number of slots in `.creating` state (lazy only).
        @usableFromInline
        var creating: Int

        /// Number of slots in `.disposing` state (shutdown).
        @usableFromInline
        var disposing: Int

        /// Creates state for a pool with the given capacity.
        @usableFromInline
        init(capacity: Int) {
            // Pre-allocate fixed-capacity LIFO buffer for available indices (starts empty)
            self.available = Buffer.Fixed(capacity: capacity)
            self.waiters = Async.Waiter.Queue()
            self.slots = (0..<capacity).map { Slot(index: Slot.Index($0)) }
            self.next = 0
            self.lifecycle = .open
            self.metrics = Pool.Metrics()
            self.outstanding = 0
            self.creating = 0
            self.disposing = 0
        }
    }
}

// MARK: - Shutdown Completion Predicate

extension Pool.Fixed.State where Resource: ~Copyable & Sendable {
    /// Whether shutdown is complete.
    ///
    /// Shutdown is complete when:
    /// - Lifecycle is closing
    /// - No outstanding checkouts
    /// - No in-flight creations
    /// - No in-progress disposals
    @usableFromInline
    var isShutdownComplete: Bool {
        lifecycle == .closing && outstanding == 0 && creating == 0 && disposing == 0
    }

    /// Checks if shutdown is complete and returns the appropriate Effect.
    ///
    /// **CRITICAL:** Every path that decrements `creating`, `disposing`, or
    /// `outstanding` MUST call this method and execute the returned Effect.
    /// Missing a single site causes `shutdown.wait()` to hang forever.
    ///
    /// - Returns: `.gate(.open)` if shutdown is complete, `.none` otherwise.
    @usableFromInline
    mutating func checkShutdownComplete() -> Pool.Fixed<Resource>.Effect {
        if isShutdownComplete {
            _ = lifecycle.completeShutdown()
            return .gate(.open)
        }
        return .none
    }
}

// MARK: - Centralized Transition Helper

extension Pool.Fixed.State where Resource: ~Copyable & Sendable {
    /// Transitions a slot to a new state.
    ///
    /// **INVARIANT:** ALL slot state changes MUST go through this helper.
    /// Never modify `slots[i].state` directly.
    ///
    /// This maintains counter invariants and metrics automatically.
    @usableFromInline
    mutating func transition(slot index: Pool.Fixed<Resource>.Slot.Index, to newState: Pool.Fixed<Resource>.Slot.State) {
        let oldState = slots[index.rawValue].state

        #if DEBUG
        assertValidTransition(from: oldState, to: newState)
        #endif

        // Decrement old state counter
        switch oldState {
        case .out: outstanding -= 1
        case .creating: creating -= 1
        case .disposing: disposing -= 1
        case .empty, .available: break
        }

        // Increment new state counter
        switch newState {
        case .out: outstanding += 1
        case .creating: creating += 1
        case .disposing: disposing += 1
        case .empty, .available: break
        }

        // Update metrics on explicit edges only (future-proof against edge set expansion)
        //
        // Valid edges per state machine:
        //   empty → creating(id)      lazy reservation
        //   empty → available(id)     eager fill
        //   creating → available      creation succeeded
        //   creating → out            lazy checkout (immediate handoff to caller)
        //   creating → empty          creation failed
        //   available → out           checkout
        //   available → disposing     shutdown drain
        //   out → available           return (open)
        //   out → disposing           return during shutdown
        //   disposing → empty         disposal complete

        // checkedOut: increment on available→out or creating→out, decrement on out→available/disposing
        switch (oldState, newState) {
        case (.available, .out), (.creating, .out):
            metrics.checkedOut += 1
            metrics.peakCheckedOut = max(metrics.peakCheckedOut, metrics.checkedOut)
        case (.out, .available), (.out, .disposing):
            metrics.checkedOut -= 1
        default: break
        }

        // available: increment on empty/creating/out→available, decrement on available→out/disposing
        switch (oldState, newState) {
        case (.empty, .available), (.creating, .available), (.out, .available):
            metrics.available += 1
        case (.available, .out), (.available, .disposing):
            metrics.available -= 1
        default: break
        }

        slots[index.rawValue].state = newState
    }

    /// Debug-only transition validation.
    ///
    /// Asserts that the transition is legal per the state machine.
    #if DEBUG
    @usableFromInline
    func assertValidTransition(from oldState: Pool.Fixed<Resource>.Slot.State, to newState: Pool.Fixed<Resource>.Slot.State) {
        let valid: Bool
        switch (oldState, newState) {
        // From empty
        case (.empty, .creating): valid = true      // lazy reservation
        case (.empty, .available): valid = true     // eager fill

        // From creating
        case (.creating(let old), .available(let new)) where old == new: valid = true  // creation succeeded
        case (.creating(let old), .out(let new)) where old == new: valid = true        // lazy checkout
        case (.creating, .empty): valid = true      // creation failed

        // From available
        case (.available(let old), .out(let new)) where old == new: valid = true       // checkout
        case (.available(let old), .disposing(let new)) where old == new: valid = true // shutdown drain

        // From out
        case (.out(let old), .available(let new)) where old == new: valid = true       // return (open)
        case (.out(let old), .disposing(let new)) where old == new: valid = true       // return during shutdown

        // From disposing
        case (.disposing, .empty): valid = true     // disposal complete

        default: valid = false
        }

        if !valid {
            assertionFailure("Invalid slot transition: \(oldState) → \(newState)")
        }
    }
    #endif
}

// MARK: - ID Generation

extension Pool.Fixed.State where Resource: ~Copyable & Sendable {
    /// Generates the next Pool.ID.
    @usableFromInline
    mutating func nextID(scope: Pool.Scope) -> Pool.ID {
        let id = Pool.ID(raw: next, scope: scope)
        next += 1
        return id
    }
}

// MARK: - Available Free-List Helpers

extension Pool.Fixed.State where Resource: ~Copyable & Sendable {
    /// Pushes a slot index to the available free-list (LIFO).
    ///
    /// **INVARIANT:** Each slot index appears in `available` at most once.
    /// Push cannot overflow because pool has N slots, storage has capacity N,
    /// and each slot index is pushed only on state transition to available.
    ///
    /// - Parameter index: The slot index to push.
    @inlinable
    mutating func pushAvailable(_ index: Pool.Fixed<Resource>.Slot.Index) {
        available.push(__unchecked: (), index)
    }

    /// Pops a slot index from the available free-list (LIFO).
    ///
    /// - Returns: The top slot index, or nil if empty.
    @inlinable
    mutating func popAvailable() -> Pool.Fixed<Resource>.Slot.Index? {
        do {
            return try available.pop()
        } catch {
            // .empty is the only error pop() throws
            return nil
        }
    }
}

// MARK: - Waiter Management with Metrics

extension Pool.Fixed.State where Resource: ~Copyable & Sendable {
    /// Adds a waiter to the queue and updates metrics.
    @usableFromInline
    mutating func addWaiter(_ waiter: Pool.Fixed<Resource>.Waiter) {
        waiters.enqueue(waiter)
        metrics.waiters += 1
    }

    /// Removes the first waiter from the queue and updates metrics.
    ///
    /// **CRITICAL INVARIANT (Resume-After-Removal):**
    /// A waiter MUST be removed from the queue BEFORE its continuation is resumed.
    /// This ensures no waiter is ever resumed while still enqueued, which would
    /// violate the single-resumption guarantee. All code paths that resume a waiter
    /// must first call `popWaiter()` or otherwise remove it from the queue.
    ///
    /// - Returns: The removed waiter, or `nil` if queue is empty.
    @usableFromInline
    mutating func popWaiter() -> Pool.Fixed<Resource>.Waiter? {
        guard let waiter = waiters.dequeueFirst() else {
            return nil
        }
        metrics.waiters -= 1
        return waiter
    }

    /// Reaps all flagged waiters from the queue.
    ///
    /// Uses `Async.Waiter.Queue.reapFlagged` to scan+rebuild in one pass,
    /// removing waiters that have `cancelled` or `timedOut` flags set.
    /// Remaining unflagged waiters are preserved in FIFO order.
    ///
    /// This is the reaping mechanism for timeout/cancel. It ensures flagged
    /// waiters are resumed even if no resource ever becomes available.
    ///
    /// **Must be called with the pool lock held. Does not resume.**
    ///
    /// - Parameter pending: Array to collect pending resumptions.
    @usableFromInline
    mutating func reapFlaggedWaiters(into pending: inout [Async.Waiter.Resumption]) {
        // Copy lifecycle to local to avoid capturing self
        let currentLifecycle = lifecycle
        var timeoutCount = 0

        waiters.reapFlagged(into: &pending) { reason, entry in
            // Track waiters resolved as timed out
            if reason == .timedOut {
                timeoutCount += 1
            }

            // Apply Pool's precedence: shutdown > cancel > timeout
            return Pool.Lifecycle.Precedence.apply(
                lifecycle: currentLifecycle,
                cancelled: reason == .cancelled,
                timedOut: reason == .timedOut,
                outcome: reason == .cancelled ? .failure(.cancelled) : .failure(.timeout)
            )
        }

        // Update metrics
        metrics.timeouts += UInt64(timeoutCount)
        metrics.waiters = waiters.count
    }
}
