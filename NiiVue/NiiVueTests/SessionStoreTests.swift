//
//  SessionStoreTests.swift
//  NiiVueTests
//
//  Phase 2 Task 6: Session Save/Restore Pack
//

import XCTest
@testable import NiiVue

final class SessionStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() async throws {
        let store = SessionStore()
        let id = try await store.save(json: "{\"hello\":\"world\"}")
        let loaded = try await store.load(id: id)
        XCTAssertEqual(loaded, "{\"hello\":\"world\"}")
    }
}
