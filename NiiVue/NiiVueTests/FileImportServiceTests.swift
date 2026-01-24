//
//  FileImportServiceTests.swift
//  NiiVueTests
//
//  Task 9: Tests for FileImportService
//

import XCTest
@testable import NiiVue

final class FileImportServiceTests: XCTestCase {
    func testImportMovesFileIntoDestinationDirectory() async throws {
        // Create a temp file (simulates asCopy: true behavior)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0xAA, 0xBB]).write(to: tmp)

        let service = FileImportService()
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let imported = try await service.importDocument(at: tmp, destinationDirectory: destDir)

        // Verify file was moved (not copied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "Temp file should be moved, not copied")
        XCTAssertFalse(imported.id.isEmpty)
        XCTAssertEqual(imported.originalFileName, tmp.lastPathComponent)
        XCTAssertEqual(try Data(contentsOf: imported.localURL), Data([0xAA, 0xBB]))
    }

    func testImportCreatesUniqueSubdirectory() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0x01]).write(to: tmp)

        let service = FileImportService()
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let imported = try await service.importDocument(at: tmp, destinationDirectory: destDir)

        // Verify file is in a subdirectory named after the ID
        XCTAssertTrue(imported.localURL.path.contains(imported.id))
    }

    func testImportPreservesOriginalFileName() async throws {
        let originalName = "my_brain_scan.nii.gz"
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(originalName)
        try Data([0x02]).write(to: tmp)

        let service = FileImportService()
        let destDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let imported = try await service.importDocument(at: tmp, destinationDirectory: destDir)

        XCTAssertEqual(imported.originalFileName, originalName)
        XCTAssertTrue(imported.localURL.lastPathComponent == originalName)
    }
}
