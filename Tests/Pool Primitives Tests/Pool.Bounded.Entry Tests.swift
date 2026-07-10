import Pool_Primitives
import Pool_Primitives_Test_Support
import Testing

@testable import Pool_Bounded_Primitives

// Pool.Bounded.Entry is generic — parallel namespace per [TEST-004]
@Suite
struct `Pool.Bounded.Entry Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
}

// MARK: - Type Aliases

private typealias TestPool = Pool.Bounded<Int>
private typealias Entry = TestPool.Entry

// MARK: - Unit Tests

extension `Pool.Bounded.Entry Tests`.Unit {
    @Test
    func `empty entry is empty`() {
        let entry = Entry()
        #expect(entry.isEmpty)
    }

    @Test
    func `entry with value is occupied`() {
        let entry = Entry(42)
        #expect(entry.isFull)
    }

    @Test
    func `move in stores value`() {
        let entry = Entry()
        entry.move.in(99)
        #expect(entry.isFull)
    }

    @Test
    func `move out retrieves value`() {
        let entry = Entry(42)
        let value = entry.move.out
        #expect(value == 42)
        #expect(entry.isEmpty)
    }

    @Test
    func `move in after move out works`() {
        let entry = Entry(42)
        _ = entry.move.out
        entry.move.in(100)
        #expect(entry.isFull)
        #expect(entry.move.out == 100)
    }
}

// MARK: - Edge Cases

extension `Pool.Bounded.Entry Tests`.`Edge Case` {
    @Test
    func `multiple move cycles work correctly`() {
        let entry = Entry()

        for i in 0..<10 {
            entry.move.in(i)
            let value = entry.move.out
            #expect(value == i)
        }

        #expect(entry.isEmpty)
    }
}
