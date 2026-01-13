//
//  WebViewManagerStateTests.swift
//  NiiVueTests
//
//  Task 6: Tests for WebViewManager loading/error state
//

import XCTest
import WebKit
@testable import NiiVue

@MainActor
final class WebViewManagerStateTests: XCTestCase {
    func testWebViewInjectsAutoApplyCTPresetUserScriptAtDocumentStart() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())
        let scripts = manager.webView.configuration.userContentController.userScripts

        let script = try XCTUnwrap(scripts.first(where: { $0.source.contains("window.autoApplyCTPreset") }))
        XCTAssertEqual(script.injectionTime, .atDocumentStart)
        XCTAssertTrue(script.isForMainFrameOnly)
    }

    func testWebViewManagerWiresPreprocessedVolumeCacheToURLSchemeHandler() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())
        XCTAssertNotNil(manager.urlSchemeHandler.preprocessedVolumeCache)
    }

    func testUpdateUICTPresetAnalysisUpdatesPublishedState() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())

        XCTAssertNil(manager.lastCTPresetAnalysis)

        manager.handleScriptMessage(
            name: "updateUI",
            body: """
            {"type":"ctPresetAnalysis","payload":{"phase":"nephrographic","confidence":0.85,"calMin":60,"calMax":180,"windowWidth":120,"windowLevel":120,"colormap":"ct_urinary_adaptive"}}
            """
        )

        let analysis = try XCTUnwrap(manager.lastCTPresetAnalysis)
        XCTAssertEqual(analysis.phase, "nephrographic")
        XCTAssertEqual(analysis.colormap, "ct_urinary_adaptive")
        XCTAssertEqual(analysis.calMin, 60, accuracy: 0.0001)
        XCTAssertEqual(analysis.calMax, 180, accuracy: 0.0001)
        XCTAssertEqual(analysis.windowWidth, 120, accuracy: 0.0001)
        XCTAssertEqual(analysis.windowLevel, 120, accuracy: 0.0001)
    }

    func testUpdateUIDrawingDebugUpdatesPublishedState() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())

        XCTAssertNil(manager.lastDrawingOperation)
        XCTAssertNil(manager.lastDrawingDrawSum)

        manager.handleScriptMessage(
            name: "updateUI",
            body: """
            {"type":"drawingDebug","payload":{"operation":"drawOtsu","drawSum":1234}}
            """
        )

        let operation = try XCTUnwrap(manager.lastDrawingOperation)
        let drawSum = try XCTUnwrap(manager.lastDrawingDrawSum)
        XCTAssertEqual(operation, "drawOtsu")
        XCTAssertEqual(drawSum, 1234, accuracy: 0.0001)
    }

    func testInitializationTimeoutSetsErrorMessage() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator(), initializationTimeoutNanoseconds: 10_000_000) // 10ms
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        XCTAssertEqual(manager.lastErrorMessage, "WebView initialization timeout")
        XCTAssertFalse(manager.isReady)
    }

    func testReloadCancelsPreviousInitializationTimeout() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator(), initializationTimeoutNanoseconds: 100_000_000) // 100ms
        try await Task.sleep(nanoseconds: 30_000_000) // 30ms

        manager.reload()

        // Old timeout would have fired at ~100ms after init; new timeout should fire at ~100ms after reload.
        try await Task.sleep(nanoseconds: 80_000_000) // total ~110ms
        XCTAssertNil(manager.lastErrorMessage)

        try await Task.sleep(nanoseconds: 80_000_000) // total ~190ms
        XCTAssertEqual(manager.lastErrorMessage, "WebView initialization timeout")
    }

    func testWebViewManagerMarksReadyOnFinishedLoadingMessage() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        XCTAssertFalse(manager.isReady)
        manager.handleScriptMessage(name: "finishedLoading", body: "ready")
        XCTAssertTrue(manager.isReady)
    }

    func testReadyMessageClearsError() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator(), initializationTimeoutNanoseconds: 10_000_000) // 10ms
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms

        // Should have timeout error
        XCTAssertNotNil(manager.lastErrorMessage)

        // Simulate late ready message
        manager.handleScriptMessage(name: "finishedLoading", body: "ready")

        XCTAssertTrue(manager.isReady)
        XCTAssertNil(manager.lastErrorMessage)
    }

    func testVolumeLoadedUpdatesVolumesList() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())

        manager.handleScriptMessage(
            name: "volumeLoaded",
            body: "{\"id\":\"v1\",\"name\":\"T1w_DEMO.nii.gz\",\"nFrame4D\":1}"
        )

        XCTAssertEqual(manager.volumes.map(\.id), ["v1"])
        XCTAssertEqual(manager.volumes.map(\.name), ["T1w_DEMO.nii.gz"])
    }

    func testMultipleVolumesAreAppended() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())

        manager.handleScriptMessage(
            name: "volumeLoaded",
            body: "{\"id\":\"v1\",\"name\":\"T1w.nii.gz\",\"nFrame4D\":1}"
        )
        manager.handleScriptMessage(
            name: "volumeLoaded",
            body: "{\"id\":\"v2\",\"name\":\"FLAIR.nii.gz\",\"nFrame4D\":1}"
        )

        XCTAssertEqual(manager.volumes.count, 2)
        XCTAssertEqual(manager.volumes.map(\.id), ["v1", "v2"])
    }

    func testVolumeUpdateReplacesExisting() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())

        manager.handleScriptMessage(
            name: "volumeLoaded",
            body: "{\"id\":\"v1\",\"name\":\"T1w.nii.gz\",\"nFrame4D\":1}"
        )
        manager.handleScriptMessage(
            name: "volumeLoaded",
            body: "{\"id\":\"v1\",\"name\":\"T1w_updated.nii.gz\",\"nFrame4D\":5}"
        )

        XCTAssertEqual(manager.volumes.count, 1)
        XCTAssertEqual(manager.volumes[0].name, "T1w_updated.nii.gz")
        XCTAssertEqual(manager.volumes[0].nFrame4D, 5)
    }

    func testLoadImageFromUrlClearsVolumesList() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())

        manager.handleScriptMessage(
            name: "volumeLoaded",
            body: "{\"id\":\"v1\",\"name\":\"T1w.nii.gz\",\"nFrame4D\":1}"
        )
        XCTAssertEqual(manager.volumes.count, 1)

        try await manager.loadImageFromUrl(url: "niivue://app/files/abc123", fileName: "T1w.nii.gz")

        XCTAssertEqual(manager.volumes.count, 0)
    }

    func testLoadBase64ImageClearsVolumesList() async throws {
        let manager = WebViewManager(evaluator: MockJavaScriptEvaluator())

        manager.handleScriptMessage(
            name: "volumeLoaded",
            body: "{\"id\":\"v1\",\"name\":\"T1w.nii.gz\",\"nFrame4D\":1}"
        )
        XCTAssertEqual(manager.volumes.count, 1)

        try await manager.loadBase64Image(base64: "AA==", fileName: "T1w.nii.gz")

        XCTAssertEqual(manager.volumes.count, 0)
    }
}
