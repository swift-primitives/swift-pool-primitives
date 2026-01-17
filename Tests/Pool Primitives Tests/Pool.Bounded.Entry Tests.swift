import Reference_Primitives
import Test_Primitives
import Testing_Extras

@testable import Pool_Primitives

// Pool.Bounded.Entry is generic, so we test via a concrete helper namespace
enum PoolFixedEntryTests {
    #TestSuites
}

// MARK: - Type Aliases

private typealias TestPool = Pool.Bounded<Int>
private typealias Entry = TestPool.Entry

// MARK: - Unit Tests

extension PoolFixedEntryTests.Test.Unit {
    @Test("empty entry is empty")
    func emptyEntryIsEmpty() {
        let entry = Entry()
        #expect(entry.isEmpty)
    }

    @Test("entry with value is occupied")
    func entryWithValueIsOccupied() {
        let entry = Entry(42)
        #expect(entry.isFull)
    }

    @Test("move.in stores value")
    func moveInStoresValue() {
        let entry = Entry()
        entry.move.in(99)
        #expect(entry.isFull)
    }

    @Test("move.out retrieves value")
    func moveOutRetrievesValue() {
        let entry = Entry(42)
        let value = entry.move.out
        #expect(value == 42)
        #expect(entry.isEmpty)
    }

    @Test("move.in after move.out works")
    func moveInAfterMoveOutWorks() {
        let entry = Entry(42)
        _ = entry.move.out
        entry.move.in(100)
        #expect(entry.isFull)
        #expect(entry.move.out == 100)
    }
}

// MARK: - Edge Cases

extension PoolFixedEntryTests.Test.EdgeCase {
    @Test("multiple move cycles work correctly")
    func multipleMovesCyclesWorkCorrectly() {
        let entry = Entry()

        for i in 0..<10 {
            entry.move.in(i)
            let value = entry.move.out
            #expect(value == i)
        }

        #expect(entry.isEmpty)
    }
}
