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

extension Pool.Bounded.Acquire.Try where Resource: ~Copyable & Sendable {
    /// Actions computed under lock for non-blocking acquisition.
    @usableFromInline
    enum Action: Sendable {
        /// Slot immediately available.
        case acquired(Pool.Bounded<Resource>.Slot.Index, Pool.ID)

        /// Pool is shutting down.
        case shutdown

        /// No resource available.
        case exhausted
    }
}
