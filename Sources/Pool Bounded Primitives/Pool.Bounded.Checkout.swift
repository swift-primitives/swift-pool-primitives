extension Pool.Bounded where Resource: ~Copyable {
    /// Accessor for unique checked-out handles.
    public var checkout: Checkout {
        Checkout(pool: self)
    }

    /// The asynchronous checked-out-handle operation.
    public struct Checkout: Sendable {
        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        init(pool: Pool.Bounded<Resource>) {
            self.pool = pool
        }
    }
}

extension Pool.Bounded.Checkout where Resource: ~Copyable {
    /// Waits for and transfers unique ownership of one resource.
    nonisolated(nonsending)
    public func callAsFunction() async throws(Pool.Lifecycle.Error) -> sending Pool.Bounded<Resource>.Handle {
        while true {
            let (slot, id) = try await pool.acquireSlot()
            var resource = pool.entries.underlying[
                slot.retag(Pool.Bounded<Resource>.Entry.self)
            ].move.out

            if let check = pool._check, !check(&resource) {
                if let error = await pool.release(resource, from: slot, id: id, as: .invalid) {
                    throw error
                }
                continue
            }

            let admission: Pool.Lifecycle.Error? = pool._state.withLock { state in
                if state.lifecycle.shutdown.isActive { return .shutdown }
                if Task.isCancelled { return .cancelled }
                return nil
            }
            if let admission {
                _ = await pool.release(resource, from: slot, id: id, as: .invalid)
                throw admission
            }

            return Pool.Bounded<Resource>.Handle(
                resource: resource,
                pool: pool,
                slot: slot,
                id: id
            )
        }
    }
}
