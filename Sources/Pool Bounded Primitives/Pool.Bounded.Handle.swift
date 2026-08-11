extension Pool.Bounded where Resource: ~Copyable {
    /// Unique ownership of one checked-out resource.
    ///
    /// `Handle` is deliberately non-`Sendable`. Transfer it into one task or
    /// actor region through the `sending` checkout result; never share it.
    public struct Handle: ~Copyable {
        @usableFromInline
        let storage: Storage

        @usableFromInline
        init(
            resource: consuming sending Resource,
            pool: Pool.Bounded<Resource>,
            slot: Pool.Bounded<Resource>.Slot.Index,
            id: Pool.ID
        ) {
            self.storage = Storage(
                resource: resource,
                pool: pool,
                slot: slot,
                id: id
            )
        }
    }
}

extension Pool.Bounded.Handle where Resource: ~Copyable {
    /// Lifetime-dependent access to the checked-out resource.
    public var resource: Resource {
        @_lifetime(borrow self)
        borrowing get {
            guard let resource = storage.resource else {
                preconditionFailure("Pool.Bounded.Handle used after resolution")
            }
            return resource
        }

        _modify {
            guard case .some = storage.resource else {
                preconditionFailure("Pool.Bounded.Handle used after resolution")
            }
            yield &storage.resource!
        }
    }

    /// Resolves the resource exactly once and returns the operation result.
    ///
    /// Resolution is a terminal join. Cancellation does not abandon cleanup,
    /// and concurrent shutdown cannot erase an already-produced move-only value.
    public consuming func resolve<Value: ~Copyable>(
        _ resolution: consuming Resolution<Value>
    ) async -> sending Value {
        let resource = consume storage.resource
        storage.resource = nil
        guard let resource = consume resource else {
            preconditionFailure("Pool.Bounded.Handle resolved more than once")
        }

        switch consume resolution {
        case .reusable(let value):
            _ = await storage.pool.release(
                resource,
                from: storage.slot,
                id: storage.id,
                as: .reusable
            )
            return value

        case .invalid(let value):
            _ = await storage.pool.release(
                resource,
                from: storage.slot,
                id: storage.id,
                as: .invalid
            )
            return value
        }
    }
}
