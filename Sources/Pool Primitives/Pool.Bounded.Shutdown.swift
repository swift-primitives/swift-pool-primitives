// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-pools open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-pools project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

#if !hasFeature(Embedded)
import Synchronization
#endif
public import Async_Primitives
public import Dimension_Primitives
internal import Ownership_Primitives

// MARK: - Shutdown Accessor

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Accessor for shutdown operations.
    public var shutdown: Shutdown {
        Shutdown(pool: self)
    }
}

// MARK: - Shutdown Type

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Namespace for pool shutdown operations.
    public struct Shutdown: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        init(pool: Pool.Bounded<Resource>) {
            self.pool = pool
        }
    }
}

// MARK: - Drain Action

extension Pool.Bounded.Shutdown where Resource: ~Copyable & Sendable {
    /// Actions computed under lock for shutdown drain.
    @usableFromInline
    enum DrainAction: Sendable {
        case drain([(Pool.Bounded<Resource>.Slot.Index, Pool.ID)])
        case alreadyShuttingDown
    }
}

// MARK: - Shutdown Operations

extension Pool.Bounded.Shutdown where Resource: ~Copyable & Sendable {
    /// Initiates graceful shutdown.
    ///
    /// After calling this:
    /// - New acquisitions are rejected with `.shutdown`
    /// - New fills are rejected with `.shutdown`
    /// - Outstanding checkouts continue to work
    /// - Resources are destroyed as they are returned
    ///
    /// Use `wait()` to await until all resources are disposed.
    public func callAsFunction() {
        // Phase 1: Begin shutdown and collect what needs to be done
        let (action, waiterResumptions): (DrainAction, [Async.Waiter.Resumption]) = pool._state.withLock { state in
            // Begin shutdown (idempotent)
            guard state.lifecycle.beginShutdown() else {
                return (.alreadyShuttingDown, [])
            }

            // Collect slots to drain
            var slotsToDrain: [(Pool.Bounded<Resource>.Slot.Index, Pool.ID)] = []
            while let slotIndex = state.popAvailable() {
                guard case .available(let id) = state.slots[slotIndex].state else {
                    continue
                }
                // Mark for disposal under lock
                state.transition(slot: slotIndex, to: .disposing(id))
                slotsToDrain.append((slotIndex, id))
            }

            // Drain all waiters with shutdown error
            var pending: [Async.Waiter.Resumption] = []
            state.waiters.drainAll { entry in
                pending.append(entry.resumption(with: .failure(.shutdown)))
            }
            state.metrics.waiters = 0

            return (.drain(slotsToDrain), pending)
        }

        // Phase 2: Execute waiter resumptions OUTSIDE lock
        for resumption in waiterResumptions {
            resumption.resume()
        }

        // Phase 3: Handle drain action
        switch action {
        case .alreadyShuttingDown:
            return

        case .drain(let slotsToDrain):
            // Dispose each resource OUTSIDE lock (strict stance)
            for (slotIndex, _) in slotsToDrain {
                // Move resource out OUTSIDE lock
                let resource = pool.entries[slotIndex].move.out

                // Destroy resource OUTSIDE lock
                pool.destructor(resource)

                // Complete disposal and check shutdown
                let effect: Pool.Bounded<Resource>.Effect = pool._state.withLock { state in
                    state.transition(slot: slotIndex, to: .empty)
                    state.metrics.closed += 1
                    return state.checkShutdownComplete()
                }
                pool.perform(effect)
            }

            // Final shutdown completion check (for case with no available slots)
            if slotsToDrain.isEmpty {
                let effect: Pool.Bounded<Resource>.Effect = pool._state.withLock { state in
                    state.checkShutdownComplete()
                }
                pool.perform(effect)
            }
        }
    }

    /// Whether shutdown has completed (all resources disposed).
    ///
    /// Use for polling on embedded instead of async `wait()`.
    public var isComplete: Bool {
        pool.shutdownGate.isOpen
    }

    /// Waits for shutdown to complete (callback-based).
    ///
    /// Calls the callback when all outstanding checkouts have returned and
    /// all resources have been destroyed.
    ///
    /// This method works on all platforms including embedded Swift.
    ///
    /// - Note: Automatically initiates shutdown if not already started.
    /// - Parameter callback: The callback to invoke when shutdown is complete.
    public func wait(_ callback: @escaping @Sendable () -> Void) {
        // Fast path: already complete
        guard !pool.shutdownGate.isOpen else {
            callback()
            return
        }

        // Ensure shutdown has started
        let needsShutdown: Bool = pool._state.withLock { state in
            !state.lifecycle.isShuttingDown && state.lifecycle != .closed
        }

        if needsShutdown {
            self()  // Initiate shutdown
        }

        // Wait for gate (callback-based)
        pool.shutdownGate.wait(callback)
    }

    #if !hasFeature(Embedded)
    /// Waits for shutdown to complete (async).
    ///
    /// Awaits until all outstanding checkouts have returned and
    /// all resources have been destroyed.
    ///
    /// This is async-native and non-blocking - it waits on the shutdown gate.
    ///
    /// - Parameters:
    ///   - isolation: The actor isolation context for the operation.
    ///
    /// - Note: Only available on non-embedded platforms. On embedded, use
    ///   `wait(_:)` or poll `isComplete` instead.
    /// - Note: Automatically initiates shutdown if not already started.
    public func wait(
        isolation: isolated (any Actor)? = #isolation
    ) async {
        // Fast path: already complete
        guard !pool.shutdownGate.isOpen else { return }

        // Ensure shutdown has started
        let needsShutdown: Bool = pool._state.withLock { state in
            !state.lifecycle.isShuttingDown && state.lifecycle != .closed
        }

        if needsShutdown {
            self()  // Initiate shutdown
        }

        // Wait for gate (non-blocking)
        await pool.shutdownGate.wait(isolation: isolation)
    }
    #endif
}
