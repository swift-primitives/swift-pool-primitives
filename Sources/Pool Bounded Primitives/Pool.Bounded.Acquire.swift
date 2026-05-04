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

internal import Array_Fixed_Primitives
internal import Ownership_Primitives

extension Pool.Bounded where Resource: ~Copyable {
    /// Accessor for acquire operations.
    ///
    /// `pool.acquire { resource in ... }` waits indefinitely for a slot, or
    /// until the calling Task is cancelled. Non-blocking and timeout
    /// semantics are composed externally via Task cancellation (or via a
    /// `withTimeout` primitive in a higher layer); the pool itself owns
    /// only admission and resource lifecycle.
    ///
    /// ```swift
    /// // Wait indefinitely or until Task.cancel
    /// let result = try await pool.acquire { resource in
    ///     await processResource(&resource)
    /// }
    /// ```
    public var acquire: Acquire {
        Acquire(pool: self)
    }
}

extension Pool.Bounded where Resource: ~Copyable {
    /// Namespace for the pool's acquire operation.
    public struct Acquire: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        init(pool: Pool.Bounded<Resource>) {
            self.pool = pool
        }
    }
}

#if !hasFeature(Embedded)
    extension Pool.Bounded.Acquire where Resource: ~Copyable {
        /// Acquires a resource and executes the body with exclusive access.
        ///
        /// Waits indefinitely for a slot, or until the calling Task is cancelled.
        ///
        /// ## Error Surface
        ///
        /// - Pool failures (`shutdown`, `cancelled`, `creationFailed`) are
        ///   surfaced as `Either.left(Pool.Lifecycle.Error)`.
        /// - Body failures (`E`) are surfaced as `Either.right(E)`.
        /// - For non-throwing bodies, `E` is inferred to `Never` and the
        ///   `.right(Never)` case is statically unreachable. Per [IMPL-075],
        ///   use `do throws(Either<Pool.Lifecycle.Error, Never>) { … } catch { … }`
        ///   without casting; Swift's exhaustiveness checker allows omitting
        ///   the `.right` case.
        ///
        /// ## Sync vs Async Bodies
        ///
        /// Sync closures are accepted via Swift's implicit sync→async closure
        /// promotion. There is no separate sync overload — pass a sync closure
        /// and Swift will promote it.
        ///
        /// ## Cancellation Semantics
        ///
        /// If the calling Task is cancelled while waiting for a slot OR while
        /// executing the body, the function throws `.cancelled`. The slot is
        /// released cleanly in either case. Composition with timeout primitives
        /// works through Task cancellation.
        ///
        /// - Note: Only available on non-embedded platforms. On embedded, use
        ///   `acquire.callback` instead.
        ///
        /// - Parameter body: Async closure receiving exclusive mutable access
        ///   to the resource. May suspend; the slot is held for the body's
        ///   entire duration.
        /// - Returns: The result of the body closure.
        /// - Throws: `Either<Pool.Lifecycle.Error, E>` where `.left` is a pool
        ///   failure and `.right` is a body failure.
        nonisolated(nonsending)
            public func callAsFunction<T: ~Copyable, E: Swift.Error>(
                _ body: nonisolated(nonsending) (inout sending Resource) async throws(E) -> sending T
            ) async throws(Either<Pool.Lifecycle.Error, E>) -> sending T
        {
            // Phase 1: Acquire slot (may suspend; cancellation is observed via
            // the suspension path's withTaskCancellationHandler)
            let slot: (Pool.Bounded<Resource>.Slot.Index, Pool.ID)
            do throws(Pool.Lifecycle.Error) {
                slot = try await pool.acquireSlot()
            } catch {
                throw .left(error)
            }
            let (slotIndex, id) = slot

            // Phase 2: Use resource OUTSIDE lock
            // INVARIANT: Return is total — defer ensures the slot always returns
            defer { pool.releaseSlot(slotIndex, id: id) }

            // Move resource out of the slot into a local
            var resource = pool.entries[slotIndex].move.out

            // Phase 3: Execute body OUTSIDE lock
            let result: T
            do throws(E) {
                result = try await body(&resource)
            } catch {
                // Body failed — still need to put the resource back
                pool.entries[slotIndex].move.in(resource)
                throw .right(error)
            }

            // Move resource back to entry
            pool.entries[slotIndex].move.in(resource)

            return result
        }
    }
#endif
