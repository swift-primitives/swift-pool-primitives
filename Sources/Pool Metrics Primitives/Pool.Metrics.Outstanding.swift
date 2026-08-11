extension Pool.Metrics {
    /// Counts for outstanding (currently checked-out) resources.
    public struct Outstanding: Sendable {
        /// Current outstanding resource count.
        public var current: Int

        /// Peak outstanding resource count observed since pool creation.
        public var peak: Int

        /// Creates an empty outstanding counter.
        package init() {
            self.current = 0
            self.peak = 0
        }
    }
}
