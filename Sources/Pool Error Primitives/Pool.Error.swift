extension Pool {

    public enum Error: Swift.Error, Sendable, Equatable {

        case capacity(Int)

        case exhausted

        case scope(Pool.Scope)

        case id(Pool.ID)
    }
}
