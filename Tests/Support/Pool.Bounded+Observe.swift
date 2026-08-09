#if DEBUG && POOL_CONCURRENCY
    import Pool_Bounded_Primitives

    extension Pool.Bounded where Resource: ~Copyable {
        /// Observes each completed bounded-waiter enqueue.
        ///
        /// Test code can await this callback before asserting queue-dependent
        /// behavior without accessing the pool's implementation state.
        public func observe(enqueue observer: @escaping @Sendable () -> Void) {
            enqueue.withLock { $0 = observer }
        }
    }
#endif
