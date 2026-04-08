# Audit: swift-pool-primitives

## Code Surface — 2026-04-08

### Scope

- **Target**: swift-pool-primitives
- **Skill**: code-surface — [API-NAME-001..004], [API-ERR-001..005], [API-IMPL-005..011]
- **Files**: 43 source files (14 in `Pool Primitives Core`, 28 in `Pool Bounded Primitives`, 1 umbrella export)

### Findings

None open. None deferred.

### Summary

**The `ownership-transfer-conventions` branch delivered a second-round
refactor that resolved every remaining finding from the 2026-04-07 audit
and brought the API to the canonical form.**

Previously the audit carried one DEFERRED finding for the factory closure
using untyped `() async throws -> Resource`. That is now resolved: the
closure types `throws(Pool.Lifecycle.Error)` directly, no existential
`any Error`, no untyped `throws`. The user wraps their domain errors at
the boundary as `.creationFailed`.

### Canonical API shape (post-refactor)

**One** `callAsFunction` on `Pool.Bounded.Acquire`:

```swift
nonisolated(nonsending)
public func callAsFunction<T: ~Copyable, E: Swift.Error>(
    _ body: nonisolated(nonsending) (inout sending Resource) async throws(E) -> sending T
) async throws(Either<Pool.Lifecycle.Error, E>) -> sending T
```

Sync closures promote via Swift's implicit sync→async conversion.
Non-throwing bodies infer `E = Never` — the `.right(Never)` case is
statically unreachable at catch sites.

**`Pool.Lifecycle.Error` has three cases**: `.shutdown`, `.cancelled`,
`.creationFailed`. `.timeout` and `.exhausted` are gone. Non-blocking
and timeout semantics compose externally via Task cancellation.

**Deleted types**: `Pool.Bounded.Acquire.Try`, `Pool.Bounded.Acquire.Try.Action`,
`Pool.Bounded.Acquire.Timeout`. Subsumed by composition.

**`Resource: ~Copyable` only** — the `& Sendable` constraint is dropped
from the type parameter throughout. Validated by a constraint-relaxation
proof test using a non-Sendable `~Copyable` `NonSendableHandle` struct.

**`Pool.Bounded` class is plain `Sendable`** (no `@unchecked`). Every
stored property is Sendable; conformance derives. The only localized
unsafe escape is `nonisolated(unsafe) var onEnqueue` — a DEBUG-only test
hook that test code sets after construction.

**`Either<Pool.Lifecycle.Error, E>`** from swift-algebra-primitives is
the function's typed throws clause. `.left` = pool failure, `.right` =
body failure. Per [IMPL-075], catches use
`do throws(Either<...>) { } catch { switch error { … } }` — never a
`catch let e as Type` cast.

**`Ownership.Shared` wraps dropped** for `Creator` and `Destructor`.
Closures are already reference-typed in Swift; `Ownership.Shared`
indirection was gratuitous. `Ownership.Slot<Resource>` remains for
`Entry` storage — that's the legitimate heap-allocated single-cell
atomic primitive the language doesn't provide.

**Internal Sendable conformances dropped** on action / discriminator
enums (`Acquire.Action`, `Acquire.Callback.Action`, `Fill.Action`,
`Fill.Commit`, `Effect`, `Effect.Gate`, `Effect.Waiter`, `Release.Action`,
`Shutdown.Drain`, `Slot`, `Slot.State`). These are locally computed
under `withLock` and returned via `sending T` — no Sendable conformance
required.

**Stored closures retain `@Sendable`** (`destroy`, `create`, `_check`,
DEBUG `onEnqueue`, Callback variant body/completion). Justified: stored
on a Sendable type and invoked from arbitrary Tasks across the actor
boundary; `@Sendable` ensures captures are safely shareable.

### Compliant areas

- All public types follow `Nest.Name` pattern.
- Slot indexing uses `Tagged<Self, Ordinal>` with typed subscripts —
  zero `.rawValue` calls in source.
- Typed throws coverage on all public API; no untyped `throws`, no
  `throws(any Error)`, no `Result<T, E>` in public return types.
- Error type naming: `Pool.Error`, `Pool.Lifecycle.Error`,
  `Pool.Bounded.Fill.Error` all properly nested per [API-ERR-002].
- No Foundation imports.
- Type bodies are minimal — only stored properties + canonical initializers.
- Import precision: public imports demoted to internal where they're not
  referenced from public declarations or inlinable code; zero unused
  public-import warnings in the package.

---

## Modularization — 2026-04-08

### Scope

- **Target**: swift-pool-primitives
- **Skill**: modularization — [MOD-001..015]
- **Files**: Package.swift, all `Sources/**/*.swift`, all `exports.swift`

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [MOD-001] | Package.swift:16-19 | `Pool Primitives Core` is published as a library product. Per [MOD-001], "Core is an internal target only — it MUST NOT be published as a library product." This pattern is widespread across the swift-primitives ecosystem; the rule and the practice are out of sync. | DEFERRED — ecosystem-wide pattern |
| 2 | LOW | [MOD-DOMAIN] | Package.swift (overall structure) | Pool has only one variant (`Pool Bounded Primitives`). With a single variant, the [MOD-015] "primary vs supplementary" distinguishing test is ambiguous. Classified as primary decomposition by the swift-primitives import precision audit (2026-04-03). | DEFERRED — pending second variant |

### Summary

2 findings, both deferred for ecosystem-wide reasons.

**New dependency added**: `swift-algebra-primitives` (for `Either<Left, Right>`,
re-exported from `Pool Primitives Core/exports.swift`).

**Compliance highlights**:
- [MOD-001] Core layer present; [MOD-002] external dependency centralization
  via Core re-exports; [MOD-005] umbrella with only `@_exported public import`
  statements; [MOD-006] dependency minimization respected; [MOD-007] graph
  depth = 2; [MOD-011] Test Support published; [MOD-012] naming follows
  convention; [MOD-013] semantic group markers present.
- Constraint isolation [MOD-004]: PASS. Pool Primitives Core carries no
  `Copyable`-imposing conformances.

---

## Legacy — Consolidated 2026-04-07

### From: swift-institute/Research/audits/implementation-naming-2026-03-20/swift-pool-primitives.md (2026-03-20)

| Original ID | Status |
|-------------|--------|
| POOL-001..009 | RESOLVED — compound type names eliminated |
| POOL-010..012 | RESOLVED — factory closure now `throws(Pool.Lifecycle.Error)`, no existential erasure |
| POOL-013 | RESOLVED — clarified that extensions are not type declarations |
| POOL-014 | RESOLVED — Pool.Bounded.Acquire.swift declares only the Acquire struct |
| POOL-015..018 | OUT OF SCOPE — implementation skill (`__unchecked`, `try!`); tracked separately |

### From: swift-institute/Research/async-pool-primitives-audit.md (2026-03-18, swift-pool-primitives portion)

| Original Finding | Status |
|------------------|--------|
| Finding 4 (Slot.Index `.rawValue` chains) | RESOLVED — `Tagged<Self, Ordinal>` with zero `.rawValue` calls |
| Finding 5 (State init conversion chain) | OUT OF SCOPE — implementation skill |
| Finding 6 (Raw counters in State) | OUT OF SCOPE — implementation skill |
| Finding 7 (Mixed Int/UInt64 in metrics) | OUT OF SCOPE — implementation skill. Note: `Pool.Metrics.timeouts` was renamed to `.cancellations` as part of the lifecycle-error collapse. |

The async-primitives portion of `async-pool-primitives-audit.md` remains
in place at the swift-institute scope until swift-async-primitives gets
its own per-package `Research/audit.md`.
