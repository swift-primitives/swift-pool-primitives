#if POOL_CONCURRENCY

    extension Pool.Bounded.Fill where Resource: ~Copyable {

        @usableFromInline
        enum Action {

            case notEager

            case shutdown

            case full

            case install(Pool.Bounded<Resource>.Slot.Index, Pool.ID)
        }
    }
#endif
