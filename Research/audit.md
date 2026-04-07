# Audit: swift-pool-primitives

## Code Surface — 2026-04-07

### Scope

- **Target**: swift-pool-primitives
- **Skill**: code-surface — [API-NAME-001..004], [API-ERR-001..005], [API-IMPL-005..011]
- **Files**: 33 source files (13 in `Pool Primitives Core`, 19 in `Pool Bounded Primitives`, 1 umbrella export)

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | HIGH | [API-IMPL-006] | Sources/Pool Bounded Primitives/Pool.Bounded.Acquire.Timeout.swift:47 | Parent type `Pool.Bounded.Acquire` (struct) is declared in a child-named file. The `Acquire` type belongs in `Pool.Bounded.Acquire.swift`, not in the file named for its `Timeout` child. File naming MUST match the type's full nested path. | OPEN |
| 2 | HIGH | [API-IMPL-005] | Sources/Pool Bounded Primitives/Pool.Bounded.Acquire.swift:121,308,317 | File contains 3 type declarations: `Pool.Bounded.Acquire.Action` enum (line 121), `Pool.Bounded.Release` namespace enum (line 308), `Pool.Bounded.Release.Action` enum (line 317). The `Release` namespace is also semantically misplaced inside the `Acquire` file. Split into `Pool.Bounded.Acquire.Action.swift`, `Pool.Bounded.Release.swift`, `Pool.Bounded.Release.Action.swift`. | OPEN |
| 3 | HIGH | [API-IMPL-005] | Sources/Pool Bounded Primitives/Pool.Bounded.Acquire.Timeout.swift:47,95 | File contains 2 type declarations: `Pool.Bounded.Acquire` struct (line 47) and `Pool.Bounded.Acquire.Timeout` struct (line 95). After resolving Finding 1, the `Timeout` struct should be the only declaration here. | OPEN |
| 4 | HIGH | [API-IMPL-005] | Sources/Pool Bounded Primitives/Pool.Bounded.Effect.swift:34,51,67 | File contains 3 type declarations: `Pool.Bounded.Effect` enum (line 34), `Pool.Bounded.Effect.Gate` enum (line 51), `Pool.Bounded.Effect.Waiter` enum (line 67). Split into `Pool.Bounded.Effect.swift`, `Pool.Bounded.Effect.Gate.swift`, `Pool.Bounded.Effect.Waiter.swift`. | OPEN |
| 5 | HIGH | [API-IMPL-005] | Sources/Pool Bounded Primitives/Pool.Bounded.Fill.swift:37,52,69,92 | File contains 4 type declarations: `Pool.Bounded.Fill` struct (line 37), `Pool.Bounded.Fill.Error` enum (line 52), `Pool.Bounded.Fill.Action` enum (line 69), `Pool.Bounded.Fill.Commit` enum (line 92). Split each child into its own file. | OPEN |
| 6 | MEDIUM | [API-IMPL-005] | Sources/Pool Bounded Primitives/Pool.Bounded.Acquire.Try.swift:31,63 | File contains 2 type declarations: `Pool.Bounded.Acquire.Try` struct (line 31) and `Pool.Bounded.Acquire.Try.Action` enum (line 63). Split `Action` into `Pool.Bounded.Acquire.Try.Action.swift`. | OPEN |
| 7 | MEDIUM | [API-IMPL-005] | Sources/Pool Bounded Primitives/Pool.Bounded.Acquire.Callback.swift:34,72 | File contains 2 type declarations: `Pool.Bounded.Acquire.Callback` struct (line 34) and `Pool.Bounded.Acquire.Callback.Action` enum (line 72). Split `Action` into its own file. | OPEN |
| 8 | MEDIUM | [API-IMPL-005] | Sources/Pool Bounded Primitives/Pool.Bounded.Shutdown.swift:38,57 | File contains 2 type declarations: `Pool.Bounded.Shutdown` struct (line 38) and `Pool.Bounded.Shutdown.Drain` enum (line 57). Split `Drain` into its own file. | OPEN |
| 9 | MEDIUM | [API-IMPL-005] | Sources/Pool Bounded Primitives/Pool.Bounded.Waiter.swift:15,24 | File contains 2 type declarations: `Pool.Bounded.Waiter` namespace enum (line 15) and `Pool.Bounded.Waiter.Metadata` struct (line 24). Split `Metadata` into its own file. (Typealiases `Outcome`, `Entry`, `Flagged` do not count per [API-IMPL-005] clarification.) | OPEN |
| 10 | MEDIUM | [API-ERR-001] | Sources/Pool Bounded Primitives/Pool.Bounded.Creation.swift:17,24; Pool.Bounded.swift:111 | User-supplied factory closure uses untyped `() async throws -> Resource` at three sites: stored property (Creation.swift:17), `Creation.init` parameter (Creation.swift:24), and `Pool.Bounded.init` parameter (Pool.Bounded.swift:111). A DESIGN comment at Creation.swift:12-15 documents the rationale: the user's domain-specific error is intentionally erased to `Pool.Lifecycle.Error.creationFailed`. The pool catches every error and never inspects the type, so making the closure generic over `E` would force callers to wrap their errors without benefit. | DEFERRED — DESIGN documented |

