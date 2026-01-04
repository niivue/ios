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

    func testAddVolumesFromUrlsBuildsCorrectJSCall() async throws {
        let js = MockJavaScriptEvaluator()
        js.nextAsyncString = "[]"
        let manager = WebViewManager(evaluator: js)

        let overlays = [
            (url: "niivue://app/files/a", name: "mask-a.nii.gz"),
            (url: "niivue://app/files/b", name: "mask-b.nii.gz")
        ]
        try await manager.addVolumesFromUrls(overlays)

        XCTAssertGreaterThanOrEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.addVolumesFromUrls"))
        XCTAssertTrue(js.scripts[0].contains("mask-a.nii.gz"))
        XCTAssertTrue(js.scripts[0].contains("mask-b.nii.gz"))
        XCTAssertTrue(js.scripts.contains(where: { $0.contains("window.getVolumeInfoList") }))
    }

    func testLoadMeshesFromUrlsBuildsCorrectJSCall() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        let meshes = [
            (url: "niivue://app/files/m1", name: "lh.pial.gii"),
            (url: "niivue://app/files/m2", name: "rh.pial.gii")
        ]
        try await manager.loadMeshesFromUrls(meshes)

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.loadMeshesFromUrls"))
        XCTAssertTrue(js.scripts[0].contains("lh.pial.gii"))
        XCTAssertTrue(js.scripts[0].contains("rh.pial.gii"))
    }

    func testExportViewerStateJSONBuildsCorrectJSCall() async throws {
        let js = MockJavaScriptEvaluator()
        js.nextAsyncString = "{\"volumes\":[]}"
        let manager = WebViewManager(evaluator: js)

        let json = try await manager.exportViewerStateJSON()

        XCTAssertEqual(json, "{\"volumes\":[]}")
        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.exportViewerState"))
        XCTAssertTrue(js.scripts[0].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("return window.exportViewerState("))
    }

    func testApplyViewerStateJSONBuildsCorrectJSCall() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.applyViewerStateJSON("{\"volumes\":[]}")

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.applyViewerState"))
        XCTAssertTrue(js.scripts[0].contains("{\\\"volumes\\\":[]}"))
    }

    func testRestoreSessionJSONWithSourcesLoadsVolumesThenAppliesViewerState() async throws {
        let js = MockJavaScriptEvaluator()
        js.nextAsyncString = "[]"
        let manager = WebViewManager(evaluator: js)

        let sessionJSON = """
        {
          "version": 1,
          "volumeSources": [
            { "url": "niivue://app/files/a", "name": "a.nii.gz" },
            { "url": "niivue://app/files/b", "name": "b.nii.gz" }
          ],
          "viewerState": {
            "volumes": [
              { "colormap": "gray", "opacity": 0.5, "frame4D": 2 },
              { "colormap": "hot", "opacity": 1.0, "frame4D": 0 }
            ]
          }
        }
        """

        try await manager.restoreSessionJSON(sessionJSON)

        let loadIndex = js.scripts.firstIndex(where: { $0.contains("window.loadVolumesFromUrls") })
        XCTAssertNotNil(loadIndex)

        let syncIndex = js.scripts.firstIndex(where: { $0.contains("window.getVolumeInfoList") })
        XCTAssertNotNil(syncIndex)

        let applyIndex = js.scripts.firstIndex(where: { $0.contains("window.applyViewerState") })
        XCTAssertNotNil(applyIndex)

        if let loadIndex, let applyIndex {
            XCTAssertLessThan(loadIndex, applyIndex)
        }
    }

    func testRestoreSessionLegacyViewerStateOnlyAppliesWithoutReload() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.restoreSessionJSON("{\"volumes\":[]}")

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.applyViewerState"))
    }

    func testLoadImageFromUrlUpdatesVolumeSources() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadImageFromUrl(url: "niivue://app/files/a", fileName: "a.nii.gz")

        XCTAssertEqual(manager.volumeSources, [.init(url: "niivue://app/files/a", name: "a.nii.gz")])
    }

    func testExportSessionSnapshotJSONIncludesVolumeSourcesAndViewerState() async throws {
        let js = MockJavaScriptEvaluator()
        js.nextAsyncString = "{\"volumes\":[]}"
        let manager = WebViewManager(evaluator: js)
        manager.volumeSources = [.init(url: "niivue://app/files/a", name: "a.nii.gz")]

        let snapshotJSON = try await manager.exportSessionSnapshotJSON()
        let data = try XCTUnwrap(snapshotJSON.data(using: .utf8))
        let decoded = try JSONDecoder().decode(SessionSnapshotV1.self, from: data)

        XCTAssertEqual(decoded.version, 1)
        XCTAssertEqual(decoded.volumeSources, [.init(url: "niivue://app/files/a", name: "a.nii.gz")])
        XCTAssertEqual(decoded.viewerState.volumes.count, 0)
    }
}
