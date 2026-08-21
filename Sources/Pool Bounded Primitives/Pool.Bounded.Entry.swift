#if POOL_CONCURRENCY
    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        typealias Entry = Ownership.Slot<Resource>
    }
#endif
