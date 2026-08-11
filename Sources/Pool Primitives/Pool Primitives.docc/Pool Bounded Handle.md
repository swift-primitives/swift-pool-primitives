# Checked-out bounded resources

`Pool.Bounded` is the canonical owner of generic bounded resource admission,
exclusive checkout, terminal release, cancellation, metrics, and shutdown drain.

Use ``Pool/Bounded/checkout`` when an operation must retain unique ownership
beyond one acquisition call. Checkout returns a `sending`, move-only
``Pool/Bounded/Handle``. Transfer that handle into one task or actor region;
the handle deliberately does not conform to `Sendable` and must never be shared
for concurrent reuse.

Borrow or mutate ``Pool/Bounded/Handle/resource`` only while the handle remains
alive. Finish by consuming the handle with
``Pool/Bounded/Handle/resolve(_:)``. A reusable resolution validates and returns
the resource while the pool is open. Invalid resolution and concurrent shutdown
await orderly destruction. Resolution always returns its possibly move-only
operation value; a shutdown race cannot erase a value that the operation has
already produced.

Dropping a live handle is safe but terminal. Its storage synchronously marks the
slot as disposing, invokes the pool's nonthrowing `drop` fallback outside the
state lock, and completes the slot as empty. It never returns an abandoned
resource as reusable, starts a task, or detaches asynchronous cleanup. Resource
types that need immediate cancellation should provide that behavior through the
initializer's `drop` callback; `destroy` remains the awaited orderly path.

The bounded pool is an ordinary package surface. It is not protected by a
package trait or SPI. Higher-layer forwarding facades own no separate resource
pool law; consumers migrate directly to `Pool Bounded Primitives` or the
`Pool Primitives` umbrella. A facade may be removed only after exact consumer
migration and build evidence establish that it is dead at build level.

> Important: This source-complete design has not yet been built or tested under
> the programme's source-only moratorium and remains **UNVERIFIED**.
