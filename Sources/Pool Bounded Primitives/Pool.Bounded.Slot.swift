#if POOL_CONCURRENCY
    public import Dimension_Primitives

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        struct Slot {

            @usableFromInline
            let index: Index

            @usableFromInline
            var state: State

            @usableFromInline
            init(index: Index) {
                self.index = index
                self.state = .empty
            }
        }
    }
    extension Pool.Bounded.Slot where Resource: ~Copyable {

        @usableFromInline
        typealias Index = Tagged<Self, Ordinal>
    }
#endif
