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

extension Pool.Bounded.Waiter where Resource: ~Copyable & Sendable {
    /// Metadata carried with each waiter entry.
    ///
    /// Empty for now - can add fields without breaking changes.
    /// Potential future uses: creation instant, priority, trace IDs.
    @usableFromInline
    struct Metadata: Sendable {}
}
