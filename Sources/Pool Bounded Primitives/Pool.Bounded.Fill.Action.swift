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

extension Pool.Bounded.Fill where Resource: ~Copyable {
    /// Actions computed under lock for fill operations.
    @usableFromInline
    enum Action {
        /// Policy check failed - not eager.
        case notEager

        /// Pool is shutting down.
        case shutdown

        /// Pool is full - no empty slots.
        case full

        /// Found empty slot - proceed to install.
        case install(Pool.Bounded<Resource>.Slot.Index, Pool.ID)
    }
}
