//
//  TimeSeriesCommandTests.swift
//  NiiVueTests
//
//  Phase 2 Task 4: 4D Time-Series Controls
//

import XCTest
@testable import NiiVue

@MainActor
final class TimeSeriesCommandTests: XCTestCase {
    func testSetFrameCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.setFrame4D(volumeIndex: 0, frame: 3)
        XCTAssertTrue(js.scripts[0].contains("setFrame4D"))
    }
}
