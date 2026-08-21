#if POOL_CONCURRENCY

    public import Either_Primitives
    internal import Fixed_Primitives
    internal import Ownership_Primitives
    internal import Tagged_Collection_Primitives

    extension Pool.Bounded where Resource: ~Copyable {

        public var acquire: Acquire {
            Acquire(pool: self)
        }
    }

    extension Pool.Bounded where Resource: ~Copyable {

        public struct Acquire: Sendable {
            @usableFromInline
            let pool: Pool.Bounded<Resource>

            @usableFromInline
            init(pool: Pool.Bounded<Resource>) {
                self.pool = pool
            }
        }
    }

    extension Pool.Bounded.Acquire where Resource: ~Copyable {

        nonisolated(nonsending) public func callAsFunction<T: ~Copyable, E: Swift.Error>(
            _ body:
                nonisolated(nonsending) (inout sending Resource) async throws(E)
                -> sending Pool.Bounded<Resource>.Disposition<T>
        ) async throws(Either<Pool.Lifecycle.Error, E>) -> sending T {
            while true {
                let slot: (Pool.Bounded<Resource>.Slot.Index, Pool.ID)
                do throws(Pool.Lifecycle.Error) {
                    slot = try await pool.acquireSlot()
                } catch {
                    throw .left(error)
                }
                let (slotIndex, id) = slot
                var resource = pool.entries.underlying[
                    slotIndex.retag(Pool.Bounded<Resource>.Entry.self)
                ].move.out

                if let check = pool._check, !check(&resource) {
                    if let error = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .invalid
                    ) {
                        throw .left(error)
                    }
                    continue
                }

                let admissionError: Pool.Lifecycle.Error? = pool._state.withLock { state in
                    if state.lifecycle.shutdown.isActive { return .shutdown }
                    if Task.isCancelled { return .cancelled }
                    return nil
                }
                if let admissionError {
                    _ = await pool.release(resource, from: slotIndex, id: id, as: .invalid)
                    throw .left(admissionError)
                }

                let disposition: Pool.Bounded<Resource>.Disposition<T>
                do throws(E) {
                    disposition = try await body(&resource)
                } catch {
                    let releaseError = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .invalid
                    )
                    if let releaseError {
                        throw .left(releaseError)
                    }
                    if Task.isCancelled {
                        throw .left(.cancelled)
                    }
                    throw .right(error)
                }

                if Task.isCancelled {
                    let releaseError = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .invalid
                    )
                    throw .left(releaseError ?? .cancelled)
                }

                switch consume disposition {
                case .reusable(let value):
                    if let error = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .reusable
                    ) {
                        throw .left(error)
                    }
                    return value

                case .invalid(let value):
                    if let error = await pool.release(
                        resource,
                        from: slotIndex,
                        id: id,
                        as: .invalid
                    ) {
                        throw .left(error)
                    }
                    return value
                }
            }
        }
    }
#endif
