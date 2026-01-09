// MARK: - Move Accessor

extension Pool.Fixed.Entry where Resource: ~Copyable & Sendable {
    /// Accessor for move operations.
    @usableFromInline
    var move: Move {
        Move(entry: self)
    }
}

// MARK: - Move Type

extension Pool.Fixed.Entry where Resource: ~Copyable & Sendable {
    /// Namespace for resource move operations.
    @usableFromInline
    struct Move {
        @usableFromInline
        let entry: Pool.Fixed<Resource>.Entry

        @usableFromInline
        init(entry: Pool.Fixed<Resource>.Entry) {
            self.entry = entry
        }
    }
}

// MARK: - Move Operations

extension Pool.Fixed.Entry.Move where Resource: ~Copyable & Sendable {
    /// Takes the resource out of storage.
    ///
    /// - Precondition: Entry must be occupied.
    /// - Returns: The stored resource.
    @usableFromInline
    var out: Resource {
        precondition(entry.occupied, "Entry is not occupied")
        entry.occupied = false
        return entry.storage.move()
    }

    /// Puts a resource into storage.
    ///
    /// - Precondition: Entry must not be occupied.
    /// - Parameter value: The resource to store.
    @usableFromInline
    func `in`(_ value: consuming Resource) {
        precondition(!entry.occupied, "Entry is already occupied")
        entry.storage.initialize(to: value)
        entry.occupied = true
    }
}
