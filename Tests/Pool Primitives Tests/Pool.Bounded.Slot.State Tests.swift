import Test_Primitives
import Testing_Extras

@testable import Pool_Primitives

// Pool.Bounded.Slot.State is generic, so we test via a concrete helper namespace
enum PoolFixedSlotStateTests {
    #TestSuites
}

// MARK: - Type Aliases

private typealias TestPool = Pool.Bounded<Int>
private typealias SlotState = TestPool.Slot.State

// MARK: - Unit Tests

extension PoolFixedSlotStateTests.Test.Unit {
    @Test("empty state has no ID")
    func emptyStateHasNoID() {
        let state = SlotState.empty

        if case .empty = state {
            // Expected
        } else {
            Issue.record("Expected empty state")
        }
    }

    @Test("available state carries ID")
    func availableStateCarriesID() {
        let id = Pool.ID(raw: 42, scope: Pool.Scope())
        let state = SlotState.available(id)

        if case .available(let storedId) = state {
            #expect(storedId == id)
        } else {
            Issue.record("Expected available state")
        }
    }

    @Test("out state carries ID")
    func outStateCarriesID() {
        let id = Pool.ID(raw: 42, scope: Pool.Scope())
        let state = SlotState.out(id)

        if case .out(let storedId) = state {
            #expect(storedId == id)
        } else {
            Issue.record("Expected out state")
        }
    }

    @Test("creating state carries ID")
    func creatingStateCarriesID() {
        let id = Pool.ID(raw: 42, scope: Pool.Scope())
        let state = SlotState.creating(id)

        if case .creating(let storedId) = state {
            #expect(storedId == id)
        } else {
            Issue.record("Expected creating state")
        }
    }

    @Test("disposing state carries ID")
    func disposingStateCarriesID() {
        let id = Pool.ID(raw: 42, scope: Pool.Scope())
        let state = SlotState.disposing(id)

        if case .disposing(let storedId) = state {
            #expect(storedId == id)
        } else {
            Issue.record("Expected disposing state")
        }
    }
}
