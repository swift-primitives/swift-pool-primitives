#if POOL_CONCURRENCY

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        enum Release {}
    }
#endif
