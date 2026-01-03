//
//  DrawingExportServiceTests.swift
//  NiiVueTests
//
//  Task 5: Tests for DrawingExportService
//

import XCTest
@testable import NiiVue

final class DrawingExportServiceTests: XCTestCase {
    func testDecodeBase64WritesFile() throws {
        let service = DrawingExportService()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let data = Data([0x01, 0x02, 0x03])
        let b64 = data.base64EncodedString()

        let url = try service.writeNiftiGz(base64: b64, preferredFileName: "out.nii.gz", directory: tmp)

        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testInvalidBase64Throws() {
        let service = DrawingExportService()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        XCTAssertThrowsError(try service.writeNiftiGz(base64: "not valid base64!!!", preferredFileName: "out.nii.gz", directory: tmp))
    }

    func testFileHasCorrectFileName() throws {
        let service = DrawingExportService()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let data = Data([0xAB, 0xCD])
        let b64 = data.base64EncodedString()

        let url = try service.writeNiftiGz(base64: b64, preferredFileName: "test_drawing.nii.gz", directory: tmp)

        XCTAssertEqual(url.lastPathComponent, "test_drawing.nii.gz")
    }
}
