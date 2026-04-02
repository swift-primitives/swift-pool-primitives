import Testing
import Pool_Primitives_Test_Support

import Pool_Primitives

// Pool.Lifecycle.State is non-generic — type extension per [TEST-003]
extension Pool.Lifecycle.State {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
    }
}

// MARK: - Unit Tests

extension Pool.Lifecycle.State.Test.Unit {
    @Test
    func `initial state is open`() {
        var state = Pool.Lifecycle.State.open
        #expect(!state.shutdown.isActive)
    }

    @Test
    func `shutdown begin transitions to closing`() {
        var state = Pool.Lifecycle.State.open
        let transitioned = state.shutdown.begin()

        #expect(transitioned)
        #expect(state == .closing)
        #expect(state.shutdown.isActive)
    }

    @Test
    func `shutdown begin is idempotent`() {
        var state = Pool.Lifecycle.State.open
        _ = state.shutdown.begin()
        let secondAttempt = state.shutdown.begin()

        #expect(!secondAttempt)
        #expect(state == .closing)
    }

    @Test
    func `shutdown complete transitions to closed`() {
        var state = Pool.Lifecycle.State.closing
        let transitioned = state.shutdown.complete()

        #expect(transitioned)
        #expect(state == .closed)
    }

    @Test
    func `shutdown complete from open fails`() {
        var state = Pool.Lifecycle.State.open
        let transitioned = state.shutdown.complete()

        #expect(!transitioned)
        #expect(state == .open)
    }

    @Test
    func `shutdown isActive for all states`() {
        var open = Pool.Lifecycle.State.open
        var closing = Pool.Lifecycle.State.closing
        var closed = Pool.Lifecycle.State.closed
        #expect(!open.shutdown.isActive)
        #expect(closing.shutdown.isActive)
        #expect(closed.shutdown.isActive)
    }
}

// MARK: - Edge Cases

extension Pool.Lifecycle.State.Test.EdgeCase {
    @Test
    func `closed state cannot transition further`() {
        var state = Pool.Lifecycle.State.closed

        let beginResult = state.shutdown.begin()
        #expect(!beginResult)
        #expect(state == .closed)

        let completeResult = state.shutdown.complete()
        #expect(!completeResult)
        #expect(state == .closed)
    }
}
