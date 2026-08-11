extension Pool.Bounded.Handle where Resource: ~Copyable {
    /// A checked-out resource's explicit terminal disposition and result.
    public enum Resolution<Value: ~Copyable>: ~Copyable {
        /// Validates and returns the resource to reusable storage when the pool
        /// remains open; concurrent shutdown destroys it instead.
        case reusable(Value)

        /// Destroys the resource before returning the result.
        case invalid(Value)
    }
}
