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
import Reference_Primitives

// MARK: - Test Resource

private struct TestResource: Sendable {
    let id: Int
}

// MARK: - Tests

@Suite("Pool.Acquire")
struct PoolAcquireTests {

    @Test("effect stores scope as arguments")
    func effectStoresScope() {
        let scope = Pool.Scope()
        let effect = Pool.Acquire<TestResource>(scope: scope)

        #expect(effect.scope == scope)
        #expect(effect.arguments == scope)
    }

    @Test("effect is Sendable")
    func effectIsSendable() {
        func requiresSendable<T: Sendable>(_: T.Type) {}
        requiresSendable(Pool.Acquire<TestResource>.self)
    }

    @Test("value type is Reference.Box")
    func valueTypeIsBox() {
        let _: Pool.Acquire<TestResource>.Value.Type = Reference.Box<TestResource>.self
    }

    @Test("failure type is Pool.Error")
    func failureTypeIsPoolError() {
        let _: Pool.Acquire<TestResource>.Failure.Type = Pool.Error.self
    }

    @Test("different scopes produce different effects")
    func differentScopes() {
        let scope1 = Pool.Scope()
        let scope2 = Pool.Scope()

        let effect1 = Pool.Acquire<TestResource>(scope: scope1)
        let effect2 = Pool.Acquire<TestResource>(scope: scope2)

        #expect(effect1.scope != effect2.scope)
    }
}
