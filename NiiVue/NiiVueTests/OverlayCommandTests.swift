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

    func testListColormapsParsesJSONAndDoesNotUseReturnPrefix() async throws {
        let js = MockJavaScriptEvaluator()
        js.nextString = "[\"gray\",\"hot\"]"
        let manager = WebViewManager(evaluator: js)

        let colormaps = try await manager.listColormaps()

        XCTAssertEqual(colormaps, ["gray", "hot"])
        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.listColormaps"))
        XCTAssertFalse(
            js.scripts[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("return "),
            "evaluateString must not receive a function-body 'return ...' script: \(js.scripts[0])"
        )
    }
}
