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

// MARK: - Fill Accessor

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Accessor for fill operations (eager policy only).
    public var fill: Fill {
        Fill(pool: self)
    }
}

// MARK: - Fill Type

extension Pool.Bounded where Resource: ~Copyable & Sendable {
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

// MARK: - Fill Error

extension Pool.Bounded.Fill where Resource: ~Copyable & Sendable {
    /// Errors that can occur during fill operations.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// Pool is not using eager policy.
        case notEager

        /// Pool is shutting down or closed.
        case shutdown

        /// Pool is already at capacity (no empty slots).
        case full
    }
}

// MARK: - Fill Action

extension Pool.Bounded.Fill where Resource: ~Copyable & Sendable {
    /// Actions computed under lock for fill operations.
    @usableFromInline
    enum Action: Sendable {
        /// Policy check failed - not eager.
        case notEager

        /// Pool is shutting down.
        case shutdown

        /// Pool is full - no empty slots.
        case full

        /// Found empty slot - proceed to install.
        case install(Pool.Bounded<Resource>.Slot.Index, Pool.ID)
    }
}

// MARK: - Commit Action

extension Pool.Bounded.Fill where Resource: ~Copyable & Sendable {
    /// Actions for committing a filled slot.
    @usableFromInline
    enum CommitAction: Sendable {
        /// Add slot to available pool.
        case addToPool

        /// Hand off directly to waiter.
        case handOff(Async.Waiter.Resumption)
    }
}

// MARK: - Fill Operations

extension Pool.Bounded.Fill where Resource: ~Copyable & Sendable {
    /// Fills the pool with a single resource.
    ///
    /// ## Two-Phase Commit (Strict Stance)
    /// 1. Check policy, lifecycle, find slot under lock (reserve with `.creating`)
    /// 2. Install resource OUTSIDE lock
    /// 3. Commit (mark available, check waiters) under lock
    /// 4. Execute effects OUTSIDE lock
    ///
    /// - Parameter resource: The resource to add to the pool.
    /// - Throws: `Fill.Error` if pool is not eager, shutdown, or full.
    public func callAsFunction(_ resource: consuming Resource) throws(Error) {
        // Phase 1: Check preconditions and reserve slot under lock
        let action: Action = pool._state.withLock { state in
            // Verify eager policy
            guard case .eager = pool.policy else {
                return .notEager
            }

            // Check lifecycle
            guard !state.lifecycle.isShuttingDown else {
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
            pool.entries[slotIndex.rawValue].move.in(resource)

            // Phase 3: Commit under lock
            var skippedResumptions: [Async.Waiter.Resumption] = []

            let (commitAction, effect): (CommitAction, Pool.Bounded<Resource>.Effect) = pool._state.withLock { state in
                // Mark as available (creating → available)
                state.transition(slot: slotIndex, to: .available(id))
                state.metrics.fills += 1

                // Check if we should hand off to a waiter directly
                if let waiter = state.dequeueEligibleWaiter(skipped: &skippedResumptions) {
                    // Hand off directly to waiter (available → out)
                    state.transition(slot: slotIndex, to: .out(id))
                    state.metrics.acquisitions += 1
                    let resumption = waiter.resumption(with: .success((slotIndex, id)))
                    return (.handOff(resumption), .none)
                } else {
                    // Make available in pool
                    state.pushAvailable(slotIndex)
                    return (.addToPool, state.checkShutdownComplete())
                }
            }

            // Phase 4: Execute effects OUTSIDE lock

            // Resume skipped waiters (cancelled/timed out)
            for resumption in skippedResumptions {
                resumption.resume()
            }

            // Execute commit action
            switch commitAction {
            case .addToPool:
                pool.perform(effect)

            case .handOff(let resumption):
                pool.perform(.waiter(.resume(resumption)))
            }
        }
    }
}

// MARK: - Batch Fill

extension Pool.Bounded.Fill where Resource: ~Copyable & Sendable {
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
    ) throws(Error) -> Int {
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
