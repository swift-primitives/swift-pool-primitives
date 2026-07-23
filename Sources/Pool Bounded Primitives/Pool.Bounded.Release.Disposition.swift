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

#if POOL_CONCURRENCY
    extension Pool.Bounded.Release where Resource: ~Copyable {
        /// Whether a checked-out resource may return to reusable storage.
        @usableFromInline
        enum Disposition {
            case reusable
            case invalid
        }
    }
#endif