### Summary

10 findings: 0 critical, 5 high, 4 medium, 1 deferred (0 low).

**Systemic pattern**: All 9 [API-IMPL-005] / [API-IMPL-006] violations cluster in the `Pool Bounded Primitives` target. The `Pool Primitives Core` target is fully compliant (13/13 single-type files). The pattern is co-locating "discriminator" enums (`Action`, `Effect.*`, `Commit`, `Drain`) with their parent operation types. The remediation is mechanical: each discriminator gets its own file matching its full nested path. The most consequential violation is Finding 1 — the `Pool.Bounded.Acquire` parent type is declared in `Pool.Bounded.Acquire.Timeout.swift` while `Pool.Bounded.Acquire.swift` declares unrelated `Release` types. Fixing this should be done first, after which Findings 2 and 3 fall out naturally.

**Compliant areas** (no findings):
- `Pool Primitives Core` target: all 13 source files single-type compliant; namespace structure (`Pool`, `Pool.Acquire`, `Pool.Capacity`, `Pool.Error`, `Pool.ID`, `Pool.Lifecycle.{Error,State,Precedence}`, `Pool.Metrics`, `Pool.Release`, `Pool.Scope`) is exemplary.
- All public types follow `Nest.Name` pattern; the legacy compound names (`TryAcquire`, `CallbackAcquire`, `TimeoutAcquire`, `AcquireAction`, `ReleaseAction`, `CommitAction`, `DrainAction`) flagged by the 2026-03-20 audit have all been resolved.
- Slot indexing has been migrated from `Tagged<Self, Int>` with `.rawValue` chains (30+ legacy sites) to `Tagged<Self, Ordinal>` with typed subscripts (zero `.rawValue` calls in source).
- Typed throws coverage on all functions in scope, with the documented exception in Finding 10.
- Error type naming: `Pool.Error`, `Pool.Lifecycle.Error`, `Pool.Bounded.Fill.Error` all properly nested per [API-ERR-002].
- No Foundation imports.

---

## Modularization — 2026-04-07

### Scope

- **Target**: swift-pool-primitives
- **Skill**: modularization — [MOD-001..015]
- **Files**: Package.swift, all `Sources/**/*.swift`, all `exports.swift`

### Findings

| # | Severity | Rule | Location | Finding | Status |
|---|----------|------|----------|---------|--------|
| 1 | MEDIUM | [MOD-001] | Package.swift:16-19 | `Pool Primitives Core` is published as a library product. Per [MOD-001], "Core is an internal target only — it MUST NOT be published as a library product." Note: this pattern is widespread across the swift-primitives ecosystem (e.g., swift-buffer-primitives publishes `Buffer Primitives Core` and per-variant `Core` products); the ecosystem-wide modularization audit (`swift-primitives/Research/audit.md`, 2026-04-03) does not flag it. The rule and the practice are out of sync. | DEFERRED — ecosystem-wide pattern, requires norm-vs-rule reconciliation |
| 2 | LOW | [MOD-DOMAIN] | Package.swift (overall structure) | Pool has only one variant (`Pool Bounded Primitives`). With a single variant, the [MOD-015] "primary vs supplementary" distinguishing test is ambiguous. The swift-primitives import precision audit (2026-04-03) classified pool as **primary decomposition**, but the package is at the boundary: a future second variant (e.g., `Pool Unbounded Primitives` or `Pool Channel Primitives`) would confirm the classification. Currently the umbrella saves no compile cost over importing `Pool Bounded Primitives` directly. | DEFERRED — pending second variant or explicit reclassification |

### Summary

2 findings: 0 critical, 0 high, 0 medium open, 1 medium deferred, 1 low deferred.

**Compliance highlights**:
- [MOD-001] Core layer: present (`Pool Primitives Core`), depends on Async Core / Dimension / Effect / Ownership; every other target depends on it transitively.
- [MOD-002] External dependency centralization: variants reach external types via Core's `exports.swift`. The `Pool Bounded Primitives` target's direct dependencies on Stack/Array/Async-Waiter/Mutex/Promise variants are justified — it needs concrete Stack and Array types for storage and Waiter/Mutex/Promise for synchronization, and these are not pulled in transitively through Async Core.
- [MOD-005] Umbrella: `Pool Primitives` target depends on Core + Bounded; `exports.swift` contains only `@_exported public import` statements.
- [MOD-006] Dependency minimization: each target declares only what it imports. `Pool Bounded Primitives` has 7 sibling/external dependencies, all justified by direct usage in the source.
- [MOD-007] Dependency graph shape: depth = 2 (Core → Bounded → Umbrella). Within ecosystem benchmarks.
- [MOD-011] Test Support: published as a library product (`Pool Primitives Test Support`), depends on the umbrella + `Index Primitives Test Support`.
- [MOD-012] Naming: all targets follow `{Domain} [Variant] Primitives [Core|Test Support]` convention.
- [MOD-013] Semantic group markers: Package.swift uses `// MARK: - Core`, `// MARK: - Variants`, `// MARK: - Umbrella`, `// MARK: - Tests`.

