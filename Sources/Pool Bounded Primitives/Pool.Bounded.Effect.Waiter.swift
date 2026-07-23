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

    public import Array_Primitive
    public import Async_Waiter_Primitives
    internal import Buffer_Linear_Bounded_Primitive
    internal import Buffer_Linear_Primitive
    internal import Buffer_Primitive
    internal import Column_Primitives
    internal import Fixed_Primitives
    internal import Memory_Allocator_Primitive
    internal import Memory_Heap_Primitives
    internal import Ownership_Shared_Primitive
    internal import Storage_Contiguous_Primitives

    extension Pool.Bounded.Effect where Resource: ~Copyable {
        /// Waiter effects for continuation resumption.
        ///
        /// ## Construction Constraint
        /// `batch([Resumption])` must ONLY originate from `Async.Waiter.Queue`
        /// operations (for example, `reapFlagged`, `reapAll`). Never construct batch
        /// arrays ad-hoc in application code.
        @usableFromInline
        enum Waiter: ~Copyable {
            /// Resume a single waiter.
            case resume(Async.Waiter.Resumption)

            // reason: `[T]` sugar always means Swift.Array (requires Copyable);
            // this module's `Array<E: ~Copyable>` (Array_Primitive front door) is
            // what `Async.Waiter.Resumption` (~Copyable) actually needs — sugar
            // breaks the build here ("does not conform to protocol 'Copyable'").
            // swift-format-ignore: UseShorthandTypeNames
            /// Resume multiple waiters (from queue operations only).
            case batch(Array<Async.Waiter.Resumption>)
        }
    }
#endif
