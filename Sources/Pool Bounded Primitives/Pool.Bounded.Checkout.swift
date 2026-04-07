extension Pool.Bounded where Resource: ~Copyable {
    /// Pure ownership token for a checked-out resource.
    ///
    /// This is ~Copyable but does NOT store the Resource itself.
    /// It stores only (slot, entry, id) - no pool reference.
    /// Resource is extracted to a LOCAL variable for body execution.
    ///
    /// No pool reference - return-to-pool happens in the scope
    /// that already has `self`.
    @usableFromInline
    struct Checkout: ~Copyable {
        /// The slot index this checkout came from.
        @usableFromInline
        let slot: Slot.Index

        /// Reference to the entry holding the resource.
        @usableFromInline
        let entry: Entry

        /// The ID for this checkout (for return validation).
        @usableFromInline
        let id: Pool.ID

        /// Creates a checkout token.
        @usableFromInline
        init(slot: Slot.Index, entry: Entry, id: Pool.ID) {
            self.slot = slot
            self.entry = entry
            self.id = id
        }
    }
}
