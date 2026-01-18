// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-pools open source project
//
// Copyright (c) 2025 Coen ten Thije Boonkkamp and the swift-pools project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

import Testing
@testable import Pool_Primitives

// MARK: - Test Resource

private struct TestResource: Sendable {
    let id: Int
}

// MARK: - Tests

@Suite("Pool.Release")
struct PoolReleaseTests {

    @Test("effect stores id as arguments")
    func effectStoresId() {
        let scope = Pool.Scope()
        let id = Pool.ID(raw: 1, scope: scope)
        let effect = Pool.Release<TestResource>(id: id)

        #expect(effect.id == id)
        #expect(effect.arguments == id)
    }

    @Test("effect is Sendable")
    func effectIsSendable() {
        func requiresSendable<T: Sendable>(_: T.Type) {}
        requiresSendable(Pool.Release<TestResource>.self)
    }

    @Test("value type is Void")
    func valueTypeIsVoid() {
        let _: Pool.Release<TestResource>.Value.Type = Void.self
    }

    @Test("failure type is Never")
    func failureTypeIsNever() {
        let _: Pool.Release<TestResource>.Failure.Type = Never.self
    }

    @Test("different ids produce different effects")
    func differentIds() {
        let scope = Pool.Scope()
        let id1 = Pool.ID(raw: 1, scope: scope)
        let id2 = Pool.ID(raw: 2, scope: scope)

        let effect1 = Pool.Release<TestResource>(id: id1)
        let effect2 = Pool.Release<TestResource>(id: id2)

        #expect(effect1.id != effect2.id)
    }
}
