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
internal import Array_Primitives

// MARK: - Callback Acquire Type

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Callback-based acquire operations.
    ///
    /// Acquires a resource and calls back when available. If no resource
    /// is immediately available, waits until one becomes available.
    ///
    /// On embedded platforms, call `pool.poll()` periodically to pump
    /// waiters for timeout/cancellation processing.
    ///
    /// Works on all platforms including embedded Swift.
    public struct CallbackAcquire: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        init(pool: Pool.Bounded<Resource>) {
            self.pool = pool
        }
    }
}

// MARK: - Callback Acquire Accessor

extension Pool.Bounded.Acquire where Resource: ~Copyable & Sendable {
    /// Access callback-based acquire operations.
    ///
    /// ```swift
    /// // Callback-based acquire (works on embedded)
    /// pool.acquire.callback { resource in
    ///     // use resource
    ///     return someValue
    /// } completion: { result in
    ///     switch result {
    ///     case .success(let value): // handle value
    ///     case .failure(let error): // handle error
    ///     }
    /// }
    /// ```
    public var callback: Pool.Bounded<Resource>.CallbackAcquire {
        Pool.Bounded<Resource>.CallbackAcquire(pool: pool)
    }
}

// MARK: - Callback Acquire Action

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Actions computed under lock for callback-based acquisition.
    @usableFromInline
    enum CallbackAcquireAction: Sendable {
        /// Slot immediately available.
        case immediate(Slot.Index, Pool.ID)

        /// Need to wait for a slot.
        case enqueue

        /// Pool is shutting down.
        case shutdown
    }
}

// MARK: - Callback Acquire Operations

extension Pool.Bounded.CallbackAcquire where Resource: ~Copyable & Sendable {
    /// Acquires a resource and calls back with the result.
    ///
    /// If a resource is immediately available, the body is executed and
    /// completion is called synchronously. Otherwise, the operation is
    /// enqueued and completion is called when a resource becomes available.
    ///
    /// Works on all platforms including embedded Swift.
    ///
    /// - Parameters:
    ///   - body: Closure receiving exclusive mutable access to resource.
    ///   - completion: Called with the result when acquisition completes.
    public func callAsFunction<T: Sendable>(
        _ body: @escaping @Sendable (inout Resource) -> T,
        completion: @escaping @Sendable (Result<T, Pool.Lifecycle.Error>) -> Void
    ) {
        // Phase 1: Try immediate acquisition under lock
        let action: Pool.Bounded<Resource>.CallbackAcquireAction = pool._state.withLock { state in
            // Check lifecycle
            guard !state.lifecycle.isShuttingDown else {
                return .shutdown
            }

            // Try immediate acquisition (LIFO for cache locality)
            if let slotIndex = state.popAvailable() {
                guard case .available(let id) = state.slots[slotIndex].state else {
                    preconditionFailure("Available ring contains non-available slot")
                }

                // Mark as out under lock
                state.transition(slot: slotIndex, to: .out(id))
                state.metrics.acquisitions += 1
                return .immediate(slotIndex, id)
            }

            // Must wait
            return .enqueue
        }

        // Phase 2: Handle action OUTSIDE lock
        switch action {
        case .shutdown:
            completion(.failure(.shutdown))

        case .immediate(let slotIndex, let id):
            // Execute immediately
            executeAndRelease(slotIndex: slotIndex, id: id, body: body, completion: completion)

        case .enqueue:
            // Enqueue waiter with callback
            enqueueWaiter(body: body, completion: completion)
        }
    }

    /// Acquires a resource and calls back with the result (throwing body).
    ///
    /// If a resource is immediately available, the body is executed and
    /// completion is called synchronously. Otherwise, the operation is
    /// enqueued and completion is called when a resource becomes available.
    ///
    /// Works on all platforms including embedded Swift.
    ///
    /// - Parameters:
    ///   - body: Throwing closure receiving exclusive mutable access.
    ///   - completion: Called with the result when acquisition completes.
    public func callAsFunction<T: Sendable, E: Error>(
        _ body: @escaping @Sendable (inout Resource) throws(E) -> T,
        completion: @escaping @Sendable (Result<Result<T, E>, Pool.Lifecycle.Error>) -> Void
    ) {
        // Wrap the throwing body to return Result<T, E>
        let wrappedBody: @Sendable (inout Resource) -> Result<T, E> = { resource in
            do throws(E) {
                return .success(try body(&resource))
            } catch {
                return .failure(error)
            }
        }

        self(wrappedBody, completion: completion)
    }

    // MARK: - Private Helpers

    @usableFromInline
    func executeAndRelease<T: Sendable>(
        slotIndex: Pool.Bounded<Resource>.Slot.Index,
        id: Pool.ID,
        body: @escaping @Sendable (inout Resource) -> T,
        completion: @escaping @Sendable (Result<T, Pool.Lifecycle.Error>) -> Void
    ) {
        // Execute body OUTSIDE lock
        var resource = pool.entries[slotIndex].move.out
        let result = body(&resource)
        pool.entries[slotIndex].move.in(resource)

        // Release slot
        pool.releaseSlot(slotIndex, id: id)

        // Call completion
        completion(.success(result))
    }

    @usableFromInline
    func enqueueWaiter<T: Sendable>(
        body: @escaping @Sendable (inout Resource) -> T,
        completion: @escaping @Sendable (Result<T, Pool.Lifecycle.Error>) -> Void
    ) {
        let flag = Pool.Bounded<Resource>.Flag()

        // Create callback that will be invoked when resource available
        let callback: @Sendable (Pool.Bounded<Resource>.Outcome) -> Void = { [pool] outcome in
            switch outcome {
            case .success((let slotIndex, let id)):
                // Execute body OUTSIDE lock
                var resource = pool.entries[slotIndex].move.out
                let result = body(&resource)
                pool.entries[slotIndex].move.in(resource)

                // Release slot
                pool.releaseSlot(slotIndex, id: id)

                // Call completion
                completion(.success(result))

            case .failure(let error):
                completion(.failure(error))
            }
        }

        // Enqueue waiter with callback
        pool._state.withLock { state in
            let waiter = Pool.Bounded<Resource>.Waiter.Entry(
                continuation: Async.Continuation(callback),
                flag: flag,
                metadata: Pool.Bounded<Resource>.Waiter.Metadata()
            )
            state.addWaiter(waiter)
        }

        #if DEBUG
        pool.onWaiterEnqueued?()
        #endif
    }
}
