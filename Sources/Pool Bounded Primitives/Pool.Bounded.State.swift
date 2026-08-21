#if POOL_CONCURRENCY
    public import Array_Primitive
    public import Array_Primitives
    public import Async_Primitives
    internal import Async_Promise_Primitives
    public import Async_Waiter_Primitives
    internal import Buffer_Linear_Bounded_Primitive
    internal import Buffer_Linear_Primitive
    internal import Buffer_Primitive
    internal import Column_Primitives
    internal import Dimension_Primitives
    public import Fixed_Primitives
    internal import Index_Primitives
    internal import Iterable
    internal import Memory_Allocator_Primitive
    internal import Memory_Heap_Primitives
    internal import Ownership_Shared_Primitive
    @_spi(Internal) internal import Pool_ID_Primitives
    @_spi(Internal) internal import Pool_Metrics_Primitives
    @_spi(Internal) internal import Pool_Scope_Primitives
    public import Queue_Primitive
    internal import Queue_Primitives
    public import Stack_Primitives
    internal import Storage_Contiguous_Primitives

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        struct State: ~Copyable {

            @usableFromInline
            var available: Stack<Slot.Index>.Bounded

            @usableFromInline
            var waiters: Async.Waiter.Queue.Unbounded<Outcome, Waiter.Metadata>

            @usableFromInline
            var slots: Fixed<Slot>

            @usableFromInline
            var next: UInt64

            @usableFromInline
            var lifecycle: Pool.Lifecycle.State

            @usableFromInline
            var metrics: Pool.Metrics

            @usableFromInline
            var outstanding: Int

            @usableFromInline
            var creating: Int

            @usableFromInline
            var disposing: Int

            @usableFromInline
            init(capacity: Int) {

                precondition(
                    capacity >= 0,
                    "Pool.Bounded.State requires a non-negative capacity, got \(capacity)"
                )

                let slotCapacity = Index<Slot.Index>.Count(
                    _unchecked: Cardinal(UInt(capacity))
                )
                self.available = Stack<Slot.Index>.Bounded(capacity: slotCapacity)
                self.waiters = Async.Waiter.Queue.Unbounded()
                let slots: Fixed<Slot>
                do {
                    let slotCount = try Slot.Index.Count(capacity)
                    slots = try Fixed<Slot>(count: slotCount, initializingWith: { Slot(index: $0) })
                } catch {
                    preconditionFailure(
                        "Pool.Bounded slot storage could not be sized for capacity \(capacity): \(error)"
                    )
                }
                self.slots = slots
                self.next = 0
                self.lifecycle = .open
                self.metrics = Pool.Metrics()
                self.outstanding = 0
                self.creating = 0
                self.disposing = 0
            }
        }
    }

    extension Pool.Bounded.State where Resource: ~Copyable {

        @usableFromInline
        var isShutdownComplete: Bool {
            lifecycle == .closing
                && outstanding == 0
                && creating == 0
                && disposing == 0
                && waiters.isEmpty
        }

        @usableFromInline
        mutating func checkShutdownComplete() -> Pool.Bounded<Resource>.Effect {
            if isShutdownComplete {
                _ = lifecycle.shutdown.complete()
                return .gate(.open)
            }
            return .none
        }
    }

    extension Pool.Bounded.State where Resource: ~Copyable {

        @usableFromInline
        mutating func transition(
            slot index: Pool.Bounded<Resource>.Slot.Index,
            to newState: Pool.Bounded<Resource>.Slot.State
        ) {
            let oldState = slots[index].state

            #if DEBUG
                assertValidTransition(from: oldState, to: newState)
            #endif

            switch oldState {
            case .out: outstanding -= 1
            case .creating: creating -= 1
            case .disposing: disposing -= 1
            case .empty, .available: break
            }

            switch newState {
            case .out: outstanding += 1
            case .creating: creating += 1
            case .disposing: disposing += 1
            case .empty, .available: break
            }

            switch (oldState, newState) {
            case (.available, .out), (.creating, .out):
                metrics.outstanding.current += 1
                metrics.outstanding.peak = max(
                    metrics.outstanding.peak,
                    metrics.outstanding.current
                )

            case (.out, .available), (.out, .disposing):
                metrics.outstanding.current -= 1

            default: break
            }

            switch (oldState, newState) {
            case (.empty, .available), (.creating, .available), (.out, .available):
                metrics.available += 1

            case (.available, .out), (.available, .disposing):
                metrics.available -= 1

            default: break
            }

            slots[index].state = newState
        }

        #if DEBUG
            @usableFromInline
            func assertValidTransition(
                from oldState: Pool.Bounded<Resource>.Slot.State,
                to newState: Pool.Bounded<Resource>.Slot.State
            ) {
                let valid: Bool
                switch (oldState, newState) {

                case (.empty, .creating): valid = true
                case (.empty, .available): valid = true

                case (.creating(let old), .available(let new)) where old == new: valid = true
                case (.creating(let old), .out(let new)) where old == new: valid = true
                case (.creating, .empty): valid = true
                case (.creating(let old), .disposing(let new)) where old == new: valid = true

                case (.available(let old), .out(let new)) where old == new: valid = true
                case (.available(let old), .disposing(let new)) where old == new: valid = true

                case (.out(let old), .available(let new)) where old == new: valid = true
                case (.out(let old), .disposing(let new)) where old == new: valid = true

                case (.disposing, .empty): valid = true

                default: valid = false
                }

                if !valid {
                    assertionFailure("Invalid slot transition: \(oldState) → \(newState)")
                }
            }
        #endif
    }

    extension Pool.Bounded.State where Resource: ~Copyable {

        @usableFromInline
        mutating func nextID(scope: Pool.Scope) -> Pool.ID {
            let id = Pool.ID(raw: next, scope: scope)
            next += 1
            return id
        }
    }

    extension Pool.Bounded.State where Resource: ~Copyable {

        @inlinable
        mutating func pushAvailable(_ index: Pool.Bounded<Resource>.Slot.Index) {
            do {

                try available.push(index)
            } catch {
                preconditionFailure(
                    "Pool.Bounded free-list overflow: a slot index was pushed twice (\(error))"
                )
            }
        }

        @inlinable
        mutating func popAvailable() -> Pool.Bounded<Resource>.Slot.Index? {
            available.pop()
        }
    }

    extension Pool.Bounded.State where Resource: ~Copyable {

        @usableFromInline
        func findEmptySlot() -> Pool.Bounded<Resource>.Slot.Index? {
            slots.first { slot in
                if case .empty = slot.state { return true }
                return false
            }?.index
        }
    }

    extension Pool.Bounded.State where Resource: ~Copyable {

        @usableFromInline
        mutating func addWaiter(_ waiter: consuming Pool.Bounded<Resource>.Waiter.Entry) {
            waiters.enqueue(waiter)
            metrics.waiters += 1
        }

        @usableFromInline
        mutating func popWaiter() -> Pool.Bounded<Resource>.Waiter.Entry? {
            guard let waiter = waiters.dequeue() else {
                return nil
            }
            metrics.waiters -= 1
            return waiter
        }

        @usableFromInline
        mutating func dequeueEligibleWaiter(

            skipped: inout [Async.Waiter.Resumption]
        ) -> Pool.Bounded<Resource>.Waiter.Entry? {

            var flagged = Async.Waiter.Queue.Drain<Pool.Bounded<Resource>.Waiter.Flagged>()
            let entry = waiters.popEligible(flaggedInto: &flagged)

            let currentLifecycle = lifecycle
            var removedCount = entry != nil ? 1 : 0
            flagged.drain { flaggedEntry in
                removedCount += 1

                let split = flaggedEntry.split()

                let outcome: Pool.Bounded<Resource>.Outcome = Pool.Lifecycle.Precedence.apply(
                    lifecycle: currentLifecycle,
                    cancelled: true,
                    outcome: .failure(.cancelled)
                )

                skipped.append(split.entry.resumption(with: outcome))
            }

            metrics.waiters -= removedCount

            return entry
        }

        @usableFromInline

        mutating func reapFlaggedWaiters() -> [Async.Waiter.Resumption] {

            var pending = [Async.Waiter.Resumption](initialCapacity: 0)

            let currentLifecycle = lifecycle

            var flagged = Async.Waiter.Queue.Drain<Pool.Bounded<Resource>.Waiter.Flagged>()
            waiters.reapFlagged(into: &flagged)

            var reapedCount = 0
            flagged.drain { flaggedEntry in
                reapedCount += 1

                let split = flaggedEntry.split()

                let outcome: Pool.Bounded<Resource>.Outcome = Pool.Lifecycle.Precedence.apply(
                    lifecycle: currentLifecycle,
                    cancelled: true,
                    outcome: .failure(.cancelled)
                )

                pending.append(split.entry.resumption(with: outcome))
            }

            metrics.waiters -= reapedCount

            return pending
        }

        @usableFromInline

        mutating func fail(
            waitersWith error: Pool.Lifecycle.Error
        ) -> [Async.Waiter.Resumption] {

            var pending = [Async.Waiter.Resumption](initialCapacity: 0)

            while let waiter = dequeueEligibleWaiter(skipped: &pending) {
                pending.append(waiter.resumption(with: .failure(error)))
            }

            return pending
        }
    }
#endif
