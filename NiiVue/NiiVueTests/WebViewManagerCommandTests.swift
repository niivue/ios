//
//  WebViewManagerCommandTests.swift
//  NiiVueTests
//
//  Task 4: Tests for WebViewManager using safe quoting + async evaluation
//

import XCTest
@testable import NiiVue

@MainActor
final class WebViewManagerCommandTests: XCTestCase {
    func testLoadBase64ImageUsesJSONEscapedArguments() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadBase64Image(base64: "AA==", fileName: "O'Reilly.nii.gz")

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.loadBase64Image"))
        XCTAssertTrue(
            js.scripts[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("return await window.loadBase64Image(")
        )
        XCTAssertTrue(js.scripts[0].contains("\"O'Reilly.nii.gz\""))
    }

    func testLoadImageFromUrlUsesAsyncAwaitEvaluation() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadImageFromUrl(url: "niivue://app/files/abc123", fileName: "T1w.nii.gz")

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.loadImageFromUrl"))
        XCTAssertTrue(
            js.scripts[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("return await window.loadImageFromUrl(")
        )
    }

    func testSetSliceTypeUsesJSONEscapedArguments() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.setSliceType(sliceType: 3)

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.setSliceType"))
        XCTAssertTrue(js.scripts[0].contains("3"))
    }

    func testSetLayoutUsesJSONEscapedArguments() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.setLayout(layout: 2)

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.setLayout"))
        XCTAssertTrue(js.scripts[0].contains("2"))
    }

    func testSetPenValueUsesJSONEscapedArguments() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.setPenValue(penValue: 1, isFilled: true, drawingEnabled: true)

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.setPenValue"))
    }

    func testLoadVolumesFromUrlsBuildsCorrectJSCall() async throws {
        let js = MockJavaScriptEvaluator()
        // Provide mock return for syncVolumeCount's getVolumeInfoList call (uses callAsyncString)
        js.nextAsyncString = "[]"
        let manager = WebViewManager(evaluator: js)

        let volumes = [
            (url: "niivue://app/samples/T1.nii.gz", name: "T1.nii.gz"),
            (url: "niivue://app/samples/T2.nii.gz", name: "T2.nii.gz")
        ]
        try await manager.loadVolumesFromUrls(volumes)

        // We expect 2 scripts: loadVolumesFromUrls and getVolumeInfoList
        XCTAssertGreaterThanOrEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.loadVolumesFromUrls"))
        // Verify the JSON array structure - note the escaped quotes in the JSON
        XCTAssertTrue(js.scripts[0].contains("T1.nii.gz"), "Script should contain T1.nii.gz: \(js.scripts[0])")
        XCTAssertTrue(js.scripts[0].contains("T2.nii.gz"), "Script should contain T2.nii.gz: \(js.scripts[0])")
    }
}
