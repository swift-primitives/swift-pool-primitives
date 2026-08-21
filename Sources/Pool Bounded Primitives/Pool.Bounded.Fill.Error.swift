#if POOL_CONCURRENCY

    extension Pool.Bounded.Fill where Resource: ~Copyable {

        public enum Error: Swift.Error, Sendable, Equatable {

            case notEager

            case shutdown

            case full

            case invalid
        }
    }
#endif
