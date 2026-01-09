import Test_Support_Primitives
import Testing
import Async_Primitives

@testable import Pool_Primitives

extension Pool.Lifecycle.State {
    #TestSuites
}

// MARK: - Unit Tests

extension Pool.Lifecycle.State.Test.Unit {
    @Test("initial state is open")
    func initialStateIsOpen() {
        let state = Pool.Lifecycle.State.open
        #expect(!state.isShuttingDown)
    }

    @Test("beginShutdown transitions to closing")
    func beginShutdownTransitionsToClosing() {
        var state = Pool.Lifecycle.State.open
        let transitioned = state.beginShutdown()

        #expect(transitioned)
        #expect(state == .closing)
        #expect(state.isShuttingDown)
    }

    @Test("beginShutdown is idempotent")
    func beginShutdownIsIdempotent() {
        var state = Pool.Lifecycle.State.open
        _ = state.beginShutdown()
        let secondAttempt = state.beginShutdown()

        #expect(!secondAttempt)
        #expect(state == .closing)
    }

    @Test("completeShutdown transitions to closed")
    func completeShutdownTransitionsToClosed() {
        var state = Pool.Lifecycle.State.closing
        let transitioned = state.completeShutdown()

        #expect(transitioned)
        #expect(state == .closed)
    }

    @Test("completeShutdown from open fails")
    func completeShutdownFromOpenFails() {
        var state = Pool.Lifecycle.State.open
        let transitioned = state.completeShutdown()

        #expect(!transitioned)
        #expect(state == .open)
    }

    @Test("isShuttingDown for all states")
    func isShuttingDownForAllStates() {
        #expect(!Pool.Lifecycle.State.open.isShuttingDown)
        #expect(Pool.Lifecycle.State.closing.isShuttingDown)
        #expect(Pool.Lifecycle.State.closed.isShuttingDown)
    }
}

// MARK: - Edge Cases

extension Pool.Lifecycle.State.Test.EdgeCase {
    @Test("closed state cannot transition further")
    func closedStateCannotTransitionFurther() {
        var state = Pool.Lifecycle.State.closed

        let beginResult = state.beginShutdown()
        #expect(!beginResult)
        #expect(state == .closed)

        let completeResult = state.completeShutdown()
        #expect(!completeResult)
        #expect(state == .closed)
    }
}
