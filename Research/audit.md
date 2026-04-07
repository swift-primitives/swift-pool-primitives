# Audit: swift-pool-primitives

## Code Surface — 2026-04-07

### Scope

- **Target**: swift-pool-primitives
- **Skill**: code-surface — [API-NAME-001..004], [API-ERR-001..005], [API-IMPL-005..011]
- **Files**: 46 source files (14 in `Pool Primitives Core`, 31 in `Pool Bounded Primitives`, 1 umbrella export)

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [API-ERR-001] | Sources/Pool Bounded Primitives/Pool.Bounded.Creation.swift:17,24; Pool.Bounded.swift:111 | User-supplied factory closure uses untyped `() async throws -> Resource` at three sites: stored property (Creation.swift:17), `Creation.init` parameter (Creation.swift:24), and `Pool.Bounded.init` parameter (Pool.Bounded.swift:111). A DESIGN comment at Creation.swift:12-15 documents the rationale: the user's domain-specific error is intentionally erased to `Pool.Lifecycle.Error.creationFailed`. | DEFERRED — DESIGN documented |

### Summary

1 finding: 0 critical, 0 high, 0 medium open, 1 medium deferred.

**Resolved (formerly OPEN) on 2026-04-07**:
- [API-IMPL-005] / [API-IMPL-006] file structure: all 9 prior violations RESOLVED. `Pool.Bounded.Acquire` parent struct moved to `Pool.Bounded.Acquire.swift` (was misplaced in `Pool.Bounded.Acquire.Timeout.swift`). All nested discriminator enums extracted to dedicated files matching their nested name path: `Pool.Bounded.Acquire.Action`, `Pool.Bounded.Acquire.Try.Action`, `Pool.Bounded.Acquire.Callback.Action`, `Pool.Bounded.Effect.Gate`, `Pool.Bounded.Effect.Waiter`, `Pool.Bounded.Fill.Error`, `Pool.Bounded.Fill.Action`, `Pool.Bounded.Fill.Commit`, `Pool.Bounded.Shutdown.Drain`, `Pool.Bounded.Release` (namespace), `Pool.Bounded.Release.Action`, `Pool.Bounded.Waiter.Metadata`. The Pool.Bounded extension methods that were entangled with the type declarations (callAsFunction overloads, acquireSlot, createLazyResource, suspendForSlot, releaseSlot, pumpWaiters, etc.) were moved to `Pool.Bounded+Acquire.swift` and `Pool.Bounded+Release.swift` per the `+` extension file convention. State helpers (findEmptySlot, dequeueEligibleWaiter) were hoisted into `Pool.Bounded.State.swift`.
- Compound public property names: `Pool.Metrics.peakCheckedOut` and `Pool.Metrics.checkedOut` consolidated under nested `Pool.Metrics.Outstanding { current, peak }` struct (new file `Pool.Metrics.Outstanding.swift`). `Pool.Bounded.onWaiterEnqueued` renamed to `Pool.Bounded.onEnqueue`.

**Compliant areas** (no findings):
- All public types follow `Nest.Name` pattern. The legacy compound names (`TryAcquire`, `CallbackAcquire`, `TimeoutAcquire`, `AcquireAction`, `ReleaseAction`, `CommitAction`, `DrainAction`) flagged by the 2026-03-20 audit have all been resolved.
- Slot indexing uses `Tagged<Self, Ordinal>` with typed subscripts (zero `.rawValue` calls in source).
- Typed throws coverage on all functions in scope, with the documented exception in Finding 1.
- Error type naming: `Pool.Error`, `Pool.Lifecycle.Error`, `Pool.Bounded.Fill.Error` all properly nested per [API-ERR-002].
- No Foundation imports.
- Type bodies are minimal — only stored properties + canonical initializers.

---

## Modularization — 2026-04-07

### Scope

- **Target**: swift-pool-primitives
- **Skill**: modularization — [MOD-001..015]
- **Files**: Package.swift, all `Sources/**/*.swift`, all `exports.swift`

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [MOD-001] | Package.swift:16-19 | `Pool Primitives Core` is published as a library product. Per [MOD-001], "Core is an internal target only — it MUST NOT be published as a library product." This pattern is widespread across the swift-primitives ecosystem; the rule and the practice are out of sync. | DEFERRED — ecosystem-wide pattern |
| 2 | LOW | [MOD-DOMAIN] | Package.swift (overall structure) | Pool has only one variant (`Pool Bounded Primitives`). With a single variant, the [MOD-015] "primary vs supplementary" distinguishing test is ambiguous. The classification as primary decomposition was made by the swift-primitives import precision audit (2026-04-03). | DEFERRED — pending second variant |

### Summary

2 findings: 0 critical, 0 high, 0 medium open, 1 medium deferred, 1 low deferred.

**Compliance highlights**:
- [MOD-001] Core layer present; [MOD-002] external dependency centralization via Core re-exports; [MOD-005] umbrella with only `@_exported public import` statements; [MOD-006] dependency minimization respected; [MOD-007] graph depth = 2; [MOD-011] Test Support published; [MOD-012] naming follows convention; [MOD-013] semantic group markers present.
- Constraint isolation [MOD-004]: PASS. Pool Primitives Core carries no `Copyable`-imposing conformances.

---

## Legacy — Consolidated 2026-04-07

### From: swift-institute/Research/audits/implementation-naming-2026-03-20/swift-pool-primitives.md (2026-03-20)

| Original ID | Status |
|-------------|--------|
| POOL-001..009 | RESOLVED — compound type names eliminated |
| POOL-010..012 | DEFERRED — see Code Surface Finding 1 (DESIGN documented) |
| POOL-013 | RESOLVED — clarified that extensions are not type declarations |
| POOL-014 | RESOLVED — Pool.Bounded.Acquire.swift now declares only the Acquire struct |
| POOL-015..018 | OUT OF SCOPE — implementation skill (`__unchecked`, `try!`); not audited here |

### From: swift-institute/Research/async-pool-primitives-audit.md (2026-03-18, swift-pool-primitives portion)

| Original Finding | Status |
|------------------|--------|
| Finding 4 (Slot.Index `.rawValue` chains) | RESOLVED — `Tagged<Self, Ordinal>` with zero `.rawValue` calls |
| Finding 5 (State init conversion chain) | OUT OF SCOPE — implementation skill |
| Finding 6 (Raw counters in State) | OUT OF SCOPE — implementation skill |
| Finding 7 (Mixed Int/UInt64 in metrics) | OUT OF SCOPE — implementation skill |

The async-primitives portion of `async-pool-primitives-audit.md` remains in place at the swift-institute scope until swift-async-primitives gets its own per-package `Research/audit.md`.
