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

#if POOL_CONCURRENCY
    internal import Array_Primitive
    internal import Array_Primitives
    internal import Async_Mutex_Primitives
    internal import Async_Primitives
    internal import Async_Waiter_Primitives
    internal import Dimension_Primitives
    public import Index_Primitives
    internal import Ownership_Primitives
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
        /// - Throws: `Fill.Error` if the pool is not eager, shutting down, full,
        ///   or the resource fails validation. Rejected resources are destroyed
        ///   before this operation returns.
        nonisolated(nonsending)
            public func callAsFunction(
                _ resource: consuming sending Resource
            ) async throws(Pool.Bounded<Resource>.Fill.Error)
        {
            // Phase 1: Check preconditions and reserve slot under lock
            let action: Action = pool._state.withLock { state in
                // Verify eager policy
                guard case .eager = pool.policy else {
                    state.disposing += 1
                    return .notEager
                }

                // Check lifecycle
                guard !state.lifecycle.shutdown.isActive else {
                    if state.lifecycle == .closing {
                        state.disposing += 1
                    }
                    return .shutdown
                }

                // Find an empty slot
                guard let slotIndex = state.findEmptySlot() else {
                    state.disposing += 1
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
                await pool.destructor(resource)
                let effect = pool._state.withLock { state in
                    state.disposing -= 1
                    return state.checkShutdownComplete()
                }
                pool.perform(effect)
                throw .notEager

            case .shutdown:
                await pool.destructor(resource)
                let effect = pool._state.withLock { state in
                    if state.lifecycle == .closing {
                        state.disposing -= 1
                    }
                    return state.checkShutdownComplete()
                }
                pool.perform(effect)
                throw .shutdown

            case .full:
                await pool.destructor(resource)
                let effect = pool._state.withLock { state in
                    state.disposing -= 1
                    return state.checkShutdownComplete()
                }
                pool.perform(effect)
                throw .full

            case .install(let slotIndex, let id):
                var resource = resource

                if let check = pool._check, !check(&resource) {
                    pool._state.withLock { state in
                        state.transition(slot: slotIndex, to: .disposing(id))
                    }
                    await pool.destructor(resource)
                    let effect = pool._state.withLock { state in
                        state.transition(slot: slotIndex, to: .empty)
                        state.metrics.closed += 1
                        return state.checkShutdownComplete()
                    }
                    pool.perform(effect)
                    throw .invalid
                }

                // Install resource OUTSIDE lock (strict stance)
                pool.entries.underlying[slotIndex.retag(Pool.Bounded<Resource>.Entry.self)].move.in(resource)

                // Phase 3: Commit under lock
                // All side-outputs embedded in Commit to avoid capturing
                // mutable variables across the withLock sending boundary.
                let commitAction: Commit = pool._state.withLock { state in
                    guard !state.lifecycle.shutdown.isActive else {
                        state.transition(slot: slotIndex, to: .disposing(id))
                        return .dispose
                    }

                    // Mark as available (creating → available)
                    state.transition(slot: slotIndex, to: .available(id))
                    state.metrics.fills += 1

                    // Local array for skipped resumptions (no external capture)
                    // reason: `[T]` sugar always means Swift.Array (requires Copyable);
                    // this module's `Array<E: ~Copyable>` (Array_Primitive front door) is
                    // what `Async.Waiter.Resumption` (~Copyable) actually needs — sugar
                    // breaks the build here ("does not conform to protocol 'Copyable'").
                    // swift-format-ignore: UseShorthandTypeNames
                    // swiftlint:disable:next syntactic_sugar
                    var skipped = Array<Async.Waiter.Resumption>(initialCapacity: 0)

                    // Check if we should hand off to a waiter directly
                    guard let waiter = state.dequeueEligibleWaiter(skipped: &skipped) else {
                        // Make available in pool
                        state.pushAvailable(slotIndex)
                        let effect = state.checkShutdownComplete()
                        return .addToPool(effect: effect, skipped: skipped)
                    }
                    // Hand off directly to waiter (available → out)
                    state.transition(slot: slotIndex, to: .out(id))
                    state.metrics.acquisitions += 1
                    let resumption = waiter.resumption(with: .success((slotIndex, id)))
                    return .handOff(resumption, skipped: skipped)
                }

                // Phase 4: Execute effects OUTSIDE lock
                switch consume commitAction {
                case .addToPool(let effect, var skipped):
                    skipped.drain { $0.resume() }
                    pool.perform(effect)

                case .handOff(let resumption, var skipped):
                    skipped.drain { $0.resume() }
                    pool.perform(.waiter(.resume(resumption)))

                case .dispose:
                    let resource = pool.entries.underlying[slotIndex.retag(Pool.Bounded<Resource>.Entry.self)].move.out
                    await pool.destructor(resource)
                    let effect = pool._state.withLock { state in
                        state.transition(slot: slotIndex, to: .empty)
                        state.metrics.closed += 1
                        return state.checkShutdownComplete()
                    }
                    pool.perform(effect)
                    throw .shutdown
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
        /// - Throws: Any `Fill.Error` other than `.full`; a full pool ends the batch.
        nonisolated(nonsending)
            public func batch(
                _ produce: () -> Resource?
            ) async throws(Pool.Bounded<Resource>.Fill.Error) -> Index<Resource>.Count
        {
            var count: Index<Resource>.Count = .zero

            while let resource = produce() {
                do throws(Pool.Bounded<Resource>.Fill.Error) {
                    try await self(resource)
                    count += .one
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
#endif
