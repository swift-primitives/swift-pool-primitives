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
    extension Pool.Bounded where Resource: ~Copyable {
        /// The terminal resource disposition and result of a successful acquisition body.
        ///
        /// Every successful body explicitly chooses whether its resource remains
        /// reusable or must be destroyed. Both cases carry the body's result.
        public enum Disposition<Value: ~Copyable>: ~Copyable {
            /// Makes the resource eligible for validation and reuse.
            case reusable(Value)

            /// Destroys the resource before returning the result.
            case invalid(Value)
        }
    }
#endif
