public import Dimension_Primitives
import Synchronization

/// Global counter for scope generation.
private let _scopeCounter = Atomic<UInt64>(0)

extension Pool {
    /// Unique scope identifier for a pool instance.
    ///
    /// Used to validate that IDs belong to the correct pool.
    public struct Scope: Sendable, Hashable {
        /// The raw scope value.
        public typealias RawValue = Tagged<Self, UInt64>

        @usableFromInline
        let value: RawValue

        /// Creates a new unique scope.
        @usableFromInline
        init() {
            self.value = RawValue(_scopeCounter.wrappingAdd(1, ordering: .relaxed).oldValue)
        }
    }
}
