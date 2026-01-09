extension Pool {
    /// Runtime statistics for pool monitoring.
    public struct Metrics: Sendable {
        /// Total resources created (lazy policy).
        public var created: UInt64

        /// Total resources filled (eager policy).
        public var fills: UInt64

        /// Total resources closed.
        public var closed: UInt64

        /// Total acquisitions.
        public var acquisitions: UInt64

        /// Total releases.
        public var releases: UInt64

        /// Total timeouts.
        public var timeouts: UInt64

        /// Current checked-out count.
        public var checkedOut: Int

        /// Current available count.
        public var available: Int

        /// Current waiter queue depth.
        public var waiters: Int

        /// Peak checked-out count.
        public var peakCheckedOut: Int

        /// Creates empty metrics.
        @usableFromInline
        init() {
            self.created = 0
            self.fills = 0
            self.closed = 0
            self.acquisitions = 0
            self.releases = 0
            self.timeouts = 0
            self.checkedOut = 0
            self.available = 0
            self.waiters = 0
            self.peakCheckedOut = 0
        }
    }
}
