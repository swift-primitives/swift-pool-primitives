internal import Async_Primitives
public import Dimension_Primitives

#if !hasFeature(Embedded)
    import Synchronization

    private let _scopeCounter = Atomic<UInt64>(0)
#else

    private let _scopeCounterMutex = Async.Mutex<UInt64>(0)
#endif

extension Pool {

    public struct Scope: Sendable, Hashable {
        @usableFromInline
        let value: RawValue

        @_spi(Internal)
        public init() {
            #if !hasFeature(Embedded)
                let previous = _scopeCounter.wrappingAdd(1, ordering: .relaxed).oldValue
                self.value = RawValue(_unchecked: previous)
            #else
                self.value = RawValue(
                    _unchecked: _scopeCounterMutex.withLock { counter in
                        let oldValue = counter
                        counter &+= 1
                        return oldValue
                    }
                )
            #endif
        }
    }
}

extension Pool.Scope {

    public typealias RawValue = Tagged<Self, UInt64>
}
