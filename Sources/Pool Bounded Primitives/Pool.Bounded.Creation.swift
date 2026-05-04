// Creation requires async closure - only available on non-embedded platforms.
#if !hasFeature(Embedded)

    extension Pool.Bounded where Resource: ~Copyable {
        /// Closures for lazy resource creation policy.
        ///
        /// Contains both the factory closure for creating resources on-demand
        /// and the destructor closure for disposing them. Stored directly on
        /// the pool — no `Ownership.Shared` wrap. Closures are already
        /// reference-typed in Swift; the extra heap indirection that
        /// `Ownership.Shared` would provide is gratuitous here.
        ///
        /// ## Factory error contract
        ///
        /// The factory closure throws `Pool.Lifecycle.Error` directly — no
        /// existential `any Error`. Per [API-ERR-001], `throws(any Error)` is
        /// forbidden. The user wraps their domain errors at the boundary:
        ///
        /// ```swift
        /// create: {
        ///     do {
        ///         return try await openConnection()
        ///     } catch {
        ///         throw Pool.Lifecycle.Error.creationFailed
        ///     }
        /// }
        /// ```
        ///
        /// The user retains full visibility into their own errors before the
        /// `throw .creationFailed` boundary; they can log, transform, or react
        /// to the original error type. The pool sees only `.creationFailed`
        /// and propagates it through `Pool.Lifecycle.Error`.
        @usableFromInline
        struct Creation: Sendable {
            @usableFromInline
            let create: @Sendable () async throws(Pool.Lifecycle.Error) -> sending Resource

            @usableFromInline
            let destroy: @Sendable (consuming Resource) -> Void

            @usableFromInline
            init(
                create: @escaping @Sendable () async throws(Pool.Lifecycle.Error) -> sending Resource,
                destroy: @escaping @Sendable (consuming Resource) -> Void
            ) {
                self.create = create
                self.destroy = destroy
            }
        }
    }
#endif
