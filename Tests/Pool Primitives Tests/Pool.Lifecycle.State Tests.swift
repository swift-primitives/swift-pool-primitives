import Pool_Primitives
import Pool_Primitives_Test_Support
import Testing

// Pool.Lifecycle.State is non-generic — type extension per [TEST-003]
extension Pool.Lifecycle.State {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct `Edge Case` {}
    }
}

// MARK: - Unit Tests

extension Pool.Lifecycle.State.Test.Unit {
    @Test
    func `initial state is open`() {
        var state = Pool.Lifecycle.State.open
        let isActive = state.shutdown.isActive
        #expect(!isActive)
    }

    @Test
    func `shutdown begin transitions to closing`() {
        var state = Pool.Lifecycle.State.open
        let transitioned = state.shutdown.begin()
        let isActive = state.shutdown.isActive

        #expect(transitioned)
        #expect(state == .closing)
        #expect(isActive)
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
        let openIsActive = open.shutdown.isActive
        let closingIsActive = closing.shutdown.isActive
        let closedIsActive = closed.shutdown.isActive
        #expect(!openIsActive)
        #expect(closingIsActive)
        #expect(closedIsActive)
    }
}

// MARK: - Edge Cases

extension Pool.Lifecycle.State.Test.`Edge Case` {
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
