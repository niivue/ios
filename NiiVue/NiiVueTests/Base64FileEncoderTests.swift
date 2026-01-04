//
//  Base64FileEncoderTests.swift
//  NiiVueTests
//
//  Swift 6 concurrency follow-up: base64 encoding must be non-main-actor.
//

import XCTest
import Foundation
@testable import NiiVue

final class Base64FileEncoderTests: XCTestCase {
    private func makeTempFile(data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NiiVue-Base64FileEncoderTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: dir)
        }

        let url = dir.appendingPathComponent("payload.bin")
        try data.write(to: url, options: [.atomic])
        return url
    }

    func testEncodeFileToBase64ReturnsExpectedStringForSmallFile() throws {
        let data = Data("hi".utf8)
        let url = try makeTempFile(data: data)

        let encoded = Base64FileEncoder.encodeFileToBase64(url: url, maxBytes: 1024)

        XCTAssertEqual(encoded, data.base64EncodedString())
    }

    func testEncodeFileToBase64ReturnsNilWhenFileTooLarge() throws {
        let data = Data(repeating: 0xAB, count: 8)
        let url = try makeTempFile(data: data)

        let encoded = Base64FileEncoder.encodeFileToBase64(url: url, maxBytes: 1)

        XCTAssertNil(encoded)
    }
}

