//
//  SegmentationCommandTests.swift
//  NiiVueTests
//
//  Phase 2 Task 5: Segmentation/Draw Tooling Pack
//

import XCTest
@testable import NiiVue

@MainActor
final class SegmentationCommandTests: XCTestCase {
    func testUndoCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.drawUndo()
        XCTAssertTrue(js.scripts[0].contains("drawUndo"))
    }
}
