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

internal import Array_Primitives
internal import Array_Fixed_Primitives
internal import Array_Primitives_Core
internal import Async_Mutex_Primitives
internal import Async_Primitives_Core
internal import Async_Waiter_Primitives
internal import Dimension_Primitives
internal import Ownership_Primitives

#if !hasFeature(Embedded)
    internal import Synchronization
#endif

// MARK: - Fill Accessor

extension Pool.Bounded where Resource: ~Copyable {
    /// Accessor for fill operations (eager policy only).
    public var fill: Fill {
        Fill(pool: self)
    }
}

// MARK: - Fill Type

extension Pool.Bounded where Resource: ~Copyable {
    /// Namespace for eager pool fill operations.
    public struct Fill: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        init(pool: Pool.Bounded<Resource>) {
            self.pool = pool
        }
    }
}

// MARK: - Fill Operations

extension Pool.Bounded.Fill where Resource: ~Copyable {
    /// Fills the pool with a single resource.
    ///
    /// ## Two-Phase Commit (Strict Stance)
    /// 1. Check policy, lifecycle, find slot under lock (reserve with `.creating`)
    /// 2. Install resource OUTSIDE lock
    /// 3. Commit (mark available, check waiters) under lock
    /// 4. Execute effects OUTSIDE lock
    ///
    /// - Parameter resource: The resource to add to the pool. Transferred
    ///   into the pool's isolation domain (`consuming sending`).
    /// - Throws: `Fill.Error` if pool is not eager, shutdown, or full.
    public func callAsFunction(_ resource: consuming sending Resource) throws(Pool.Bounded<Resource>.Fill.Error) {
        // Phase 1: Check preconditions and reserve slot under lock
        let action: Action = pool._state.withLock { state in
            // Verify eager policy
            guard case .eager = pool.policy else {
                return .notEager
            }

            // Check lifecycle
            guard !state.lifecycle.shutdown.isActive else {
                return .shutdown
            }

            // Find an empty slot
            guard let slotIndex = state.findEmptySlot() else {
                return .full
            }

            // Generate ID and reserve slot (empty → creating)
            let id = state.nextID(scope: pool.scope)
            state.transition(slot: slotIndex, to: .creating(id))
            return .install(slotIndex, id)
        }

        // Phase 2: Handle action OUTSIDE lock
        switch action {
        case .notEager:
            pool.destructor(resource)
            throw .notEager

        case .shutdown:
            pool.destructor(resource)
            throw .shutdown

        case .full:
            pool.destructor(resource)
            throw .full

        case .install(let slotIndex, let id):
            // Install resource OUTSIDE lock (strict stance)
            pool.entries[slotIndex].move.in(resource)

            // Phase 3: Commit under lock
            // All side-outputs embedded in Commit to avoid capturing
            // mutable variables across the withLock sending boundary.
            let commitAction: Commit = pool._state.withLock { state in
                // Mark as available (creating → available)
                state.transition(slot: slotIndex, to: .available(id))
                state.metrics.fills += 1

                // Local array for skipped resumptions (no external capture)
                var skipped = Array<Async.Waiter.Resumption>()

                // Check if we should hand off to a waiter directly
                if let waiter = state.dequeueEligibleWaiter(skipped: &skipped) {
                    // Hand off directly to waiter (available → out)
                    state.transition(slot: slotIndex, to: .out(id))
                    state.metrics.acquisitions += 1
                    let resumption = waiter.resumption(with: .success((slotIndex, id)))
                    return .handOff(resumption, skipped: skipped)
                } else {
                    // Make available in pool
                    state.pushAvailable(slotIndex)
                    let effect = state.checkShutdownComplete()
                    return .addToPool(effect: effect, skipped: skipped)
                }
            }

            // Phase 4: Execute effects OUTSIDE lock
            switch consume commitAction {
            case .addToPool(let effect, var skipped):
                skipped.drain { $0.resume() }
                pool.perform(effect)

            case .handOff(let resumption, var skipped):
                skipped.drain { $0.resume() }
                pool.perform(.waiter(.resume(resumption)))
            }
        }
    }
}

// MARK: - Batch Fill

extension Pool.Bounded.Fill where Resource: ~Copyable {
    /// Fills the pool with multiple resources.
    ///
    /// Adds resources up to the remaining capacity. Returns the count of
    /// resources successfully added.
    ///
    /// - Parameter produce: Closure that produces resources. Called repeatedly
    ///   until it returns nil or pool is full.
    /// - Returns: The number of resources added.
    /// - Throws: `Fill.Error.notEager` or `Fill.Error.shutdown`.
    public func batch(
        _ produce: () -> Resource?
    ) throws(Pool.Bounded<Resource>.Fill.Error) -> Int {
        var count = 0

        while let resource = produce() {
            do {
                try self(resource)
                count += 1
            } catch .full {
                // Pool is full, stop filling
                // Note: resource was already destroyed inside callAsFunction
                break
            } catch {
                throw error
            }
        }

        return count
    }
}
