//
//  JavaScriptQuoteTests.swift
//  NiiVueTests
//
//  Task 2: JSON-safe JavaScript string quoting helper
//

import XCTest
@testable import NiiVue

final class JavaScriptQuoteTests: XCTestCase {
    func testQuoteEscapesSingleQuoteAndNewline() throws {
        let input = "O'Reilly\nLine2"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"O'Reilly\\nLine2\"")
    }

    func testQuoteEscapesDoubleQuotes() throws {
        let input = "He said \"hello\""
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"He said \\\"hello\\\"\"")
    }

    func testQuoteHandlesEmptyString() throws {
        let input = ""
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"\"")
    }

    func testQuoteHandlesSpecialCharacters() throws {
        let input = "tab\there\rcarriage"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertTrue(quoted.contains("\\t"))
        XCTAssertTrue(quoted.contains("\\r"))
    }
}
