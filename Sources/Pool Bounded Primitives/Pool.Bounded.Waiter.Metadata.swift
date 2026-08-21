#if POOL_CONCURRENCY

    extension Pool.Bounded.Waiter where Resource: ~Copyable {

        @usableFromInline
        struct Metadata: Sendable {}
    }
#endif
