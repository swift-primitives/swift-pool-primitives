extension Pool.Bounded where Resource: ~Copyable {
    /// Destructor closure type for eager policy.
    ///
    /// Stored directly as a closure value — no `Ownership.Shared` wrap.
    /// Closures are already reference-typed in Swift; an extra heap
    /// indirection is gratuitous. The `@Sendable` annotation enforces that
    /// captures are safely shareable, which is necessary because the
    /// closure may be invoked from a Task context distinct from the caller
    /// that constructed the pool.
    @usableFromInline
    typealias Destructor = @Sendable (consuming Resource) -> Void
}

// MARK: - Destructor Access

extension Pool.Bounded where Resource: ~Copyable {
    /// Gets the destructor from either policy.
    @usableFromInline
    var destructor: @Sendable (consuming Resource) -> Void {
        switch policy {
        case .eager(let d): return d
        #if !hasFeature(Embedded)
            case .lazy(let c): return c.destroy
        #endif
        }
    }
}
