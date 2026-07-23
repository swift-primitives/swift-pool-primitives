#if POOL_CONCURRENCY
    extension Pool.Bounded where Resource: ~Copyable {
        /// Destructor closure type for eager policy.
        ///
        /// Stored directly as a closure value — no `Ownership.Immutable` wrap.
        /// Closures are already reference-typed in Swift; an extra heap
        /// indirection is gratuitous. The `@Sendable` annotation enforces that
        /// captures are safely shareable, which is required by the pool's stored
        /// `Sendable` policy witness. The resource itself remains unconstrained.
        @usableFromInline
        typealias Destructor = @Sendable (consuming Resource) async -> Void
    }

    // MARK: - Destructor Access

    extension Pool.Bounded where Resource: ~Copyable {
        /// Gets the destructor from either policy.
        @usableFromInline
        var destructor: @Sendable (consuming Resource) async -> Void {
            switch policy {
            case .eager(let d): return d

            case .lazy(let c): return c.destroy
            }
        }
    }
#endif
