public import Dimension_Primitives

extension Pool.Bounded where Resource: ~Copyable {
    /// A slot in the pool that can hold a resource.
    @usableFromInline
    struct Slot {
        /// Typed index into the slots array.
        @usableFromInline
        typealias Index = Tagged<Self, Ordinal>

        /// The slot index.
        @usableFromInline
        let index: Index

        /// Current state.
        @usableFromInline
        var state: State

        /// Creates an empty slot.
        @usableFromInline
        init(index: Index) {
            self.index = index
            self.state = .empty
        }
    }
}
