#if POOL_CONCURRENCY
    extension Pool.Bounded.Release where Resource: ~Copyable {

        @usableFromInline
        enum Disposition {
            case reusable
            case invalid
        }
    }
#endif
