# ``Pool_Primitives``

@Metadata {
    @DisplayName("Pool Primitives")
    @TitleHeading("Swift Primitives")
}

`Pool.Bounded<Resource>` — a bounded async resource pool: `acquire` borrows a `~Copyable`
resource for the duration of a closure and returns it afterward, suspending callers with
backpressure when the pool is exhausted; a `destroy` hook reclaims resources at shutdown.

## Topics
