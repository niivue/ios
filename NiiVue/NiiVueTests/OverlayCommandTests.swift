//
//  OverlayCommandTests.swift
//  NiiVueTests
//
//  Phase 2 Task 3: Colormap and opacity controls
//

import XCTest
@testable import NiiVue

@MainActor
final class OverlayCommandTests: XCTestCase {
    func testSetColormapCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.setColormap(volumeIndex: 0, colormap: "red")
        XCTAssertTrue(js.scripts[0].contains("setColormap"))
    }

    func testSetOpacityCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.setOpacity(volumeIndex: 0, opacity: 0.5)
        XCTAssertTrue(js.scripts[0].contains("setOpacity"))
    }
}
