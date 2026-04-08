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

---

## Follow-ups — 2026-04-08

Items recommended after the `ownership-transfer-conventions` second-round
refactor (commit `1f360de`). These are NOT findings against the current
audit skills (code-surface, modularization) — the formal findings tables
above show zero open issues. They are verification tasks, dead-code
checks, and follow-up scope items that future sessions should pick up.

### Verification tasks (medium priority)

| # | Item | Why | How to apply |
|---|------|-----|--------------|
| F-01 | Verify `Either<X, Never>` exhaustive switch elision actually works | The new canonical API and `Pool.Bounded.Acquire.swift` doc comment claim that for non-throwing bodies (where `E = Never`), Swift's pattern matcher allows omitting the `.right(Never)` case at catch sites. This is asserted but not proven by a test. | Add a test in `Pool.Bounded.AsyncBody Tests.swift`: write `do throws(Either<Pool.Lifecycle.Error, Never>) { try await pool.acquire { … } } catch { switch error { case .left(.shutdown): … } }` with NO `.right` case in the switch, and verify it compiles. If Swift requires the case, update the docstring honestly. |
| F-02 | Run a release build with the cclsp flags | Per the `io-bench test command` memory entry, primitives should be built with `swift test -c release -Xswiftc -Xllvm -Xswiftc -sil-disable-pass=CopyPropagation`. Only debug builds have been verified during this refactor. | `swift test -c release -Xswiftc -Xllvm -Xswiftc -sil-disable-pass=CopyPropagation` from the package root. Resolve any release-mode-only issues (CopyPropagation interactions with `~Copyable`, etc). |
| F-03 | Verify `Pool.Acquire` (the `Effect.Protocol` type in Pool Primitives Core) still composes correctly | `Pool.Acquire<Resource>` is the public effect type used by Effect.Protocol consumers. Its `Value` typealias is `Ownership.Shared<Resource>` (a workaround for protocol associated-types lacking `~Copyable` support, per its own doc comment). With `Resource: ~Copyable` only (no Sendable), this should still work — but `Ownership.Shared<Value: ~Copyable & Sendable>` requires `Value: Sendable`. The Pool.Acquire type may not even instantiate for non-Sendable Resources. | Read `Sources/Pool Primitives Core/Pool.Acquire.swift` and `Pool.Release.swift`. Try to instantiate `Pool.Acquire<NonSendableHandle>` in a test. If it doesn't compile, decide: (a) keep `Resource: ~Copyable & Sendable` on the Effect.Protocol types only (Pool.Bounded class stays at `~Copyable` only); (b) restructure the Effect.Protocol Value type to not require Sendable (may require waiting on Suppressed Associated Types With Defaults). |
| F-04 | Trace `Pool.Bounded._check` usage | The optional `_check: (@Sendable (inout Resource) -> Bool)?` validation closure is stored on Pool.Bounded but its callers may have all been deleted in the Try/Timeout removal. If unused, drop it (and the corresponding init parameter). If used, document the call site and verify it works under the new sending/inout shape. | `grep -rn "_check" "Sources/Pool Bounded Primitives/"`. Trace every reference. If only the storage and init reference it, the closure is dead code. |
| F-05 | Verify `Pool.Bounded.Acquire.Callback` still composes correctly | The Callback variant was deliberately left unchanged in this refactor (embedded-only contract). It uses `Result<T, Pool.Lifecycle.Error>` in the completion shape and retains `@Sendable` on body and completion closures. With the new `Pool.Lifecycle.Error` (3 cases) and the Sendable cleanup elsewhere, verify the Callback variant still builds and behaves correctly end-to-end. | Add a small test that exercises `pool.acquire.callback(body, completion: ...)` with a non-Sendable resource, both immediate and waiter-queued paths. |

### Code-surface follow-ups (medium-low priority)

