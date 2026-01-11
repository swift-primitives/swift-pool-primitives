extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Reference-based destructor for eager policy.
    @usableFromInline
    final class Destructor: @unchecked Sendable {
        @usableFromInline
        let destroy: @Sendable (consuming Resource) -> Void

        @usableFromInline
        init(_ destroy: @Sendable @escaping (consuming Resource) -> Void) {
            self.destroy = destroy
        }
    }
}

// MARK: - Destructor Access

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Gets the destructor from either policy.
    @usableFromInline
    var destructor: @Sendable (consuming Resource) -> Void {
        switch policy {
        case .eager(let d): return d.destroy
        case .lazy(let c): return c.destroy
        }
    }
}
