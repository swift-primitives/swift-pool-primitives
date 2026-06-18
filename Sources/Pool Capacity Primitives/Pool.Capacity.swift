extension Pool {
    /// Pool capacity configuration.
    public struct Capacity: Sendable, Hashable {
        /// The capacity value.
        @_spi(Internal)
        public let value: Int

        /// Creates a capacity.
        ///
        /// - Parameter value: The capacity value (must be > 0).
        /// - Throws: `Pool.Error.capacity` if value <= 0.
        public init(_ value: Int) throws(Pool.Error) {
            guard value > 0 else { throw .capacity(value) }
            self.value = value
        }

        /// Creates a capacity without validation (internal use).
        init(unchecked value: Int) {
            self.value = value
        }
    }
}

extension Pool.Capacity: ExpressibleByIntegerLiteral {
    /// Creates a capacity from an integer literal.
    ///
    /// Integer literals are compile-time constants, so trapping on invalid
    /// values is acceptable here.
    public init(integerLiteral value: Int) {
        precondition(value > 0, "Capacity literal must be > 0")
        self.value = value
    }
}
