//
//  DicomSeriesStoreTests.swift
//  NiiVueTests
//
//  Phase 2 Task 8: Tests for DicomSeriesStore
//  Verifies manifest generation and file registration.
//

import XCTest
@testable import NiiVue

@MainActor
final class DicomSeriesStoreTests: XCTestCase {
    func testManifestListsFilenamesOnePerLine() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let a = tmp.appendingPathComponent("a.dcm")
        let b = tmp.appendingPathComponent("b.dcm")
        try Data([0x01]).write(to: a)
        try Data([0x02]).write(to: b)

        let store = DicomSeriesStore()
        let seriesId = await store.register(files: [a, b])
        let manifest = await store.manifestText(for: seriesId)

        XCTAssertEqual(manifest, "a.dcm\nb.dcm")
    }

    func testUrlResolution() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let testFile = tmp.appendingPathComponent("test.dcm")
        try Data([0xAA]).write(to: testFile)

        let store = DicomSeriesStore()
        let seriesId = await store.register(files: [testFile])
        let resolvedURL = await store.url(for: seriesId, fileName: "test.dcm")

        XCTAssertEqual(resolvedURL, testFile)
    }

    func testManifestHasNoTrailingNewline() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let file = tmp.appendingPathComponent("single.dcm")
        try Data([0x01]).write(to: file)

        let store = DicomSeriesStore()
        let seriesId = await store.register(files: [file])
        let manifest = await store.manifestText(for: seriesId)

        XCTAssertFalse(manifest.hasSuffix("\n"), "Manifest should not have trailing newline")
        XCTAssertEqual(manifest, "single.dcm")
    }
}
