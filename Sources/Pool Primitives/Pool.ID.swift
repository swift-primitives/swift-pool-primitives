public import Dimension_Primitives

extension Pool {
    /// Unique identifier for a checked-out resource.
    public struct ID: Sendable, Hashable {
        /// The raw identifier type.
        public typealias RawValue = Tagged<Self, UInt64>

        /// The raw identifier value.
        @usableFromInline
        let raw: RawValue

        /// The pool scope this ID belongs to.
        @usableFromInline
        let scope: Scope

        /// Creates a new ID within the given scope.
        @usableFromInline
        init(raw: UInt64, scope: Pool.Scope) {
            self.raw = RawValue(__unchecked: (), raw)
            self.scope = scope
        }
    }
}
