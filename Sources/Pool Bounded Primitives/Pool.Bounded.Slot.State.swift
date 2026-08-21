#if POOL_CONCURRENCY
    extension Pool.Bounded.Slot where Resource: ~Copyable {

        @usableFromInline
        enum State {

            case empty

            case creating(Pool.ID)

            case available(Pool.ID)

            case out(Pool.ID)

            case disposing(Pool.ID)
        }
    }
#endif
