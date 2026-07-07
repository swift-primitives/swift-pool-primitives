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

extension Pool.Bounded.Fill where Resource: ~Copyable {
    /// Actions for committing a filled slot.
    ///
    /// Embeds skipped resumptions and shutdown effect into each case to avoid
    /// capturing mutable variables across the `withLock` sending boundary.
    @usableFromInline
    // reason: `[T]` sugar always means Swift.Array (requires Copyable); this
    // module's `Array<E: ~Copyable>` (Array_Primitive front door) is what
    // `Async.Waiter.Resumption` (~Copyable) actually needs — sugar breaks the
    // build here ("does not conform to protocol 'Copyable'"). Applies to
    // every `skipped: Array<Async.Waiter.Resumption>` below.
    enum Commit: ~Copyable {
        // swift-format-ignore: UseShorthandTypeNames
        /// Add slot to available pool.
        case addToPool(effect: Pool.Bounded<Resource>.Effect, skipped: Array<Async.Waiter.Resumption>)

        // swift-format-ignore: UseShorthandTypeNames
        /// Hand off directly to waiter.
        case handOff(Async.Waiter.Resumption, skipped: Array<Async.Waiter.Resumption>)
    }
}
