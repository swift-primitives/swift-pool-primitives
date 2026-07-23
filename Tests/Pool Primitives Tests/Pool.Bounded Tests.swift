import Async_Primitives
import Either_Primitives
import Pool_Primitives
import Pool_Primitives_Test_Support
import Synchronization
import Testing

@testable import Pool_Bounded_Primitives
@_spi(Internal) @testable import Pool_Error_Primitives

@Suite(.serialized)
struct `Pool.Bounded Tests` {
    @Suite struct Unit {}
    @Suite struct `Edge Case` {}
    @Suite struct Integration {}
}

private typealias TestPool = Pool.Bounded<Int>

extension `Pool.Bounded Tests`.Unit {
    @Test
    func `reusable disposition returns the resource to the pool`() async throws {
        let pool = TestPool(capacity: 1, destroy: { _ in })
        try await pool.fill(41)

        let first: Int = try await pool.acquire { resource in
            resource += 1
            return .reusable(resource)
        }
        let second: Int = try await pool.acquire { resource in
            .reusable(resource)
        }

        #expect(first == 42)
        #expect(second == 42)
        #expect(pool.metrics.acquisitions == 2)
        #expect(pool.metrics.releases == 2)

        await pool.shutdown()
    }

    @Test
    func `pool accepts a non-Sendable resource`() async throws {
        let pool = Pool.Bounded<Handle>(capacity: 1, destroy: { _ in })
        try await pool.fill(Handle(value: 7))

        let result: Int = try await pool.acquire { handle in
            handle.value += 1
            return .reusable(handle.value)
        }

        #expect(result == 8)
        await pool.shutdown()
    }

    @Test
    func `lazy creation validates before body delivery`() async throws {
        let destroyed = Mutex(0)
        let pool = TestPool(
            capacity: 1,
            check: { $0 > 0 },
            create: { 0 },
            destroy: { _ in destroyed.withLock { $0 += 1 } }
        )

        do throws(Either<Pool.Lifecycle.Error, Never>) {
            let _: Int = try await pool.acquire { .reusable($0) }
            Issue.record("Expected creation failure")
        } catch {
            switch error {
            case .left(.creationFailed):
                break

            case .left(let other):
                Issue.record("Expected creation failure, got \(other)")
            }
        }

        #expect(destroyed.withLock { $0 } == 1)
        await pool.shutdown()
    }

    @Test
    func `lazy initializer orders capacity check create destroy`() async throws {
        let pool = TestPool(
            capacity: 1,
            check: { $0 > 0 },
            create: { 41 },
            destroy: { _ in }
        )

        let result: Int = try await pool.acquire { resource in
            resource += 1
            return .reusable(resource)
        }

        #expect(result == 42)
        await pool.shutdown()
    }

    @Test
    func `batch fill returns a typed count`() async throws {
        let pool = TestPool(capacity: 2, destroy: { _ in })

        var remaining = [1, 2, 3]
        let added: Index<Int>.Count = try await pool.fill.batch {
            remaining.isEmpty ? nil : remaining.removeFirst()
        }

        #expect(added == 2)
        await pool.shutdown()
    }

    @Test
    func `lazy initializer defaults check when omitted`() async throws {
        let pool = TestPool(
            capacity: 1,
            create: { 7 },
            destroy: { _ in }
        )

        let result: Int = try await pool.acquire { .reusable($0) }

        #expect(result == 7)
        await pool.shutdown()
    }
}

extension `Pool.Bounded Tests`.`Edge Case` {
    @Test
    func `explicit invalid disposition awaits asynchronous destruction`() async throws {
        let started = Async.Gate()
        let allow = Async.Gate()
        let completed = Async.Gate()
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in
                _ = started.open()
                await allow.wait()
            }
        )
        try await pool.fill(9)

        let task = Task {
            let result: Int
            do throws(Either<Pool.Lifecycle.Error, Never>) {
                result = try await pool.acquire { .invalid($0) }
            } catch {
                Issue.record("Unexpected acquire failure: \(error)")
                return Int?.none
            }
            _ = completed.open()
            return result
        }

        await started.wait()
        #expect(!completed.isOpen)
        _ = allow.open()
        let result = await task.value
        #expect(result == 9)

        await pool.shutdown()
    }

    @Test
    func `body throw is terminal`() async throws {
        let destroyed = Mutex(0)
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in destroyed.withLock { $0 += 1 } }
        )
        try await pool.fill(1)

        do throws(Either<Pool.Lifecycle.Error, Failure>) {
            let _: Int = try await pool.acquire { _ throws(Failure) in
                throw Failure()
            }
            Issue.record("Expected body failure")
        } catch {
            switch error {
            case .right(let failure):
                #expect(failure == Failure())

            case .left(let lifecycle):
                Issue.record("Expected body failure, got \(lifecycle)")
            }
        }

        #expect(destroyed.withLock { $0 } == 1)
        await pool.shutdown()
    }

    @Test
    func `body cancellation is terminal`() async throws {
        let bodyStarted = Async.Gate()
        let releaseBody = Async.Gate()
        let destroyed = Mutex(0)
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in destroyed.withLock { $0 += 1 } }
        )
        try await pool.fill(1)

        let task = Task {
            do throws(Either<Pool.Lifecycle.Error, Never>) {
                let _: Void = try await pool.acquire { _ in
                    _ = bodyStarted.open()
                    await releaseBody.wait()
                    return .reusable(())
                }
                return Pool.Lifecycle.Error?.none
            } catch {
                switch error {
                case .left(let lifecycle):
                    return lifecycle
                }
            }
        }

        await bodyStarted.wait()
        task.cancel()
        _ = releaseBody.open()

        let cancellation = await task.value
        #expect(cancellation == .cancelled)
        #expect(destroyed.withLock { $0 } == 1)
        await pool.shutdown()
    }

    @Test
    func `full fill disposal remains joined to concurrent shutdown`() async throws {
        let started = Async.Gate()
        let allow = Async.Gate()
        let shutdownCompleted = Async.Gate()
        let destroyed = Mutex(0)
        let pool = TestPool(
            capacity: 1,
            destroy: { _ in
                destroyed.withLock { $0 += 1 }
                _ = started.open()
                await allow.wait()
            }
        )
        try await pool.fill(1)

        let fill = Task {
            do throws(TestPool.Fill.Error) {
                try await pool.fill(2)
                return TestPool.Fill.Error?.none
            } catch {
                return error
            }
        }

        await started.wait()
        let shutdown = Task {
            await pool.shutdown()
            _ = shutdownCompleted.open()
        }

        #expect(!shutdownCompleted.isOpen)
        _ = allow.open()
        let fillError = await fill.value
        #expect(fillError == .full)
        await shutdown.value
        #expect(destroyed.withLock { $0 } == 2)
    }
}

