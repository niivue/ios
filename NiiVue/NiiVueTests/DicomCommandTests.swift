//
//  DicomCommandTests.swift
//  NiiVueTests
//
//  Phase 2 Task 9: Tests for DICOM bridge wrapper in WebViewManager
//

import XCTest
@testable import NiiVue

@MainActor
final class DicomCommandTests: XCTestCase {
    func testLoadDicomSeriesCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadDicomSeriesFromManifestURL("niivue://app/dicom/series1/niivue-manifest.txt")

        XCTAssertTrue(js.scripts[0].contains("loadDicomSeriesFromManifest"))
    }

    func testLoadDicomSeriesEscapesManifestURL() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadDicomSeriesFromManifestURL("niivue://app/dicom/test\"series/niivue-manifest.txt")

        // The URL should be JSON-escaped to prevent injection
        XCTAssertTrue(js.scripts[0].contains("\\\""))
    }
}
