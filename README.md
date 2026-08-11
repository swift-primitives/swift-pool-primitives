# Pool Primitives

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)
[![CI](https://github.com/swift-primitives/swift-pool-primitives/actions/workflows/ci.yml/badge.svg)](https://github.com/swift-primitives/swift-pool-primitives/actions/workflows/ci.yml)

`Pool.Bounded<Resource>` provides bounded asynchronous resource ownership with explicit reuse or invalidation and joined asynchronous disposal.

---

## Key Features

- **Bounded capacity** — a fixed number of resources; `acquire` suspends when the pool is exhausted instead of allocating more.
- **Explicit terminal disposition** — every successful `acquire` body returns `.reusable(result)` or `.invalid(result)`; throws, cancellation, shutdown, and failed validation destroy the resource.
- **Move-only resources** — `Resource: ~Copyable`; a resource is moved between the pool and the borrower, never duplicated.
- **Joined async destruction** — fill rejection, invalidation, return validation, and shutdown await the same consuming destructor.
- **Observable** — `metrics` reports live pool state (outstanding, available, waiters) for instrumentation.

---

## Quick Start

```swift
import Pool_Primitives

final class Connection {
    var isHealthy = true

    func close() async {}
    func send(_ request: Int) -> Int { request }
}

let pool = Pool.Bounded<Connection>(
    capacity: 4,
    check: { $0.isHealthy },
    destroy: { connection in await connection.close() }
)
try await pool.fill(Connection())

let reply = try await pool.acquire { connection in
    let reply = connection.send(200)
    return connection.isHealthy ? .reusable(reply) : .invalid(reply)
}

await pool.shutdown()
```

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-primitives/swift-pool-primitives.git", branch: "main")
]
```

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "Pool Primitives", package: "swift-pool-primitives")
    ]
)
```

`Pool.Bounded` is an ordinary package surface. Consumers select either the
`Pool Primitives` umbrella or the narrower `Pool Bounded Primitives` product;
no package trait or SPI is required.

The package is pre-1.0 — depend on `branch: "main"` until `0.1.0` is tagged. Requires Swift 6.3 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or the corresponding Linux / Windows toolchain).

---

## Architecture

| Product | Contents | When to import |
|---------|----------|----------------|
| `Pool Primitives` | Umbrella — the `Pool` namespace, metrics, and `Pool.Bounded` | Most consumers |
| `Pool Bounded Primitives` | `Pool.Bounded<Resource>` | Just the bounded pool |

---

## Platform Support

| Platform         | CI  | Status       |
|------------------|-----|--------------|
| macOS 26         | Yes | Full support |
| Linux            | Yes | Full support |
| Windows          | Yes | Full support |
| iOS/tvOS/watchOS | —   | Supported    |
| Swift Embedded   | —   | Pending exact bounded-pool evidence |

`Pool.Bounded` has a fully asynchronous lifecycle. This source-only change does
not claim Embedded compatibility; that requires a later exact toolchain build.

---

## Error Handling

Acquisition separates lifecycle failures from body failures:

```text
Either<Pool.Lifecycle.Error, BodyError>
├── .left(.shutdown)
├── .left(.cancelled)
├── .left(.creationFailed)
└── .right(BodyError)
```

`fill` throws `Pool.Bounded<Resource>.Fill.Error`: `.notEager`, `.shutdown`,
`.full`, or `.invalid`. A rejected resource is destroyed before the error is
returned.

---

## Related Packages

### Dependencies

- [`swift-async-primitives`](https://github.com/swift-primitives/swift-async-primitives) — the async mutex and gate the pool coordinates acquisition and shutdown with when `Concurrency` is enabled.

---

## Community

<!-- BEGIN: discussion -->
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