#if DEBUG
    extension `Pool.Bounded Tests`.Integration {
        @Test
        func `failed return validation replaces before waiter delivery`() async throws {
            let firstBody = Async.Gate()
            let releaseFirst = Async.Gate()
            let waiterEnqueued = Async.Gate()
            let created = Mutex(0)
            let destroyed = Mutex(0)
            let pool = TestPool(
                capacity: 1,
                check: { $0 < 10 },
                create: {
                    created.withLock { value in
                        value += 1
                        return value
                    }
                },
                destroy: { _ in destroyed.withLock { $0 += 1 } }
            )

            let first = Task {
                try await pool.acquire { resource in
                    _ = firstBody.open()
                    await releaseFirst.wait()
                    resource = 10
                    return .reusable(resource)
                }
            }
            await firstBody.wait()

            pool.enqueue.withLock { $0 = { waiterEnqueued.open() } }
            let second = Task {
                try await pool.acquire { resource in .reusable(resource) }
            }
            await waiterEnqueued.wait()
            _ = releaseFirst.open()

            let firstValue = try await first.value
            let secondValue = try await second.value
            #expect(firstValue == 10)
            #expect(secondValue == 2)
            #expect(created.withLock { $0 } == 2)
            #expect(destroyed.withLock { $0 } == 1)

            await pool.shutdown()
        }

        @Test
        func `replacement creation failure fails queued acquisition`() async throws {
            let firstBody = Async.Gate()
            let releaseFirst = Async.Gate()
            let waiterEnqueued = Async.Gate()
            let created = Mutex(0)
            let pool = TestPool(
                capacity: 1,
                create: { () throws(Pool.Lifecycle.Error) -> Int in
                    try created.withLock { value throws(Pool.Lifecycle.Error) in
                        value += 1
                        guard value == 1 else { throw .creationFailed }
                        return value
                    }
                },
                destroy: { _ in }
            )

            let first = Task {
                try await pool.acquire { resource in
                    _ = firstBody.open()
                    await releaseFirst.wait()
                    return TestPool.Disposition.invalid(resource)
                }
            }
            await firstBody.wait()

            pool.enqueue.withLock { $0 = { waiterEnqueued.open() } }
            let second = Task {
                do throws(Either<Pool.Lifecycle.Error, Never>) {
                    let _: Int = try await pool.acquire {
                        TestPool.Disposition.reusable($0)
                    }
                    return Pool.Lifecycle.Error?.none
                } catch {
                    switch error {
                    case .left(let lifecycle):
                        return lifecycle
                    }
                }
            }
            await waiterEnqueued.wait()
            _ = releaseFirst.open()

            let firstValue = try await first.value
            let secondError = await second.value
            #expect(firstValue == 1)
            #expect(secondError == .creationFailed)
            await pool.shutdown()
        }

        @Test
        func `shutdown is an idempotent join that awaits every disposal`() async throws {
            let started = Async.Gate()
            let allow = Async.Gate()
            let firstCompleted = Async.Gate()
            let secondCompleted = Async.Gate()
            let destroyed = Mutex(0)
            let pool = TestPool(
                capacity: 2,
                destroy: { _ in
                    destroyed.withLock { $0 += 1 }
                    _ = started.open()
                    await allow.wait()
                }
            )
            try await pool.fill(1)
            try await pool.fill(2)

            let first = Task {
                await pool.shutdown()
                _ = firstCompleted.open()
            }
            await started.wait()
            let second = Task {
                await pool.shutdown()
                _ = secondCompleted.open()
            }

            #expect(!firstCompleted.isOpen)
            #expect(!secondCompleted.isOpen)
            _ = allow.open()
            await first.value
            await second.value

            #expect(firstCompleted.isOpen)
            #expect(secondCompleted.isOpen)
            #expect(destroyed.withLock { $0 } == 2)
            #expect(pool._state.withLock { $0.lifecycle } == .closed)
        }
    }
#endif
