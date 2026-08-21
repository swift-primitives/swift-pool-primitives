public import Dimension_Primitives

extension Pool {

    public struct ID: Sendable, Hashable {

        @usableFromInline
        let raw: RawValue

        @usableFromInline
        let scope: Scope

        @_spi(Internal)
        public init(raw: UInt64, scope: Pool.Scope) {
            self.raw = RawValue(_unchecked: raw)
            self.scope = scope
        }
    }
}

extension Pool.ID {

    public typealias RawValue = Tagged<Self, UInt64>
}