**Constraint isolation [MOD-004]**: PASS. `Pool Primitives Core` carries no `Copyable`-imposing conformances. `Pool.Acquire`/`Pool.Release` (Effect.Protocol conformers) operate on `Resource: ~Copyable & Sendable`. The `Pool Bounded Primitives` variant adds the storage variant of the type but does not re-impose `Copyable` on the Core types.

---

## Legacy — Consolidated 2026-04-07

### From: swift-institute/Research/audits/implementation-naming-2026-03-20/swift-pool-primitives.md (2026-03-20)

The 2026-03-20 implementation-naming audit identified 18 findings against [API-NAME-001], [API-ERR-001], [API-IMPL-005], and [IMPL-INTENT]. Status as of 2026-04-07:

| Original ID | Description | Current Status |
|-------------|-------------|----------------|
| POOL-001 | `TryAcquire` compound type name | RESOLVED — now `Pool.Bounded.Acquire.Try` |
| POOL-002 | `CallbackAcquire` compound type name | RESOLVED — now `Pool.Bounded.Acquire.Callback` |
| POOL-003 | `TimeoutAcquire` compound type name | RESOLVED — now `Pool.Bounded.Acquire.Timeout` |
| POOL-004 | `AcquireAction` compound enum name | RESOLVED — now `Pool.Bounded.Acquire.Action` |
| POOL-005 | `ReleaseAction` compound enum name | RESOLVED — now `Pool.Bounded.Release.Action` |
| POOL-006 | `TryAcquireAction` compound enum name | RESOLVED — now `Pool.Bounded.Acquire.Try.Action` |
| POOL-007 | `CallbackAcquireAction` compound enum name | RESOLVED — now `Pool.Bounded.Acquire.Callback.Action` |
| POOL-008 | `CommitAction` compound enum name | RESOLVED — now `Pool.Bounded.Fill.Commit` |
| POOL-009 | `DrainAction` compound enum name | RESOLVED — now `Pool.Bounded.Shutdown.Drain` |
| POOL-010 | Untyped throws on `Creation.create` stored property | SUPERSEDED by Code Surface Finding 10 (now DEFERRED with documented DESIGN rationale) |
| POOL-011 | Untyped throws on `Creation.init` parameter | SUPERSEDED by Code Surface Finding 10 |
| POOL-012 | Untyped throws on `Pool.Bounded.init` parameter | SUPERSEDED by Code Surface Finding 10 |
| POOL-013 | Multiple sections in `Pool.Bounded.swift` (extensions only) | RESOLVED — clarified to be acceptable per [API-IMPL-005]; extensions on the same type are not type declarations |
| POOL-014 | Multiple type declarations in `Pool.Bounded.Acquire.swift` | SUPERSEDED by Code Surface Finding 2 (still present, with different child types after rename) |
| POOL-015 | `__unchecked` constructor at `Pool.Bounded.State.swift:65-67` | STILL PRESENT — `Pool.Bounded.State.swift:69-71` uses `Stack<Slot.Index>.Index.Count(__unchecked: (), Cardinal(UInt(capacity)))`. Out of code-surface scope; tracked under implementation skill (not audited here). |
| POOL-016 | `try!` on `Slot.Index.Count` and `Array<Slot>.Fixed` | STILL PRESENT — out of code-surface scope; tracked under implementation skill |
| POOL-017 | `try!` on `Array<Entry>.Fixed` (Pool.Bounded.swift:84,116) | STILL PRESENT at Pool.Bounded.swift:89,121 — out of code-surface scope |
| POOL-018 | `try!` on `available.push(index)` | STILL PRESENT at Pool.Bounded.State.swift:250 — out of code-surface scope |

### From: swift-institute/Research/async-pool-primitives-audit.md (2026-03-18, swift-pool-primitives portion)

| Original Finding | Description | Current Status |
|------------------|-------------|----------------|
| Finding 4 | `Slot.Index = Tagged<Self, Int>` with `.rawValue` at 30+ sites | RESOLVED — `Pool.Bounded.Slot.Index` is now `Tagged<Self, Ordinal>` (Pool.Bounded.Slot.swift:9), zero `.rawValue` calls remain in source |
| Finding 5 | State init conversion chain `Int → UInt → Cardinal → Count` | STILL PRESENT — Pool.Bounded.State.swift:69-71. Implementation skill scope. |
| Finding 6 | Raw `Int` counters in State (`outstanding`, `creating`, `disposing`) | DEFERRED (conscious debt — contained blast radius); Pool.Bounded.State.swift:55-63 |
| Finding 7 | Mixed `Int`/`UInt64` in metrics | DEFERRED — Pool.Bounded.State.swift:340 |

**Cross-references**: The legacy file at `swift-institute/Research/async-pool-primitives-audit.md` covers BOTH swift-async-primitives and swift-pool-primitives. Per [AUDIT-016] wrong-scope discovery, the pool-primitives portion of that file has been consolidated above. The async-primitives portion of that file remains in place at the swift-institute scope until swift-async-primitives gets its own per-package `Research/audit.md`.
