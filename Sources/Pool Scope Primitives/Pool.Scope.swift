internal import Async_Primitives
public import Dimension_Primitives

#if !hasFeature(Embedded)
    import Synchronization
    /// Global counter for scope generation (non-embedded).
    private let _scopeCounter = Atomic<UInt64>(0)
#else
    /// Global counter for scope generation (embedded).
    ///
    /// Uses mutex-protected counter since Atomic isn't available.
    private let _scopeCounterMutex = Async.Mutex<UInt64>(0)
#endif

extension Pool {
    /// Unique scope identifier for a pool instance.
    ///
    /// Used to validate that IDs belong to the correct pool.
    public struct Scope: Sendable, Hashable {
        /// The raw scope value.
        public typealias RawValue = Tagged<Self, UInt64>

        @usableFromInline
        let value: RawValue

        /// Creates a new unique scope.
        @_spi(Internal)
        public init() {
            #if !hasFeature(Embedded)
                self.value = RawValue(_unchecked: _scopeCounter.wrappingAdd(1, ordering: .relaxed).oldValue)
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
