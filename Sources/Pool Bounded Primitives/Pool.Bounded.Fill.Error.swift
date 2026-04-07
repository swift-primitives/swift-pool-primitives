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
    /// Errors that can occur during fill operations.
    public enum Error: Swift.Error, Sendable, Equatable {
        /// Pool is not using eager policy.
        case notEager

        /// Pool is shutting down or closed.
        case shutdown

        /// Pool is already at capacity (no empty slots).
        case full
    }
}
