public import Reference_Primitives

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Reference-based destructor for eager policy.
    ///
    /// Uses `Reference.Box` for standardized immutable heap storage with
    /// explicit Sendable semantics.
    @usableFromInline
    typealias Destructor = Reference.Box<@Sendable (consuming Resource) -> Void>
}

// MARK: - Destructor Access

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Gets the destructor from either policy.
    @usableFromInline
    var destructor: @Sendable (consuming Resource) -> Void {
        switch policy {
        case .eager(let d): return d.value
        case .lazy(let c): return c.value.destroy
        }
    }
}
