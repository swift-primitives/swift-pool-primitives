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

public import Async_Primitives

extension Pool.Fixed where Resource: ~Copyable & Sendable {
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
    enum Effect: Sendable {
        /// No effect needed.
        case none

        /// Gate operation (shutdown notification).
        case gate(Gate)

        /// Waiter operation (continuation resumption).
        case waiter(Waiter)
    }
}

// MARK: - Gate

extension Pool.Fixed.Effect where Resource: ~Copyable & Sendable {
    /// Gate effects for shutdown notification.
    @usableFromInline
    enum Gate: Sendable {
        /// Open the shutdown gate (signal completion).
        case open
    }
}

// MARK: - Waiter

extension Pool.Fixed.Effect where Resource: ~Copyable & Sendable {
    /// Waiter effects for continuation resumption.
    ///
    /// ## Construction Constraint
    /// `batch([Resumption])` must ONLY originate from `Async.Waiter.Queue`
    /// operations (e.g., `reapFlagged`, `reapAll`). Never construct batch
    /// arrays ad-hoc in application code.
    @usableFromInline
    enum Waiter: Sendable {
        /// Resume a single waiter.
        case resume(Async.Waiter.Resumption)

        /// Resume multiple waiters (from queue operations only).
        case batch([Async.Waiter.Resumption])
    }
}
