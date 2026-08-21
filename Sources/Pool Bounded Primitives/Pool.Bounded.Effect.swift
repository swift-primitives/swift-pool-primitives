#if POOL_CONCURRENCY

    internal import Array_Primitive
    internal import Async_Mutex_Primitives
    internal import Async_Primitives
    internal import Async_Waiter_Primitives

    extension Pool.Bounded where Resource: ~Copyable {

        @usableFromInline
        enum Effect: ~Copyable {

            case none

            case gate(Gate)

            case waiter(Waiter)
        }
    }
#endif
