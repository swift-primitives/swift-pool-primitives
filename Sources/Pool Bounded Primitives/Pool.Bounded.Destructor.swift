#if POOL_CONCURRENCY
    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        typealias Destructor = @Sendable (consuming Resource) async -> Void
    }

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        var destructor: @Sendable (consuming Resource) async -> Void {
            switch policy {
            case .eager(let d): return d

            case .lazy(let c): return c.destroy
            }
        }
    }
#endif
