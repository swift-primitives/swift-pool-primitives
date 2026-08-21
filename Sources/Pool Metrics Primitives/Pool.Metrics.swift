extension Pool {

    public struct Metrics: Sendable {

        public var created: UInt64

        public var fills: UInt64

        public var closed: UInt64

        public var acquisitions: UInt64

        public var releases: UInt64

        public var cancellations: UInt64

        public var outstanding: Outstanding

        public var available: Int

        public var waiters: Int

        @_spi(Internal)
        public init() {
            self.created = 0
            self.fills = 0
            self.closed = 0
            self.acquisitions = 0
            self.releases = 0
            self.cancellations = 0
            self.outstanding = Outstanding()
            self.available = 0
            self.waiters = 0
        }
    }
}
