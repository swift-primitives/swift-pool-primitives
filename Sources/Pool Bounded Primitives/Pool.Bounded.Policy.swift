#if POOL_CONCURRENCY
    extension Pool.Bounded where Resource: ~Copyable {
        /// Resource creation policy.
        ///
        /// Stores closures directly — no `Ownership.Immutable` wrap. The eager
        /// case stores the destructor; the lazy case stores both factory and
        /// destructor (via `Creation`).
        @usableFromInline
        enum Policy: Sendable {
            /// Resources created only via `fill()`.
            ///
            /// Acquire waits for available.
            case eager(Destructor)

            /// Resources created on-demand up to capacity.
            case lazy(Creation)
        }
    }
#endif
