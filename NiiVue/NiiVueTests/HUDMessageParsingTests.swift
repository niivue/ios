//
//  HUDMessageParsingTests.swift
//  NiiVueTests
//
//  Phase 2 Task 1: HUD location readout
//

import XCTest
@testable import NiiVue

@MainActor
final class HUDMessageParsingTests: XCTestCase {
    func testLocationMessageIsStored() throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())
        manager.handleScriptMessage(name: "locationChange", body: "{\"string\":\"1×2×3 = 4\"}")
        XCTAssertEqual(manager.lastLocationString, "1×2×3 = 4")
    }
}
