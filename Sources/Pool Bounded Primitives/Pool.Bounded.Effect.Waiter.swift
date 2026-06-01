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

extension Pool.Bounded.Effect where Resource: ~Copyable {
    /// Waiter effects for continuation resumption.
    ///
    /// ## Construction Constraint
    /// `batch([Resumption])` must ONLY originate from `Async.Waiter.Queue`
    /// operations (e.g., `reapFlagged`, `reapAll`). Never construct batch
    /// arrays ad-hoc in application code.
    @usableFromInline
    enum Waiter: ~Copyable {
        /// Resume a single waiter.
        case resume(Async.Waiter.Resumption)

        /// Resume multiple waiters (from queue operations only).
        case batch(Array<Async.Waiter.Resumption>)
    }
}
