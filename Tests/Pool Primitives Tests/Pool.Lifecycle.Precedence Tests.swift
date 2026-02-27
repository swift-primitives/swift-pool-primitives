import Testing
import Pool_Primitives_Test_Support

import Pool_Primitives

// Pool.Lifecycle.Precedence is non-generic — type extension per [TEST-003]
extension Pool.Lifecycle.Precedence {
    @Suite
    struct Test {
        @Suite struct Unit {}
        @Suite struct EdgeCase {}
    }
}

// MARK: - Unit Tests

extension Pool.Lifecycle.Precedence.Test.Unit {
    @Test
    func `success passes through when no flags set`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: false,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .success(42))
    }

    @Test
    func `shutdown dominates success`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: false,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }

    @Test
    func `shutdown dominates cancellation`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: true,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }

    @Test
    func `shutdown dominates timeout`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: false,
            timedOut: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }

    @Test
    func `cancellation dominates success`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: true,
            timedOut: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.cancelled))
    }

    @Test
    func `cancellation dominates timeout`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: true,
            timedOut: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.cancelled))
    }

    @Test
    func `timeout dominates success`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: false,
            timedOut: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.timeout))
    }

    @Test
    func `failure passes through when no flags set`() {
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
    @Test
    func `all flags set returns shutdown`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: true,
            timedOut: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }
}
