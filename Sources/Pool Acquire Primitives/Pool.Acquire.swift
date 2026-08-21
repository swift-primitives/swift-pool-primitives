public import Effect_Primitives
public import Ownership_Primitives

extension Pool {

    public struct Acquire<Resource: ~Copyable>: Effect.`Protocol` {

        public typealias Arguments = Pool.Scope

        public typealias Value = Ownership.Immutable<Resource>

        public typealias Failure = Pool.Error

        public let scope: Pool.Scope

        public var arguments: Pool.Scope { scope }

        @inlinable
        public init(scope: Pool.Scope) {
            self.scope = scope
        }
    }
}
