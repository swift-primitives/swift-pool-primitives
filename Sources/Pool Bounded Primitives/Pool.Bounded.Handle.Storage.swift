extension Pool.Bounded.Handle where Resource: ~Copyable {
    /// The single cleanup truth for one checked-out resource.
    @usableFromInline
    final class Storage {
        @usableFromInline
        var resource: Resource?

        @usableFromInline
        let pool: Pool.Bounded<Resource>

        @usableFromInline
        let slot: Pool.Bounded<Resource>.Slot.Index

        @usableFromInline
        let id: Pool.ID

        @usableFromInline
        init(
            resource: consuming sending Resource,
            pool: Pool.Bounded<Resource>,
            slot: Pool.Bounded<Resource>.Slot.Index,
            id: Pool.ID
        ) {
            self.resource = resource
            self.pool = pool
            self.slot = slot
            self.id = id
        }

        deinit {
            let resource = consume self.resource
            self.resource = nil
            guard let resource = consume resource else { return }
            pool.abandon(resource, from: slot, id: id)
        }
    }
}
