# Pool Primitives Scope

`swift-pool-primitives` provides the substrate for **bounded, lifecycle-managed
pools of reusable resources**: acquisition and release of a fixed set of
resources under a capacity limit, with FIFO waiter queuing, an
open → draining → shutdown lifecycle, and a runtime metrics snapshot. The package
owns the `Pool` namespace and the vocabulary that defines a pool's identity,
configuration, errors, lifecycle, and metrics, plus the concrete `Pool.Bounded`
implementation.

## Per-[MOD-031] shape

The package follows `[MOD-031]` per-sub-namespace decomposition: `Pool Primitive`
is the zero-external-dependency namespace root per `[MOD-017]`, and each
sub-namespace is its own target. There is no `Pool Primitives Core` target — the
legacy `[MOD-001]` Core convention was retired from this package during its
publication-readiness reshape.

The identity/configuration vocabulary is grouped into two targets rather than one
per sub-namespace: `Pool.Scope` + `Pool.ID` (`Pool Scope Primitives`) and
`Pool.Error` + `Pool.Capacity` (`Pool Error Primitives`). This is the
maximal-granularity decomposition that stays within `[MOD-007]`'s depth-≤3 guide:
the reference chain `Scope → ID → Error → Capacity` plus `Pool.Bounded`'s
dependency on it would otherwise reach edge-depth 4–5. Each pair co-locates
mutually-referential types — `Pool.ID` embeds a `Pool.Scope`; `Pool.Capacity`
validation throws `Pool.Error`.

## Owner targets

- **Pool Primitive** — the root `public enum Pool {}` namespace. Zero external
  deps per `[MOD-017]`'s invariant.
- **Pool Scope Primitives** — `Pool.Scope` (pool-instance identity) and `Pool.ID`
  (checked-out-resource identity).
- **Pool Error Primitives** — `Pool.Error` (operational errors) and `Pool.Capacity`
  (capacity configuration).
- **Pool Lifecycle Primitives** — `Pool.Lifecycle` state, error, and precedence: the
  open → draining → shutdown state machine.
- **Pool Metrics Primitives** — `Pool.Metrics` and `Pool.Metrics.Outstanding`: the
  runtime monitoring snapshot.
- **Pool Acquire Primitives** — `Pool.Acquire`: the acquisition effect (`Effect.Protocol`).
- **Pool Release Primitives** — `Pool.Release`: the release effect (`Effect.Protocol`).
- **Pool Bounded Primitives** — `Pool.Bounded`: the fixed-capacity pool implementation
  (slot state machine, waiter queue, fill/drain, shutdown). Kept as one target because
  its internals share private storage and are mutually `~Copyable`-coupled
  (`[MOD-026]` bundling exception).
- **Pool Primitives** — umbrella; re-exports all sub-namespace targets so consumers
  needing the union write `import Pool_Primitives`.
- **Pool Primitives Test Support** — published test-fixtures product.

## Out of scope

- **Resource construction / connection logic** — the pool stores and hands out
  resources; how a resource is *created* is the consumer's `create:` closure. Lives in
  consumer code.
- **Timeout / non-blocking acquisition semantics** — `Pool.Bounded` waits indefinitely
  until a slot is available or the calling `Task` is cancelled; timeout and "try"
  semantics are composed externally via `Task` cancellation (the pool surfaces both as
  `.cancelled`). Lives in consumer code.
- **Allocation strategy and storage layout** — slot storage, contiguous buffers, and
  allocators are consumed from `swift-buffer-linear-primitives`,
  `swift-storage-primitives`, `swift-buffer-primitives`, and `swift-memory-*`.
  Consumed, not owned.
- **Synchronization and async coordination** — mutex, waiter queue, and promise
  substrate are consumed from `swift-async-primitives`. Consumed, not owned.
- **Alternative pool strategies** (unbounded / elastic / sharded) — a new strategy is a
  new sibling *variant* target alongside `Pool.Bounded` (e.g. `Pool Unbounded Primitives`),
  never a widening of `Pool.Bounded` or of the shared vocabulary targets.

## Evaluation rule

Sub-target additions are evaluated against this scope. If a proposed addition is OUT of
scope, it extracts to a sibling package, not into this one. A new pool *strategy* that is
in scope becomes its own variant target (mirroring `Pool.Bounded`), never an expansion of
an existing target's identity surface.
