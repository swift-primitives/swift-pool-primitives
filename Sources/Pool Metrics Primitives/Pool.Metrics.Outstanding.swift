extension Pool.Metrics {

    public struct Outstanding: Sendable {

        public var current: Int

        public var peak: Int

        @_spi(Internal)
        public init() {
            self.current = 0
            self.peak = 0
        }
    }
}
