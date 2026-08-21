#if POOL_CONCURRENCY

    extension Pool.Bounded.Effect where Resource: ~Copyable {

        @usableFromInline
        enum Gate {

            case open
        }
    }
#endif
