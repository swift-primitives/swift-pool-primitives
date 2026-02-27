import Testing
import Pool_Primitives_Test_Support
import Ownership_Primitives

@_spi(Internal) @testable import Pool_Primitives_Core
import Pool_Primitives

// MARK: - Test Resource

private struct TestResource: Sendable {
    let id: Int
}

// MARK: - Tests

// Pool.Acquire is generic — parallel namespace per [TEST-004]
@Suite
struct PoolAcquireTests {
    @Suite struct Unit {}
}

extension PoolAcquireTests.Unit {
    @Test
    func `effect stores scope as arguments`() {
        let scope = Pool.Scope()
        let effect = Pool.Acquire<TestResource>(scope: scope)

        #expect(effect.scope == scope)
        #expect(effect.arguments == scope)
    }

    @Test
    func `effect is Sendable`() {
        func requiresSendable<T: Sendable>(_: T.Type) {}
        requiresSendable(Pool.Acquire<TestResource>.self)
    }

    @Test
    func `value type is Ownership Shared`() {
        let _: Pool.Acquire<TestResource>.Value.Type = Ownership.Shared<TestResource>.self
    }

    @Test
    func `failure type is Pool Error`() {
        let _: Pool.Acquire<TestResource>.Failure.Type = Pool.Error.self
    }

    @Test
    func `different scopes produce different effects`() {
        let scope1 = Pool.Scope()
        let scope2 = Pool.Scope()

        let effect1 = Pool.Acquire<TestResource>(scope: scope1)
        let effect2 = Pool.Acquire<TestResource>(scope: scope2)

        #expect(effect1.scope != effect2.scope)
    }
}
