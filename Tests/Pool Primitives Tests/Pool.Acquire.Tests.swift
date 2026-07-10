import Ownership_Primitives
import Pool_Primitives
import Pool_Primitives_Test_Support
import Testing

@_spi(Internal) @testable import Pool_Scope_Primitives

// MARK: - Test Resource

private struct TestResource: Sendable {
    let id: Int
}

// MARK: - Tests

// Pool.Acquire is generic — parallel namespace per [TEST-004]
@Suite
struct `Pool.Acquire Tests` {
    @Suite struct Unit {}
}

extension `Pool.Acquire Tests`.Unit {
    @Test
    func `effect stores scope as arguments`() {
        let scope = Pool.Scope()
        let effect = Pool.Acquire<TestResource>(scope: scope)

        #expect(effect.scope == scope)
        #expect(effect.arguments == scope)
    }

    @Test
    func `value type is Ownership Shared`() {
        let _: Pool.Acquire<TestResource>.Value.Type = Ownership.Immutable<TestResource>.self
    }

    @Test
    func `failure type is Pool Swift.Error`() {
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
