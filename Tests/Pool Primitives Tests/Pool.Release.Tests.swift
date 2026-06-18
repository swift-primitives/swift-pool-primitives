import Pool_Primitives
import Pool_Primitives_Test_Support
import Testing

@_spi(Internal) @testable import Pool_Scope_Primitives
@_spi(Internal) @testable import Pool_ID_Primitives

// MARK: - Test Resource

private struct TestResource: Sendable {
    let id: Int
}

// MARK: - Tests

// Pool.Release is generic — parallel namespace per [TEST-004]
@Suite
struct PoolReleaseTests {
    @Suite struct Unit {}
}

extension PoolReleaseTests.Unit {
    @Test
    func `effect stores id as arguments`() {
        let scope = Pool.Scope()
        let id = Pool.ID(raw: 1, scope: scope)
        let effect = Pool.Release<TestResource>(id: id)

        #expect(effect.id == id)
        #expect(effect.arguments == id)
    }

    @Test
    func `value type is Void`() {
        let _: Pool.Release<TestResource>.Value.Type = Void.self
    }

    @Test
    func `failure type is Never`() {
        let _: Pool.Release<TestResource>.Failure.Type = Never.self
    }

    @Test
    func `different ids produce different effects`() {
        let scope = Pool.Scope()
        let id1 = Pool.ID(raw: 1, scope: scope)
        let id2 = Pool.ID(raw: 2, scope: scope)

        let effect1 = Pool.Release<TestResource>(id: id1)
        let effect2 = Pool.Release<TestResource>(id: id2)

        #expect(effect1.id != effect2.id)
    }
}
