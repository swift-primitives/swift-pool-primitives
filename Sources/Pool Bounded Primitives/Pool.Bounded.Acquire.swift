#if POOL_CONCURRENCY
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

    public import Either_Primitives
    internal import Fixed_Primitives
    internal import Ownership_Primitives
    internal import Tagged_Collection_Primitives

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
        ///     let result = await processResource(&resource)
        ///     return .reusable(result)
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
        ///   `.right(Never)` case is statically unreachable.
        ///
        /// ## Cancellation Semantics
        ///
        /// If the calling Task is cancelled while waiting for a slot or while
        /// executing the body, the function destroys the resource and throws
        /// `.cancelled` after disposal completes.
        ///
        /// - Parameter body: Closure receiving exclusive mutable access to the
        ///   resource. The body must explicitly return
        ///   ``Pool/Bounded/Disposition/reusable(_:)`` or
        ///   ``Pool/Bounded/Disposition/invalid(_:)``. Throws, cancellation,
        ///   concurrent shutdown, and failed validation destroy the resource.
        /// - Returns: The value carried by the body's terminal disposition.
        /// - Throws: `Either<Pool.Lifecycle.Error, E>` where `.left` is a pool
        ///   failure and `.right` is a body failure.
        nonisolated(nonsending)
            public func callAsFunction<T: ~Copyable, E: Swift.Error>(
                _ body: nonisolated(nonsending) (inout sending Resource) async throws(E) -> sending Pool.Bounded<Resource>.Disposition<T>
            ) async throws(Either<Pool.Lifecycle.Error, E>) -> sending T
        {
            while true {
                let slot: (Pool.Bounded<Resource>.Slot.Index, Pool.ID)
                do throws(Pool.Lifecycle.Error) {
                    slot = try await pool.acquireSlot()
                } catch {
                    throw .left(error)
                }
                let (slotIndex, id) = slot
                var resource = pool.entries.underlying[
                    slotIndex.retag(Pool.Bounded<Resource>.Entry.self)
                ].move.out

                if let check = pool._check, !check(&resource) {
                    if let error = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .invalid
                    ) {
                        throw .left(error)
                    }
                    continue
                }

                let admissionError: Pool.Lifecycle.Error? = pool._state.withLock { state in
                    if state.lifecycle.shutdown.isActive { return .shutdown }
                    if Task.isCancelled { return .cancelled }
                    return nil
                }
                if let admissionError {
                    _ = await pool.release(resource, from: slotIndex, id: id, as: .invalid)
                    throw .left(admissionError)
                }

                let disposition: Pool.Bounded<Resource>.Disposition<T>
                do throws(E) {
                    disposition = try await body(&resource)
                } catch {
                    let releaseError = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .invalid
                    )
                    if let releaseError {
                        throw .left(releaseError)
                    }
                    if Task.isCancelled {
                        throw .left(.cancelled)
                    }
                    throw .right(error)
                }

                if Task.isCancelled {
                    let releaseError = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .invalid
                    )
                    throw .left(releaseError ?? .cancelled)
                }

                switch consume disposition {
                case .reusable(let value):
                    if let error = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .reusable
                    ) {
                        throw .left(error)
                    }
                    return value

                case .invalid(let value):
                    if let error = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .invalid
                    ) {
                        throw .left(error)
                    }
                    return value
                }
            }
        }
    }
#endif
