#if POOL_CONCURRENCY

    public import Array_Primitive
    public import Async_Waiter_Primitives
    internal import Buffer_Linear_Bounded_Primitive
    internal import Buffer_Linear_Primitive
    internal import Buffer_Primitive
    internal import Column_Primitives
    internal import Fixed_Primitives
    internal import Memory_Allocator_Primitive
    internal import Memory_Heap_Primitives
    internal import Ownership_Shared_Primitive
    internal import Storage_Contiguous_Primitives

    extension Pool.Bounded.Fill where Resource: ~Copyable {

        @usableFromInline

        enum Commit: ~Copyable {

            case addToPool(
                effect: Pool.Bounded<Resource>.Effect,
                skipped: [Async.Waiter.Resumption]
            )

            case handOff(Async.Waiter.Resumption, skipped: [Async.Waiter.Resumption])

            case dispose
        }
    }
#endif
