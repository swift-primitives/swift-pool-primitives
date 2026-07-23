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

    extension Pool.Bounded.Acquire where Resource: ~Copyable {
        /// Actions computed under lock for slot acquisition.
        @usableFromInline
        enum Action {
            /// Slot immediately available - return to caller.
            case immediate(Pool.Bounded<Resource>.Slot.Index, Pool.ID)

            #if POOL_CONCURRENCY
                /// Need to create resource lazily.
                case create(Pool.Bounded<Resource>.Slot.Index, Pool.ID)
            #endif

            /// Need to suspend and wait for slot.
            case suspend

            /// Pool is shutting down.
            case shutdown
        }
    }
#endif
