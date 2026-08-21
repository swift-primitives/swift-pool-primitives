#if POOL_CONCURRENCY

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        struct Creation: Sendable {
            @usableFromInline
            let create: @Sendable () async throws(Pool.Lifecycle.Error) -> sending Resource

            @usableFromInline
            let destroy: @Sendable (consuming Resource) async -> Void

            @usableFromInline
            init(
                create:
                    @escaping @Sendable () async throws(Pool.Lifecycle.Error) -> sending Resource,
                destroy: @escaping @Sendable (consuming Resource) async -> Void
            ) {
                self.create = create
                self.destroy = destroy
            }
        }
    }
#endif
