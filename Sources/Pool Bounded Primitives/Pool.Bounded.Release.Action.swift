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

extension Pool.Bounded.Release where Resource: ~Copyable {
    /// Actions computed under lock for slot release.
    ///
    /// Embeds skipped resumptions into each case to avoid capturing
    /// mutable variables across the `withLock` sending boundary.
    @usableFromInline
    enum Action: ~Copyable {
        /// Hand off to waiting waiter.
        case handOff(Async.Waiter.Resumption, skipped: Array<Async.Waiter.Resumption>)

        /// Return to available pool.
        case returnToPool(skipped: Array<Async.Waiter.Resumption>)

        /// Dispose during shutdown.
        case dispose(skipped: Array<Async.Waiter.Resumption>)
    }
}
