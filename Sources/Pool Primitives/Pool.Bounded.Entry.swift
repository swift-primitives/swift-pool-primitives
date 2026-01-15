extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Class wrapper for Resource storage.
    ///
    /// This is the ONLY place Resource is stored. Arrays of Entry
    /// are Copyable because they're arrays of class references.
    ///
    /// Uses manual single-slot storage to avoid Optional<Resource>
    /// which would require Resource: Copyable under strict move-only modes.
    @safe
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
            let ptr = UnsafeMutablePointer<Resource>.allocate(capacity: 1)
            unsafe self.storage = ptr
            unsafe ptr.initialize(to: value)
            self.occupied = true
        }

        /// Creates an empty entry (slot allocated but unoccupied).
        @usableFromInline
        init() {
            let ptr = UnsafeMutablePointer<Resource>.allocate(capacity: 1)
            unsafe self.storage = ptr
            self.occupied = false
        }

        deinit {
            if occupied {
                unsafe storage.deinitialize(count: 1)
            }
            unsafe storage.deallocate()
        }
    }
}
