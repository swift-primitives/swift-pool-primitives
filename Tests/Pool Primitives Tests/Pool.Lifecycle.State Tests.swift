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
        let state = Pool.Lifecycle.State.open
        #expect(!state.isShuttingDown)
    }

    @Test
    func `beginShutdown transitions to closing`() {
        var state = Pool.Lifecycle.State.open
        let transitioned = state.beginShutdown()

        #expect(transitioned)
        #expect(state == .closing)
        #expect(state.isShuttingDown)
    }

    @Test
    func `beginShutdown is idempotent`() {
        var state = Pool.Lifecycle.State.open
        _ = state.beginShutdown()
        let secondAttempt = state.beginShutdown()

        #expect(!secondAttempt)
        #expect(state == .closing)
    }

    @Test
    func `completeShutdown transitions to closed`() {
        var state = Pool.Lifecycle.State.closing
        let transitioned = state.completeShutdown()

        #expect(transitioned)
        #expect(state == .closed)
    }

    @Test
    func `completeShutdown from open fails`() {
        var state = Pool.Lifecycle.State.open
        let transitioned = state.completeShutdown()

        #expect(!transitioned)
        #expect(state == .open)
    }

    @Test
    func `isShuttingDown for all states`() {
        #expect(!Pool.Lifecycle.State.open.isShuttingDown)
        #expect(Pool.Lifecycle.State.closing.isShuttingDown)
        #expect(Pool.Lifecycle.State.closed.isShuttingDown)
    }
}

// MARK: - Edge Cases

extension Pool.Lifecycle.State.Test.EdgeCase {
    @Test
    func `closed state cannot transition further`() {
        var state = Pool.Lifecycle.State.closed

        let beginResult = state.beginShutdown()
        #expect(!beginResult)
        #expect(state == .closed)

        let completeResult = state.completeShutdown()
        #expect(!completeResult)
        #expect(state == .closed)
    }
}
