public import Reference_Primitives

extension Pool.Bounded where Resource: ~Copyable & Sendable {
    /// Class wrapper for Resource storage.
    ///
    /// This is the ONLY place Resource is stored. Arrays of Entry
    /// are Copyable because they're arrays of class references.
    ///
    /// Entry is a typealias to `Reference.Slot`, which provides:
    /// - Heap-allocated single-slot storage for `~Copyable` values
    /// - Atomic store/take operations for thread safety
    /// - `store(_:)` to move a value in (precondition: empty)
    /// - `take()` to move a value out (precondition: full)
    /// - `isEmpty` / `isFull` for state inspection
    @usableFromInline
    typealias Entry = Reference.Slot<Resource>
}
