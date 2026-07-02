public import Array_Primitive
public import Array_Primitives
public import Async_Primitives
internal import Async_Promise_Primitives
public import Async_Waiter_Primitives
public import Buffer_Linear_Bounded_Primitive
public import Buffer_Linear_Primitive
internal import Buffer_Primitive
public import Column_Primitives
internal import Dimension_Primitives
public import Fixed_Primitives
internal import Memory_Allocator_Primitive
internal import Memory_Heap_Primitives
@_spi(Internal) internal import Pool_ID_Primitives
@_spi(Internal) internal import Pool_Metrics_Primitives
@_spi(Internal) internal import Pool_Scope_Primitives
public import Queue_Primitive
internal import Queue_Primitives
internal import Shared_Primitive
public import Stack_Primitives
public import Storage_Contiguous_Primitives

extension Pool.Bounded where Resource: ~Copyable {
    /// Internal synchronized state for the pool.
    ///
    /// ~Copyable because it contains the waiter queue which is ~Copyable.
    /// Resource is stored ONLY in Entry (class wrapper with manual storage).
    @usableFromInline
    struct State: ~Copyable {
        /// Fixed-capacity LIFO stack for available slot indices.
        ///
        /// Contains indices of slots in `.available(id)` state only.
        ///
        /// Uses `Stack.Bounded` for Copyable COW semantics with no stdlib arrays.
        @usableFromInline
        var available: Stack<Slot.Index>.Bounded

        /// FIFO queue of waiters.
        ///
        /// Uses `Async.Waiter.Queue.Unbounded` as substrate for atomic flagging and
        /// deferred resumption. Pool retains ownership of metrics and precedence.
        ///
        /// **INVARIANT:** Must only be mutated via `addWaiter()`, `popWaiter()`,
        /// and `reapFlaggedWaiters()`. Direct mutation bypasses metrics tracking.
        @usableFromInline
        var waiters: Async.Waiter.Queue.Unbounded<Outcome, Waiter.Metadata>

        /// Slot states by index.
        @usableFromInline
        var slots: Fixed<Column.Bounded<Slot>>

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
            // Pre-allocate fixed-capacity LIFO stack for available indices (starts empty)
            let slotCapacity = Stack<Slot.Index>.Index.Count(
                _unchecked: Cardinal(UInt(capacity))
            )
            self.available = Stack<Slot.Index>.Bounded(capacity: slotCapacity)
            self.waiters = Async.Waiter.Queue.Unbounded()
            let slotCount = try! Slot.Index.Count(capacity)
            self.slots = try! Fixed<Column.Bounded<Slot>>(count: slotCount, initializingWith: { Slot(index: $0) })
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

extension Pool.Bounded.State where Resource: ~Copyable {
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
    mutating func checkShutdownComplete() -> Pool.Bounded<Resource>.Effect {
        if isShutdownComplete {
            _ = lifecycle.shutdown.complete()
            return .gate(.open)
        }
        return .none
    }
}

// MARK: - Centralized Transition Helper

extension Pool.Bounded.State where Resource: ~Copyable {
    /// Transitions a slot to a new state.
    ///
    /// **INVARIANT:** ALL slot state changes MUST go through this helper.
    /// Never modify `slots[i].state` directly.
    ///
    /// This maintains counter invariants and metrics automatically.
    @usableFromInline
    mutating func transition(slot index: Pool.Bounded<Resource>.Slot.Index, to newState: Pool.Bounded<Resource>.Slot.State) {
        let oldState = slots[index].state

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

        // outstanding: increment on available→out or creating→out, decrement on out→available/disposing
        switch (oldState, newState) {
        case (.available, .out), (.creating, .out):
            metrics.outstanding.current += 1
            metrics.outstanding.peak = max(metrics.outstanding.peak, metrics.outstanding.current)

        case (.out, .available), (.out, .disposing):
            metrics.outstanding.current -= 1

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

        slots[index].state = newState
    }

    /// Debug-only transition validation.
    ///
    /// Asserts that the transition is legal per the state machine.
    #if DEBUG
        @usableFromInline
        func assertValidTransition(from oldState: Pool.Bounded<Resource>.Slot.State, to newState: Pool.Bounded<Resource>.Slot.State) {
            let valid: Bool
            switch (oldState, newState) {
            // From empty
            case (.empty, .creating): valid = true  // lazy reservation
            case (.empty, .available): valid = true  // eager fill

            // From creating
            case (.creating(let old), .available(let new)) where old == new: valid = true  // creation succeeded
            case (.creating(let old), .out(let new)) where old == new: valid = true  // lazy checkout
            case (.creating, .empty): valid = true  // creation failed

            // From available
            case (.available(let old), .out(let new)) where old == new: valid = true  // checkout
            case (.available(let old), .disposing(let new)) where old == new: valid = true  // shutdown drain

            // From out
            case (.out(let old), .available(let new)) where old == new: valid = true  // return (open)
            case (.out(let old), .disposing(let new)) where old == new: valid = true  // return during shutdown

            // From disposing
            case (.disposing, .empty): valid = true  // disposal complete

            default: valid = false
            }

            if !valid {
                assertionFailure("Invalid slot transition: \(oldState) → \(newState)")
            }
        }
    #endif
}

// MARK: - ID Generation

extension Pool.Bounded.State where Resource: ~Copyable {
    /// Generates the next Pool.ID.
    @usableFromInline
    mutating func nextID(scope: Pool.Scope) -> Pool.ID {
        let id = Pool.ID(raw: next, scope: scope)
        next += 1
        return id
    }
}

// MARK: - Available Free-List Helpers

extension Pool.Bounded.State where Resource: ~Copyable {
    /// Pushes a slot index to the available free-list (LIFO).
    ///
    /// **INVARIANT:** Each slot index appears in `available` at most once.
    /// Push cannot overflow because pool has N slots, storage has capacity N,
    /// and each slot index is pushed only on state transition to available.
    ///
    /// - Parameter index: The slot index to push.
    @inlinable
    mutating func pushAvailable(_ index: Pool.Bounded<Resource>.Slot.Index) {
        // Invariant guarantees no overflow - capacity equals slot count
        try! available.push(index)
    }

