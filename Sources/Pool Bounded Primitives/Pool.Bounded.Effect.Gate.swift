#if POOL_CONCURRENCY
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

    extension Pool.Bounded.Effect where Resource: ~Copyable {
        /// Gate effects for shutdown notification.
        @usableFromInline
        enum Gate {
            /// Open the shutdown gate (signal completion).
            case open
        }
    }
#endif
