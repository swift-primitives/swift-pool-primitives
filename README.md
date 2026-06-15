# Pool Primitives

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)
[![CI](https://github.com/swift-primitives/swift-pool-primitives/actions/workflows/ci.yml/badge.svg)](https://github.com/swift-primitives/swift-pool-primitives/actions/workflows/ci.yml)

`Pool.Bounded<Resource>` — a bounded async resource pool. `acquire` borrows a resource for the duration of a closure and returns it to the pool afterward; when every resource is checked out, callers suspend until one is released (backpressure rather than over-allocation). Resources are `~Copyable`, so a pooled connection, buffer, or handle is moved in and out rather than copied, and a `destroy` hook reclaims each one at shutdown.

---

## Key Features

- **Bounded capacity** — a fixed number of resources; `acquire` suspends when the pool is exhausted instead of allocating more.
- **Scoped acquire / release** — `acquire { resource in … }` returns the resource automatically when the closure exits, on success or throw.
- **Move-only resources** — `Resource: ~Copyable`; a resource is moved between the pool and the borrower, never duplicated.
- **Observable** — `metrics` reports live pool state (outstanding, available, waiters) for instrumentation.

---

## Quick Start

```swift
import Pool_Primitives

final class Connection: Sendable {
    func close() {}
    func send(_ request: Int) -> Int { request }
}

// A bounded pool of up to 4 connections; `destroy` reclaims a resource at shutdown.
let pool = Pool.Bounded<Connection>(capacity: 4, destroy: { $0.close() })
try pool.fill(Connection())                 // hand a resource to the pool

// `acquire` borrows a resource for the closure, then returns it to the pool:
let reply = try await pool.acquire { connection in
    connection.send(200)
}
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

The package is pre-1.0 — depend on `branch: "main"` until `0.1.0` is tagged. Requires Swift 6.3 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or the corresponding Linux / Windows toolchain).

---

## Architecture

| Product | Contents | When to import |
|---------|----------|----------------|
| `Pool Primitives` | Umbrella — `Pool.Bounded`, the `Pool` namespace, and metrics | Most consumers |
| `Pool Bounded Primitives` | `Pool.Bounded<Resource>` — the bounded resource pool | Just the bounded pool |

---

## Platform Support

| Platform         | CI  | Status       |
|------------------|-----|--------------|
| macOS 26         | Yes | Full support |
| Linux            | Yes | Full support |
| Windows          | Yes | Full support |
| iOS/tvOS/watchOS | —   | Supported    |
| Swift Embedded   | —   | Pending (nightly-toolchain follow-up) |

---

## Related Packages

- [`swift-async-primitives`](https://github.com/swift-primitives/swift-async-primitives) — the async mutex and gate the pool coordinates acquisition and shutdown with.

---

## Community

<!-- BEGIN: discussion -->
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
