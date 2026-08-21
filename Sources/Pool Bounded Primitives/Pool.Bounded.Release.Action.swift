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

    extension Pool.Bounded.Release where Resource: ~Copyable {

        @usableFromInline
        enum Action: ~Copyable {

            case handOff(Async.Waiter.Resumption, skipped: [Async.Waiter.Resumption])

            case returnToPool(skipped: [Async.Waiter.Resumption])

            case dispose(skipped: [Async.Waiter.Resumption])
        }
    }
#endif
