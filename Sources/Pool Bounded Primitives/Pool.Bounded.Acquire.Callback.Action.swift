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

extension Pool.Bounded.Acquire.Callback where Resource: ~Copyable {
    /// Actions computed under lock for callback-based acquisition.
    @usableFromInline
    enum Action {
        /// Slot immediately available.
        case immediate(Pool.Bounded<Resource>.Slot.Index, Pool.ID)

        /// Need to wait for a slot.
        case enqueue

        /// Pool is shutting down.
        case shutdown
    }
}