    /// Pops a slot index from the available free-list (LIFO).
    ///
    /// - Returns: The top slot index, or nil if empty.
    @inlinable
    mutating func popAvailable() -> Pool.Bounded<Resource>.Slot.Index? {
        available.pop()
    }
}

// MARK: - Slot Lookup

extension Pool.Bounded.State where Resource: ~Copyable {
    /// Finds an empty slot for lazy creation.
    ///
    /// - Returns: The index of an empty slot, or nil if none available.
    @usableFromInline
    func findEmptySlot() -> Pool.Bounded<Resource>.Slot.Index? {
        slots.first { slot in
            if case .empty = slot.state { return true }
            return false
        }?.index
    }
}

// MARK: - Waiter Management with Metrics

extension Pool.Bounded.State where Resource: ~Copyable {
    /// Adds a waiter to the queue and updates metrics.
    @usableFromInline
    mutating func addWaiter(_ waiter: consuming Pool.Bounded<Resource>.Waiter.Entry) {
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
    mutating func popWaiter() -> Pool.Bounded<Resource>.Waiter.Entry? {
        guard let waiter = waiters.dequeue() else {
            return nil
        }
        metrics.waiters -= 1
        return waiter
    }

    /// Dequeues the first eligible waiter (not cancelled/timed out).
    ///
    /// Skipped waiters (cancelled/timed out) have their resumptions collected
    /// for execution outside the lock.
    ///
    /// - Parameter skipped: Array to collect resumptions for skipped waiters.
    /// - Returns: First eligible waiter, or nil.
    @usableFromInline
    mutating func dequeueEligibleWaiter(
        skipped: inout Array<Column.Heap<Async.Waiter.Resumption>>
    ) -> Pool.Bounded<Resource>.Waiter.Entry? {
        // Collect flagged entries
        var flagged = Async.Waiter.Queue.Drain<Pool.Bounded<Resource>.Waiter.Flagged>()
        let entry = waiters.popEligible(flaggedInto: &flagged)

        // Process flagged entries into resumptions.
        // Pool no longer distinguishes timeout from cancellation — both are
        // surfaced as `.cancelled` per the composition-not-deadline design.
        let currentLifecycle = lifecycle
        var removedCount = entry != nil ? 1 : 0
        flagged.drain { flaggedEntry in
            removedCount += 1

            // Deconstruct in one step - explicit ownership transition
            let split = flaggedEntry.split()

            // Apply Pool's precedence: shutdown > cancel
            let outcome: Pool.Bounded<Resource>.Outcome = Pool.Lifecycle.Precedence.apply(
                lifecycle: currentLifecycle,
                cancelled: true,
                outcome: .failure(.cancelled)
            )

            // Create resumption from consumed entry
            skipped.append(split.entry.resumption(with: outcome))
        }

        // Update metrics for removed entries
        metrics.waiters -= removedCount

        return entry
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
    /// - Returns: Array of pending resumptions to execute outside the lock.
    @usableFromInline
    mutating func reapFlaggedWaiters() -> Array<Column.Heap<Async.Waiter.Resumption>> {
        var pending = Array<Column.Heap<Async.Waiter.Resumption>>(initialCapacity: 0)

        // Copy lifecycle to local to avoid capturing self
        let currentLifecycle = lifecycle

        // Collect flagged entries
        var flagged = Async.Waiter.Queue.Drain<Pool.Bounded<Resource>.Waiter.Flagged>()
        waiters.reapFlagged(into: &flagged)

        // Process flagged entries into resumptions. Pool no longer
        // distinguishes timeout from cancellation — both surface as
        // `.cancelled` per the composition-not-deadline design.
        var reapedCount = 0
        flagged.drain { flaggedEntry in
            reapedCount += 1

            // Deconstruct in one step - explicit ownership transition
            let split = flaggedEntry.split()

            // Apply Pool's precedence: shutdown > cancel
            let outcome: Pool.Bounded<Resource>.Outcome = Pool.Lifecycle.Precedence.apply(
                lifecycle: currentLifecycle,
                cancelled: true,
                outcome: .failure(.cancelled)
            )

            // Create resumption from consumed entry
            pending.append(split.entry.resumption(with: outcome))
        }

        // Update metrics
        metrics.waiters -= reapedCount

        return pending
    }
}
