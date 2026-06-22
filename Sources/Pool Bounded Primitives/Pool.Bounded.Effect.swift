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

internal import Array_Primitive
internal import Async_Mutex_Primitives
internal import Async_Primitives
internal import Async_Waiter_Primitives

extension Pool.Bounded where Resource: ~Copyable {
    /// External effects computed under lock, executed outside lock.
    ///
    /// ## Design Contract
    /// - `withLock { }` returns only `Effect` (or tuples/arrays of effects)
    /// - `perform(_:)` is the ONLY location that executes effects
    /// - Pattern violation = any `resume()` or `gate.open()` outside `perform(_:)`
    ///
    /// ## Usage
    /// ```swift
    /// let effect: Effect = _state.withLock { state in
    ///     // ... pure state mutations ...
    ///     return state.checkShutdownComplete()
    /// }
    /// perform(effect)  // OUTSIDE lock
    /// ```
    @usableFromInline
    enum Effect: ~Copyable {
        /// No effect needed.
        case none

        /// Gate operation (shutdown notification).
        case gate(Gate)

        /// Waiter operation (continuation resumption).
        case waiter(Waiter)
    }
}
