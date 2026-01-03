//
//  JavaScriptEvaluatingTests.swift
//  NiiVueTests
//
//  Task 3: Tests for async JavaScript evaluation abstraction
//

import XCTest
@testable import NiiVue

final class JavaScriptEvaluatingTests: XCTestCase {
    @MainActor
    func testMockCapturesScripts() async throws {
        let mock = MockJavaScriptEvaluator()
        try await mock.evaluateCommand("1 + 1")
        XCTAssertEqual(mock.scripts, ["1 + 1"])
    }

    @MainActor
    func testMockReturnsConfiguredString() async throws {
        let mock = MockJavaScriptEvaluator()
        mock.nextString = "hello"
        let result = try await mock.evaluateString("window.greeting")
        XCTAssertEqual(result, "hello")
    }

    @MainActor
    func testMockReturnsConfiguredAsyncString() async throws {
        let mock = MockJavaScriptEvaluator()
        mock.nextAsyncString = "async result"
        let result = try await mock.callAsyncString("return await fetch(...)")
        XCTAssertEqual(result, "async result")
    }

    @MainActor
    func testMockAccumulatesMultipleScripts() async throws {
        let mock = MockJavaScriptEvaluator()
        try await mock.evaluateCommand("first")
        try await mock.evaluateCommand("second")
        _ = try await mock.evaluateString("third")
        XCTAssertEqual(mock.scripts, ["first", "second", "third"])
    }
}
