extension Pool.Lifecycle {

    public enum Error: Swift.Error, Sendable, Equatable {

        case shutdown

        case cancelled

        case creationFailed
    }
}
