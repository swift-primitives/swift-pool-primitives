#if POOL_CONCURRENCY
    extension Pool.Bounded.Slot where Resource: ~Copyable {
        /// Slot state machine.
        ///
        /// ## States
        /// - `empty`: No resource, lazy creation possible
        /// - `creating(id)`: Lazy creation in progress (reserved)
        /// - `available(id)`: Resource in Entry, ready for checkout
        /// - `out(id)`: Resource checked out
        /// - `disposing(id)`: Shutdown disposal in progress (reserved)
        ///
        /// ## Transitions
        /// - `empty → creating(id)`: lazy reservation under lock
        /// - `creating(id) → available(id)`: creation succeeded
        /// - `creating(id) → empty`: creation failed
        /// - `empty → available(id)`: eager fill
        /// - `available(id) → out(id)`: checkout under lock
        /// - `out(id) → available(id)`: return under lock (if open)
        /// - `out(id) → disposing(id)`: return during shutdown
        /// - `available(id) → disposing(id)`: shutdown drain
        /// - `disposing(id) → empty`: disposal complete
        @usableFromInline
        enum State {
            /// Slot has no resource (lazy creation possible).
            case empty

            /// Lazy: resource being created (reserved).
            case creating(Pool.ID)

            /// Resource in Entry, ready for checkout.
            case available(Pool.ID)

            /// Resource checked out.
            case out(Pool.ID)

            /// Shutdown: resource being disposed (reserved).
            case disposing(Pool.ID)
        }
    }
#endif
