import Pool_Primitives
import Pool_Primitives_Test_Support
import Testing

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
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .success(42))
    }

    @Test
    func `shutdown dominates success`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }

    @Test
    func `shutdown dominates cancellation`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }

    @Test
    func `cancellation dominates success`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.cancelled))
    }

    @Test
    func `failure passes through when no flags set`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .open,
            cancelled: false,
            outcome: Result<Int, Pool.Lifecycle.Error>.failure(.creationFailed)
        )

        #expect(result == .failure(.creationFailed))
    }
}

// MARK: - Edge Cases

extension Pool.Lifecycle.Precedence.Test.EdgeCase {
    @Test
    func `all flags set returns shutdown`() {
        let result = Pool.Lifecycle.Precedence.apply(
            lifecycle: .closing,
            cancelled: true,
            outcome: Result<Int, Pool.Lifecycle.Error>.success(42)
        )

        #expect(result == .failure(.shutdown))
    }
}
