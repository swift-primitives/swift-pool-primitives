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

public import Async_Waiter_Primitives
public import Array_Primitives_Core

extension Pool.Bounded.Fill where Resource: ~Copyable {
    /// Actions for committing a filled slot.
    ///
    /// Embeds skipped resumptions and shutdown effect into each case to avoid
    /// capturing mutable variables across the `withLock` sending boundary.
    @usableFromInline
    enum Commit: ~Copyable {
        /// Add slot to available pool.
        case addToPool(effect: Pool.Bounded<Resource>.Effect, skipped: Array<Async.Waiter.Resumption>)

        /// Hand off directly to waiter.
        case handOff(Async.Waiter.Resumption, skipped: Array<Async.Waiter.Resumption>)
    }
}
