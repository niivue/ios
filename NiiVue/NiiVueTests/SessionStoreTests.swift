//
//  SessionStoreTests.swift
//  NiiVueTests
//
//  Phase 2 Task 6: Session Save/Restore Pack
//

import XCTest
import Foundation
@testable import NiiVue

final class SessionStoreTests: XCTestCase {
    private func makeTempSessionsDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NiiVue-SessionStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sessionsDir = root.appendingPathComponent("Sessions", isDirectory: true)

        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        return sessionsDir
    }

    func testSaveAndLoadRoundTrip() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)
        let id = try await store.save(json: "{\"hello\":\"world\"}")
        let loaded = try await store.load(id: id)
        XCTAssertEqual(loaded, "{\"hello\":\"world\"}")
    }

    func testLoadRejectsPathTraversalID() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        let outsideFile = sessionsDir.deletingLastPathComponent().appendingPathComponent("outside.json")
        try "{\"pwned\":true}".write(to: outsideFile, atomically: true, encoding: .utf8)

        do {
            _ = try await store.load(id: "../outside")
            XCTFail("Expected invalid ID to be rejected")
        } catch {
            XCTAssertEqual(error as? SessionStoreError, .invalidID)
        }
    }

    func testDeleteRejectsPathTraversalID() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        let outsideFile = sessionsDir.deletingLastPathComponent().appendingPathComponent("outside.json")
        try "{\"pwned\":true}".write(to: outsideFile, atomically: true, encoding: .utf8)

        do {
            try await store.delete(id: "../outside")
        } catch {
            XCTAssertEqual(error as? SessionStoreError, .invalidID)
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: outsideFile.path),
            "Path traversal must not delete outside files: \(outsideFile.path)"
        )
    }

    func testListReturnsOnlyJSONSessionIDs() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        let validID = UUID().uuidString
        let jsonFile = sessionsDir.appendingPathComponent("\(validID).json")
        let invalidJsonFile = sessionsDir.appendingPathComponent("not-a-uuid.json")
        let nonJsonFile = sessionsDir.appendingPathComponent("not-a-session.txt")
        try "{}".write(to: jsonFile, atomically: true, encoding: .utf8)
        try "{}".write(to: invalidJsonFile, atomically: true, encoding: .utf8)
        try "ignore".write(to: nonJsonFile, atomically: true, encoding: .utf8)

        let ids = try await store.list()
        XCTAssertEqual(ids, [validID])
    }
}
