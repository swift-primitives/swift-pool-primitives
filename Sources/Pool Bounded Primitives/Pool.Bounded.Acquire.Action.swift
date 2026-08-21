#if POOL_CONCURRENCY

    extension Pool.Bounded.Acquire where Resource: ~Copyable {

        @usableFromInline
        enum Action {

            case immediate(Pool.Bounded<Resource>.Slot.Index, Pool.ID)

            #if POOL_CONCURRENCY

                case create(Pool.Bounded<Resource>.Slot.Index, Pool.ID)
            #endif

            case suspend

            case shutdown
        }
    }
#endif