| # | Item | Why | How to apply |
|---|------|-----|--------------|
| F-06 | Audit `Pool.Bounded.Acquire.Callback` for further `@Sendable` reduction | The Callback variant has `@Sendable` on the body, completion, and internal helpers. Some of these may be necessary (closures stored in waiter queue → fire from arbitrary executor context), but a careful audit may identify drops. The `@Sendable` annotations on the `enqueueWaiter` callback's internal capture are particularly worth re-examining. | Read `Pool.Bounded.Acquire.Callback.swift` line by line; for each `@Sendable`, identify the storage location and invocation context; drop where the closure stays in caller isolation. |
| F-07 | Consider `nonisolated(unsafe)` audit | Pool.Bounded has exactly one `nonisolated(unsafe) var onEnqueue` (DEBUG-only). Verify no other `var` properties on Sendable types lurk that should also be `nonisolated(unsafe)` or restructured. | `grep -rn "var " "Sources/Pool Bounded Primitives/" \| grep -v "let "`. Each mutable stored property on a Sendable type is suspicious. |
| F-08 | Check internal action enums for `~Copyable` opportunities | The action enums (`Acquire.Action`, `Fill.Action`, `Fill.Commit`, `Effect`, `Effect.Gate`, `Effect.Waiter`, `Release.Action`, `Shutdown.Drain`) computed under `withLock` and returned as `sending T`. Some are already `~Copyable`. Others (like `Acquire.Action`) are still implicitly Copyable. Audit which should be `~Copyable` for stricter ownership semantics. | Read each action enum file. If any case carries an owned resource (e.g., a `consuming` value), the enum should be `~Copyable`. Otherwise leave alone — Copyable is fine for pure value enums. |
| F-09 | Drop `Ownership.Shared` survey | `Ownership.Shared` was removed from `Creator` and `Destructor` typealiases in commit `bddfb28`. Verify no other `Ownership.Shared` usage lurks in the package; the only legitimate Ownership-primitives use should be `Ownership.Slot<Resource>` for the Entry storage. | `grep -rn "Ownership\." "Sources/Pool Bounded Primitives/" "Sources/Pool Primitives Core/"`. Anything that isn't `Ownership.Slot` deserves scrutiny. |

### Cross-package follow-ups (separate work)

| # | Item | Why | Where |
|---|------|-----|-------|
| F-10 | Apply the same convention treatment to swift-pools' `Pool.Blocking` | Pool.Blocking is the L3 sync/blocking variant of the same primitive. It uses the same `Pool.Lifecycle.Error` (verified to still build) but has its own conventions to audit: drop unnecessary `Sendable`, drop unnecessary `@Sendable`, use `inout sending` body parameters where applicable, eliminate `Ownership.Shared` if any, verify the timeout/cancellation paths align with the composition-not-deadline philosophy. | swift-foundations/swift-pools — `Sources/Pool Blocking/`. Separate package, separate PR. |
| F-11 | Build a `withTimeout(_:operation:)` primitive in swift-async-primitives | The composition-not-deadline design assumes such a primitive exists for the timeout use case. Currently callers needing timeouts write a Task-cancellation harness. A single `withTimeout` utility belongs in swift-async-primitives so all timeout-needing primitives compose with it the same way. | swift-async-primitives. Open a separate issue/PR. The Pool refactor proceeds without it; this is purely an ergonomics improvement for downstream consumers. |
| F-12 | swift-io's `IO.Blocking.Driver` migration | The original handoff for this branch was an IO.Blocking.Driver refactor that needed Pool.Bounded as an admission counting semaphore. The new single-overload API is what that refactor needs. The handoff `## Completion` section is now updated for the new shape; the parent IO conversation should consume it. | swift-io. Tracked via the original handoff document. |

### Workflow tasks

| # | Item | Why |
|---|------|-----|
| F-13 | Push `ownership-transfer-conventions` branch and open a PR | The branch is in a stable state with all tests passing, audit clean, downstream verified. Ready for review. |
| F-14 | Save key decisions to memory | Future sessions benefit from knowing: (a) `Either<X, Y>` from swift-algebra-primitives is the canonical error union (not Apple's `EitherError`); (b) Pool primitives compose timeouts/cancellation externally — never carry deadline parameters; (c) Drop `Ownership.Shared` for closure storage — closures are reference-typed already. |

### Out of scope (do not pick up here)

- **The Slot.Index `__unchecked` constructor** + raw counters in State.
  These are implementation-skill scope (intent-over-mechanism), not
  code-surface or modularization. Belong in a separate "intent over
  mechanism" PR.
- **Pool.Bounded as a `~Copyable` struct** mirroring Async.Mutex layout.
  Eliminates the class but is a much bigger restructure with diminishing
  returns. Defer indefinitely.
- **Renaming Pool.Lifecycle.Error.cancelled** or any other API name. The
  current shape is correct as is.
