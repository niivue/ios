//
//  SegmentationCommandTests.swift
//  NiiVueTests
//
//  Phase 2 Task 5: Segmentation/Draw Tooling Pack
//

import XCTest
import SwiftUI
import UIKit
@testable import NiiVue

@MainActor
final class SegmentationCommandTests: XCTestCase {
    func testUndoCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.drawUndo()
        XCTAssertTrue(js.scripts[0].contains("drawUndo"))
    }

    func testSetDrawOpacityCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.setDrawOpacity(opacity: 0.25)
        XCTAssertTrue(js.scripts[0].contains("setDrawOpacity"))
        XCTAssertTrue(js.scripts[0].contains("0.25"))
    }

    func testSetDrawColormapCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.setDrawColormap(colormap: "hot")
        XCTAssertTrue(js.scripts[0].contains("setDrawColormap"))
        XCTAssertTrue(js.scripts[0].contains("\"hot\""))
    }

    func testSetClickToSegmentEnabledCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.setClickToSegmentEnabled(enabled: true)
        XCTAssertTrue(js.scripts[0].contains("setClickToSegmentEnabled"))
        XCTAssertTrue(js.scripts[0].contains("true"))
    }

    // MARK: - Phase 2 UI: Segmentation assets classification

    func testSegmentationAssetClassifierTreatsNiftiAsVolume() throws {
        XCTAssertEqual(
            SegmentationAssetClassifier.classify(url: URL(fileURLWithPath: "/tmp/mask.nii")),
            .volume
        )
        XCTAssertEqual(
            SegmentationAssetClassifier.classify(url: URL(fileURLWithPath: "/tmp/mask.nii.gz")),
            .volume
        )
    }

    func testSegmentationAssetClassifierTreatsNiiVueMeshExtensionsAsMesh() throws {
        XCTAssertEqual(
            SegmentationAssetClassifier.classify(url: URL(fileURLWithPath: "/tmp/surf.gii")),
            .mesh
        )
        XCTAssertEqual(
            SegmentationAssetClassifier.classify(url: URL(fileURLWithPath: "/tmp/surf.mz3")),
            .mesh
        )
    }

    func testSegmentationAssetClassifierRejectsUnsupportedExtensions() throws {
        XCTAssertEqual(
            SegmentationAssetClassifier.classify(url: URL(fileURLWithPath: "/tmp/readme.txt")),
            .unsupported
        )
    }

    func testSegmentationAssetImportPlannerBuildsSpecsFromImportedFiles() throws {
        let imported: [FileImportService.ImportedFile] = [
            .init(id: "111", originalFileName: "mask.nii", localURL: URL(fileURLWithPath: "/tmp/mask.nii")),
            .init(id: "222", originalFileName: "surf.gii", localURL: URL(fileURLWithPath: "/tmp/surf.gii")),
            .init(id: "333", originalFileName: "notes.txt", localURL: URL(fileURLWithPath: "/tmp/notes.txt")),
        ]

        let plan = SegmentationAssetImportPlanner.plan(importedFiles: imported)

        XCTAssertEqual(plan.volumeSpecs.count, 1)
        XCTAssertEqual(plan.volumeSpecs[0].url, "niivue://app/files/111")
        XCTAssertEqual(plan.volumeSpecs[0].name, "mask.nii")

        XCTAssertEqual(plan.meshSpecs.count, 1)
        XCTAssertEqual(plan.meshSpecs[0].url, "niivue://app/files/222")
        XCTAssertEqual(plan.meshSpecs[0].name, "surf.gii")

        XCTAssertEqual(plan.unsupportedFileNames, ["notes.txt"])
    }

    // MARK: - Phase 2 UI: Multi-select document picker (segmentation assets only)

    func testDocumentPickerMultipleSetsAllowsMultipleSelection() {
        final class Delegate: NSObject, UIDocumentPickerDelegate {}
        let picker = DocumentPickerMultiple.makePicker(delegate: Delegate())
        XCTAssertTrue(picker.allowsMultipleSelection)
    }

    func testDocumentPickerMultipleCoordinatorPassesAllPickedURLsAndDismisses() {
        var isPresented = true
        var pickedURLs: [URL] = []

        let picker = DocumentPickerMultiple(
            presented: Binding(get: { isPresented }, set: { isPresented = $0 }),
            onPick: { pickedURLs = $0 }
        )
        let coordinator = picker.makeCoordinator()

        let controller = UIDocumentPickerViewController(forOpeningContentTypes: [], asCopy: true)
        let url1 = URL(fileURLWithPath: "/tmp/a.nii")
        let url2 = URL(fileURLWithPath: "/tmp/b.gii")

        coordinator.documentPicker(controller, didPickDocumentsAt: [url1, url2])

        XCTAssertEqual(pickedURLs, [url1, url2])
        XCTAssertFalse(isPresented)
    }

    func testSegmentationAssetImportExecutorCallsJSForVolumesThenMeshes() async throws {
        let js = MockJavaScriptEvaluator()
        js.nextAsyncString = "[]"
        let manager = WebViewManager(evaluator: js)

        let plan = SegmentationAssetImportPlan(
            volumeSpecs: [(url: "niivue://app/files/111", name: "mask.nii")],
            meshSpecs: [(url: "niivue://app/files/222", name: "surf.gii")],
            unsupportedFileNames: []
        )

        try await SegmentationAssetImportExecutor.execute(plan: plan, webViewManager: manager)

        let addIndex = try XCTUnwrap(js.scripts.firstIndex(where: { $0.contains("window.addVolumesFromUrls") }))
        let meshIndex = try XCTUnwrap(js.scripts.firstIndex(where: { $0.contains("window.loadMeshesFromUrls") }))
        XCTAssertLessThan(addIndex, meshIndex)
    }
}
