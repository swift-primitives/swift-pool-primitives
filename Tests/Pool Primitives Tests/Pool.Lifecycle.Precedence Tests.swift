import Test_Support_Primitives
import Testing
import Async_Primitives

@testable import Pool_Primitives

extension Pool.Lifecycle.Precedence {
    #TestSuites
}

// MARK: - Unit Tests

extension Pool.Lifecycle.Precedence.Test.Unit {
    @Test("success passes through when no flags set")
    func successPassesThrough() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: false,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .success(42))
    }

    @Test("shutdown dominates success")
    func shutdownDominatesSuccess() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: false,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }

    @Test("shutdown dominates cancellation")
    func shutdownDominatesCancellation() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: true,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }

    @Test("shutdown dominates timeout")
    func shutdownDominatesTimeout() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: false,
            timedOut: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }

    @Test("cancellation dominates success")
    func cancellationDominatesSuccess() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: true,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.cancelled))
    }

    @Test("cancellation dominates timeout")
    func cancellationDominatesTimeout() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: true,
            timedOut: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.cancelled))
    }

    @Test("timeout dominates success")
    func timeoutDominatesSuccess() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: false,
            timedOut: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.timeout))
    }

    @Test("failure passes through when no flags set")
    func failurePassesThrough() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: false,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.failure(.timeout)
        )

        #expect(result == .failure(.timeout))
    }
}

// MARK: - Edge Cases

extension Pool.Lifecycle.Precedence.Test.EdgeCase {
    @Test("all flags set returns shutdown")
    func allFlagsSetReturnsShutdown() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: true,
            timedOut: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }
}
