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

extension Pool.Bounded.Shutdown where Resource: ~Copyable {
    /// Actions computed under lock for shutdown drain.
    ///
    /// Embeds waiter resumptions into the drain case to avoid capturing
    /// mutable variables across the `withLock` sending boundary.
    @usableFromInline
    enum Drain: ~Copyable, Sendable {
        case drain([(Pool.Bounded<Resource>.Slot.Index, Pool.ID)], resumptions: Array<Async.Waiter.Resumption>)
        case alreadyShuttingDown
    }
}
