extension Pool.Fixed where Resource: ~Copyable & Sendable {
    /// Class wrapper for Resource storage.
    ///
    /// This is the ONLY place Resource is stored. Arrays of Entry
    /// are Copyable because they're arrays of class references.
    ///
    /// Uses manual single-slot storage to avoid Optional<Resource>
    /// which would require Resource: Copyable under strict move-only modes.
    @usableFromInline
    final class Entry: @unchecked Sendable {
        /// Single-slot storage for the resource.
        @usableFromInline
        let storage: UnsafeMutablePointer<Resource>

        /// Whether storage contains a valid resource.
        @usableFromInline
        var occupied: Bool

        /// Creates an entry with a resource.
        @usableFromInline
        init(_ value: consuming Resource) {
            self.storage = .allocate(capacity: 1)
            self.storage.initialize(to: value)
            self.occupied = true
        }

        /// Creates an empty entry (slot allocated but unoccupied).
        @usableFromInline
        init() {
            self.storage = .allocate(capacity: 1)
            self.occupied = false
        }

        deinit {
            if occupied {
                storage.deinitialize(count: 1)
            }
            storage.deallocate()
        }
    }
}
