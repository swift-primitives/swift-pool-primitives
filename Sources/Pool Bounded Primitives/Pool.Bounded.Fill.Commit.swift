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
public import Buffer_Linear_Primitive
internal import Buffer_Primitive
public import Column_Primitives
internal import Fixed_Primitives
internal import Memory_Allocator_Primitive
internal import Memory_Heap_Primitives
internal import Shared_Primitive
public import Storage_Contiguous_Primitives

extension Pool.Bounded.Fill where Resource: ~Copyable {
    /// Actions for committing a filled slot.
    ///
    /// Embeds skipped resumptions and shutdown effect into each case to avoid
    /// capturing mutable variables across the `withLock` sending boundary.
    @usableFromInline
    enum Commit: ~Copyable {
        /// Add slot to available pool.
        case addToPool(effect: Pool.Bounded<Resource>.Effect, skipped: Array<Column.Heap<Async.Waiter.Resumption>>)

        /// Hand off directly to waiter.
        case handOff(Async.Waiter.Resumption, skipped: Array<Column.Heap<Async.Waiter.Resumption>>)
    }
}
