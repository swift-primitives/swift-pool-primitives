import Pool_Primitives
import Pool_Primitives_Test_Support
import Testing

@testable import Pool_Bounded_Primitives
@_spi(Internal) @testable import Pool_Scope_Primitives

// Pool.Bounded.Slot.State is generic — parallel namespace per [TEST-004]
@Suite
struct PoolBoundedSlotStateTests {
    @Suite struct Unit {}
}

// MARK: - Type Aliases

private typealias TestPool = Pool.Bounded<Int>
private typealias SlotState = TestPool.Slot.State

// MARK: - Unit Tests

extension PoolBoundedSlotStateTests.Unit {
    @Test
    func `empty state has no ID`() {
        let state = SlotState.empty

        if case .empty = state {
            // Expected
        } else {
            Issue.record("Expected empty state")
        }
    }

    @Test
    func `available state carries ID`() {
        let id = Pool.ID(raw: 42, scope: Pool.Scope())
        let state = SlotState.available(id)

        if case .available(let storedId) = state {
            #expect(storedId == id)
        } else {
            Issue.record("Expected available state")
        }
    }

    @Test
    func `out state carries ID`() {
        let id = Pool.ID(raw: 42, scope: Pool.Scope())
        let state = SlotState.out(id)

        if case .out(let storedId) = state {
            #expect(storedId == id)
        } else {
            Issue.record("Expected out state")
        }
    }

    @Test
    func `creating state carries ID`() {
        let id = Pool.ID(raw: 42, scope: Pool.Scope())
        let state = SlotState.creating(id)

        if case .creating(let storedId) = state {
            #expect(storedId == id)
        } else {
            Issue.record("Expected creating state")
        }
    }

    @Test
    func `disposing state carries ID`() {
        let id = Pool.ID(raw: 42, scope: Pool.Scope())
        let state = SlotState.disposing(id)

        if case .disposing(let storedId) = state {
            #expect(storedId == id)
        } else {
            Issue.record("Expected disposing state")
        }
    }
}
