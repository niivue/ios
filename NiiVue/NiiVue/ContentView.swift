//
//  ContentView.swift
//  NiiVue
//
//  Created by Taylor Hanayik on 11/04/2024.
//  Task 4: Refactored to use new WebViewManager with async/await
//  Task 6: Added loading/error overlay
//

import SwiftUI
import WebKit
import Foundation
import UniformTypeIdentifiers

typealias MessageCallback = (String) -> Void

enum SegmentationAssetKind: Equatable {
    case mesh
    case volume
    case unsupported
}

struct SegmentationAssetClassifier {
    private static let meshExtensions: Set<String> = [
        "asc", "byu", "dfs", "fsm", "pial", "orig", "inflated", "smoothwm", "sphere", "white",
        "g", "geo", "gii", "ico", "mz3", "nv", "obj", "off", "ply", "srf", "stl",
        "tck", "tract", "tri", "trk", "tt", "trx", "vtk", "wrl", "x3d", "jcon", "json"
    ]

    private static let volumeExtensions: Set<String> = ["nii"]

    // Includes bitmap images that Niivue can load as images (used as "textures" in some workflows).
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "bmp", "tif", "tiff"]

    static func classify(url: URL) -> SegmentationAssetKind {
        let fileName = url.lastPathComponent.lowercased()
        if fileName.hasSuffix(".nii.gz") {
            return .volume
        }

        let ext = url.pathExtension.lowercased()
        if volumeExtensions.contains(ext) {
            return .volume
        }
        if meshExtensions.contains(ext) {
            return .mesh
        }
        if imageExtensions.contains(ext) {
            return .volume
        }
        return .unsupported
    }
}

struct SegmentationAssetImportPlan {
    let volumeSpecs: [(url: String, name: String)]
    let meshSpecs: [(url: String, name: String)]
    let unsupportedFileNames: [String]
}

struct SegmentationAssetImportPlanner {
    static func plan(importedFiles: [FileImportService.ImportedFile]) -> SegmentationAssetImportPlan {
        var volumeSpecs: [(url: String, name: String)] = []
        var meshSpecs: [(url: String, name: String)] = []
        var unsupportedFileNames: [String] = []

        for imported in importedFiles {
            let kind = SegmentationAssetClassifier.classify(url: imported.localURL)
            switch kind {
            case .volume:
                volumeSpecs.append((url: "niivue://app/files/\(imported.id)", name: imported.originalFileName))
            case .mesh:
                meshSpecs.append((url: "niivue://app/files/\(imported.id)", name: imported.originalFileName))
            case .unsupported:
                unsupportedFileNames.append(imported.originalFileName)
            }
        }

        return SegmentationAssetImportPlan(
            volumeSpecs: volumeSpecs,
            meshSpecs: meshSpecs,
            unsupportedFileNames: unsupportedFileNames
        )
    }
}

struct SegmentationAssetImportExecutor {
    static func execute(plan: SegmentationAssetImportPlan, webViewManager: WebViewManager) async throws {
        if !plan.volumeSpecs.isEmpty {
            try await webViewManager.addVolumesFromUrls(plan.volumeSpecs)
        }

        if !plan.meshSpecs.isEmpty {
            try await webViewManager.loadMeshesFromUrls(plan.meshSpecs)
        }
    }
}

/// A tiny UIKit-backed accessibility element used to reliably expose an `accessibilityIdentifier`
/// for UI tests (SwiftUI containers like `VStack` may not surface as `otherElements`).
struct AccessibilityMarkerView: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = identifier
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.accessibilityIdentifier = identifier
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var presented: Bool // To control the presentation state
    var onPick: (URL) -> Void // Closure to handle the picked document

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // This function can be used to update the view when SwiftUI state changes.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ documentPicker: DocumentPicker) {
            self.parent = documentPicker
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url) // Call the closure with the picked document URL
            parent.presented = false // Dismiss the picker
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.presented = false // Dismiss the picker when cancelled
        }

        // Helper function to check if the URL has a valid file extension
        private func isValidFileType(url: URL) -> Bool {
            let validExtensions = ["nii", "nii.gz"]
            return validExtensions.contains(where: url.lastPathComponent.lowercased().hasSuffix)
        }
    }
}

struct DocumentPickerMultiple: UIViewControllerRepresentable {
    @Binding var presented: Bool
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        Self.makePicker(delegate: context.coordinator)
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No-op.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    static func makePicker(delegate: UIDocumentPickerDelegate) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.delegate = delegate
        return picker
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPickerMultiple

        init(_ documentPicker: DocumentPickerMultiple) {
            self.parent = documentPicker
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
            parent.presented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.presented = false
        }
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var manager: WebViewManager

    func makeUIView(context: Context) -> WKWebView {
        return manager.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // This function can be used to update the view when SwiftUI state changes.
    }
}


struct ContentView: View {
    @EnvironmentObject var sharedData: SharedData
    @StateObject private var webViewManager = WebViewManager()

    @State private var documentPickerPresented = false
    @State private var segmentationAssetsPickerPresented = false
    @State private var segmentationImportInProgress = false
    @State private var segmentationImportStatusMessage: String?
    @State private var settingsSheetPresented = false
    @State private var volumesSheetPresented = false
    @State private var volumesSheetStatusMessage: String?
    @State private var availableVolumeColormaps: [String] = []
    @State private var volumeOpacityByID: [String: Double] = [:]
    @State private var volumeColormapByID: [String: String] = [:]
    @State private var volumeFrame4DByID: [String: Int] = [:]
    @State private var segmentationSheetPresented = false
    @State private var segmentationToolStatusMessage: String?

    // Phase 2 Task 9: DICOM import
    @State private var dicomPickerPresented = false
    @State private var dicomImportInProgress = false
    @State private var dicomImportStatusMessage: String?
    private let dicomSeriesStore = DicomSeriesStore()
    @State private var drawOpacity: Double = 1.0
    @State private var drawColormap: String = "gray"
    @State private var clickToSegmentEnabled = false
    @State private var sessionsSheetPresented = false
    @State private var sessionsStatusMessage: String?
    @State private var sessionsInProgress = false
    @State private var sessionIDs: [String] = []
    @State private var pickedDocumentURL: URL?
    @State private var base64EncodedString: String?
    @State private var sliceType = SliceTypes.Multiplanar.rawValue // default sliceType is multiplanar
    @State private var layout = LayoutTypes.Auto.rawValue // the default is Auto
    @State private var dragType = DragTypes.Contrast.rawValue // the default is Contrast
    @State private var show3dCrosshair = false
    @State private var show2dCrosshair = true
    @State private var penValue = PenTypes.Red.rawValue // default is red
    @State private var drawingEnabled = false // can the user draw?
    @State private var isFilled = true // is the pen filled or not?
    @State private var cornerText = false // put orientation labels in the corder or not?
    @State private var orientationCube = false // by default the 3D orientation cube is hidden
    @State private var radiological = false // use radiological convention or not in Niivue
    @State private var saveFileAlert = false
    @State private var showingSaveAlert = false
    @State private var incrementText = ""
    @State private var decrementText = ""
    @State private var sliceTypeText = ""

    /// Phase 2 Task 2: Check if we should load multiple volumes for UI testing
    private var isUITestLoadMultiple: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-load-multiple")
    }

    private var isUITestSessionsTemp: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-sessions-temp")
    }

    enum SliceTypes: Int, CaseIterable, Identifiable {
        case Axial = 0
        case Coronal = 1
        case Sagittal = 2
        case Multiplanar = 3
        case Render = 4
        var id: Self { self }
    }

    enum LayoutTypes: Int, CaseIterable, Identifiable {
        case Auto = 0
        case Column = 1
        case Grid = 2
        case Row = 3
        var id: Self { self }
    }

    enum DragTypes: Int, CaseIterable, Identifiable {
        case None = 0
        case Contrast = 1
        case Measure = 2
        case Pan = 3
        case Slicer3D = 4
        var id: Self { self }
    }

    enum PenTypes: Int, CaseIterable, Identifiable {
        case Erase = 0
        case Red = 1
        case Green = 2
        case Blue = 3
        case Yellow = 4
        case Cyan = 5
        case Purple = 6
        var id: Self { self }
    }

    // detect if iOS or macOS and set the drag setting text
#if os(iOS)
    let dragLabel = "Drag action (double tap)"
#elseif os(macOS)
    let dragLabel = "Drag action (right click)"
#endif

    private let maxBase64FallbackBytes = 25 * 1024 * 1024

    private func importSegmentationAssets(from pickedURLs: [URL]) {
        Task {
            await MainActor.run {
                segmentationImportInProgress = true
                segmentationImportStatusMessage = "Importing \(pickedURLs.count) file(s)…"
            }

            defer {
                Task { @MainActor in
                    segmentationImportInProgress = false
                }
            }

            let libraryDir = FileImportService.defaultLibraryDirectory()
            do {
                try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
            } catch {
                await MainActor.run {
                    segmentationImportStatusMessage = "Failed to create Library directory: \(error.localizedDescription)"
                }
                return
            }

            let fileImportService = FileImportService()
            var importedFiles: [FileImportService.ImportedFile] = []
            var failedImports: [String] = []

            for url in pickedURLs {
                do {
                    let imported = try await fileImportService.importDocument(at: url, destinationDirectory: libraryDir)
                    importedFiles.append(imported)
                    await webViewManager.importedFileStore.register(importedFile: imported)
                } catch {
                    failedImports.append(url.lastPathComponent)
                }
            }

            let plan = SegmentationAssetImportPlanner.plan(importedFiles: importedFiles)
            do {
                try await SegmentationAssetImportExecutor.execute(plan: plan, webViewManager: webViewManager)
            } catch {
                await MainActor.run {
                    segmentationImportStatusMessage = "Failed to load assets into Niivue: \(error.localizedDescription)"
                }
                return
            }

            let loadedCount = plan.volumeSpecs.count + plan.meshSpecs.count
            var summary = "Imported \(importedFiles.count)/\(pickedURLs.count) file(s). Loaded \(loadedCount) asset(s)."
            if !plan.unsupportedFileNames.isEmpty {
                summary.append(" Unsupported: \(plan.unsupportedFileNames.joined(separator: ", ")).")
            }
            if !failedImports.isEmpty {
                summary.append(" Failed: \(failedImports.joined(separator: ", ")).")
            }

            await MainActor.run {
                segmentationImportStatusMessage = summary
            }
        }
    }

    // MARK: - Phase 2 Task 9: DICOM import

    private func importDicomSeries(from pickedURLs: [URL]) {
        Task {
            await MainActor.run {
                dicomImportInProgress = true
                dicomImportStatusMessage = "Importing \(pickedURLs.count) DICOM file(s)…"
            }

            defer {
                Task { @MainActor in
                    dicomImportInProgress = false
                }
            }

            // Filter to DICOM files (.dcm, .dicom, or files without extension)
            let dicomURLs = pickedURLs.filter { url in
                let ext = url.pathExtension.lowercased()
                return ext == "dcm" || ext == "dicom" || ext.isEmpty
            }

            guard !dicomURLs.isEmpty else {
                await MainActor.run {
                    dicomImportStatusMessage = "No DICOM files found in selection."
                }
                return
            }

            let libraryDir = FileImportService.defaultLibraryDirectory()
            do {
                try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
            } catch {
                await MainActor.run {
                    dicomImportStatusMessage = "Failed to create Library directory: \(error.localizedDescription)"
                }
                return
            }

            let fileImportService = FileImportService()
            var importedFileURLs: [URL] = []
            var failedImports: [String] = []

            for url in dicomURLs {
                do {
                    let imported = try await fileImportService.importDocument(at: url, destinationDirectory: libraryDir)
                    await webViewManager.importedFileStore.register(importedFile: imported)
                    importedFileURLs.append(imported.localURL)
                } catch {
                    failedImports.append(url.lastPathComponent)
                }
            }

            guard !importedFileURLs.isEmpty else {
                await MainActor.run {
                    dicomImportStatusMessage = "Failed to import any DICOM files."
                }
                return
            }

            // Register the series with DicomSeriesStore
            let seriesId = await dicomSeriesStore.register(files: importedFileURLs)

            // Set the store on the URL scheme handler
            webViewManager.urlSchemeHandler.dicomSeriesStore = dicomSeriesStore

            // Load the DICOM series via manifest
            let manifestURL = "niivue://app/dicom/\(seriesId)/niivue-manifest.txt"
            do {
                try await webViewManager.loadDicomSeriesFromManifestURL(manifestURL)
                await MainActor.run {
                    dicomImportStatusMessage = "Loaded \(importedFileURLs.count) DICOM file(s)."
                }
            } catch {
                await MainActor.run {
                    dicomImportStatusMessage = "Failed to load DICOM series: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Phase 2 UI: Volume controls

    @MainActor
    private func loadVolumeColormapsIfNeeded() async {
        guard availableVolumeColormaps.isEmpty else { return }
        do {
            let colormaps = try await webViewManager.listColormaps()
            availableVolumeColormaps = colormaps.isEmpty ? ["gray"] : colormaps
        } catch {
            volumesSheetStatusMessage = "Failed to load colormaps: \(error.localizedDescription)"
            availableVolumeColormaps = ["gray"]
        }
    }

    @MainActor
    private func displayedColormap(for volumeID: String) -> String {
        volumeColormapByID[volumeID] ?? availableVolumeColormaps.first ?? "gray"
    }

    @MainActor
    private func setVolumeColormap(_ colormap: String, volumeIndex: Int, volumeID: String) {
        volumeColormapByID[volumeID] = colormap
        Task {
            do {
                try await webViewManager.setColormap(volumeIndex: volumeIndex, colormap: colormap)
            } catch {
                await MainActor.run {
                    volumesSheetStatusMessage = "Failed to set colormap: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func opacityBinding(volumeID: String, volumeIndex: Int) -> Binding<Double> {
        Binding(
            get: { volumeOpacityByID[volumeID] ?? 1.0 },
            set: { newValue in
                volumeOpacityByID[volumeID] = newValue
                Task {
                    do {
                        try await webViewManager.setOpacity(volumeIndex: volumeIndex, opacity: newValue)
                    } catch {
                        await MainActor.run {
                            volumesSheetStatusMessage = "Failed to set opacity: \(error.localizedDescription)"
                        }
                    }
                }
            }
        )
    }

    @MainActor
    private func frame4DBinding(volumeID: String, volumeIndex: Int, maxFrame: Int) -> Binding<Int> {
        Binding(
            get: { min(max(volumeFrame4DByID[volumeID] ?? 0, 0), maxFrame) },
            set: { newValue in
                let clamped = min(max(newValue, 0), maxFrame)
                volumeFrame4DByID[volumeID] = clamped
                Task {
                    do {
                        try await webViewManager.setFrame4D(volumeIndex: volumeIndex, frame: clamped)
                    } catch {
                        await MainActor.run {
                            volumesSheetStatusMessage = "Failed to set frame: \(error.localizedDescription)"
                        }
                    }
                }
            }
        )
    }

    // MARK: - Phase 2 UI: Segmentation tool controls

    @MainActor
    private func setDrawOpacity(_ opacity: Double) {
        Task {
            do {
                try await webViewManager.setDrawOpacity(opacity: opacity)
                await MainActor.run { segmentationToolStatusMessage = nil }
            } catch {
                await MainActor.run {
                    segmentationToolStatusMessage = "Failed to set draw opacity: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func setDrawColormap(_ colormap: String) {
        Task {
            do {
                try await webViewManager.setDrawColormap(colormap: colormap)
                await MainActor.run { segmentationToolStatusMessage = nil }
            } catch {
                await MainActor.run {
                    segmentationToolStatusMessage = "Failed to set draw colormap: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func setClickToSegmentEnabled(_ enabled: Bool) {
        #if DEBUG
        print("[ContentView] setClickToSegmentEnabled(\(enabled)) drawingEnabled(before)=\(drawingEnabled)")
        #endif
        // Niivue requires drawing to be enabled for click-to-segment to work (it operates on the drawing layer).
        if enabled, drawingEnabled == false {
            drawingEnabled = true
            #if DEBUG
            print("[ContentView] Auto-enabled drawing for click-to-segment")
            #endif
        }
        Task {
            do {
                try await webViewManager.setClickToSegmentEnabled(enabled: enabled)
                await MainActor.run { segmentationToolStatusMessage = nil }
            } catch {
                await MainActor.run {
                    segmentationToolStatusMessage = "Failed to set click-to-segment: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func drawUndo() {
        Task {
            do {
                try await webViewManager.drawUndo()
                await MainActor.run { segmentationToolStatusMessage = nil }
            } catch {
                await MainActor.run {
                    segmentationToolStatusMessage = "Failed to undo draw: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Phase 2 UI: Sessions

    private func sessionsDirectoryURL() -> URL {
        if isUITestSessionsTemp {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("NiiVue-UITests", isDirectory: true)
                .appendingPathComponent("Sessions", isDirectory: true)
        }
        return SessionStore.defaultSessionsDirectory()
    }

    @MainActor
    private func resetSessionsDirectoryForUITestsIfNeeded() {
        guard isUITestSessionsTemp else { return }
        let dir = sessionsDirectoryURL()
        do {
            try? FileManager.default.removeItem(at: dir)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            sessionsStatusMessage = "Failed to reset sessions directory: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func refreshSessionsList() {
        Task {
            do {
                let store = SessionStore(sessionsDirectory: sessionsDirectoryURL())
                let ids = try await store.list()
                await MainActor.run {
                    sessionIDs = ids
                }
            } catch {
                await MainActor.run {
                    sessionsStatusMessage = "Failed to list sessions: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func saveSession() {
        sessionsInProgress = true
        Task {
            defer {
                Task { @MainActor in sessionsInProgress = false }
            }
            do {
                let json = try await webViewManager.exportSessionSnapshotJSON()
                let store = SessionStore(sessionsDirectory: sessionsDirectoryURL())
                let id = try await store.save(json: json)
                let ids = try await store.list()
                await MainActor.run {
                    sessionIDs = ids
                    sessionsStatusMessage = "Saved session \(id.prefix(8))"
                }
            } catch {
                await MainActor.run {
                    sessionsStatusMessage = "Failed to save session: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func applySession(id: String) {
        sessionsInProgress = true
        Task {
            defer {
                Task { @MainActor in sessionsInProgress = false }
            }
            do {
                let store = SessionStore(sessionsDirectory: sessionsDirectoryURL())
                let json = try await store.load(id: id)
                try await webViewManager.restoreSessionJSON(json)
                await MainActor.run {
                    sessionsStatusMessage = "Applied session \(id.prefix(8))"
                }
            } catch {
                await MainActor.run {
                    sessionsStatusMessage = "Failed to apply session: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func deleteSession(id: String) {
        sessionsInProgress = true
        Task {
            defer {
                Task { @MainActor in sessionsInProgress = false }
            }
            do {
                let store = SessionStore(sessionsDirectory: sessionsDirectoryURL())
                try await store.delete(id: id)
                let ids = try await store.list()
                await MainActor.run {
                    sessionIDs = ids
                    sessionsStatusMessage = "Deleted session \(id.prefix(8))"
                }
            } catch {
                await MainActor.run {
                    sessionsStatusMessage = "Failed to delete session: \(error.localizedDescription)"
                }
            }
        }
    }

    func incrementSlice() {
        Task {
            do {
                if sliceType == SliceTypes.Axial.rawValue {
                    try await webViewManager.moveCrosshairInVox(0, 0, 1)
                } else if sliceType == SliceTypes.Coronal.rawValue {
                    try await webViewManager.moveCrosshairInVox(0, 1, 0)
                } else if sliceType == SliceTypes.Sagittal.rawValue {
                    try await webViewManager.moveCrosshairInVox(1, 0, 0)
                }
            } catch {
                print("Error incrementing slice: \(error)")
            }
        }
    }

    func decrementSlice() {
        Task {
            do {
                if sliceType == SliceTypes.Axial.rawValue {
                    try await webViewManager.moveCrosshairInVox(0, 0, -1)
                } else if sliceType == SliceTypes.Coronal.rawValue {
                    try await webViewManager.moveCrosshairInVox(0, -1, 0)
                } else if sliceType == SliceTypes.Sagittal.rawValue {
                    try await webViewManager.moveCrosshairInVox(-1, 0, 0)
                }
            } catch {
                print("Error decrementing slice: \(error)")
            }
        }
    }

    func rotateSliceType() {
        sliceType = (sliceType + 1) % 3
    }

    var shareButton: some View {
        Button(action: {
            Task {
                do {
                    if let base64Drawing = try await webViewManager.saveDrawing() {
                        // Save the drawing to disk
                        let date = Date()
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "YYYY-MM-dd_HH-mm-ss"
                        let dateString = dateFormatter.string(from: date) + ".nii.gz"
                        let fileName = pickedDocumentURL?.lastPathComponent ?? dateString

                        // Decode and save
                        if let data = Data(base64Encoded: base64Drawing) {
                            let url = URL.documentsDirectory.appendingPathComponent("drawing_\(dateString)_\(fileName)")
                            try data.write(to: url, options: [.atomic, .completeFileProtection])
                            print("Drawing saved to: \(url.path)")
                        }
                        showingSaveAlert = true
                    }
                } catch {
                    print("Error saving drawing: \(error)")
                }
            }
        })
        {
            Image(systemName: "square.and.arrow.up")
                .padding()
                .foregroundColor(.white)
        }
        .alert("Drawing saved to app folder", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: - HUD Overlay (Phase 2 Task 1)

    @ViewBuilder
    var hudOverlay: some View {
        if let locationString = webViewManager.lastLocationString {
            VStack {
                HStack {
                    Text(locationString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .accessibilityIdentifier("niivue.hud")
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Loading Overlay (Task 6)

    @ViewBuilder
    var loadingOverlay: some View {
        if !webViewManager.isReady && webViewManager.lastErrorMessage == nil {
            ZStack {
                Color.black.opacity(0.7)
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundColor(.white)
                }
            }
            .accessibilityIdentifier("niivue.loadingOverlay")
        } else if let errorMessage = webViewManager.lastErrorMessage {
            ZStack {
                Color.black.opacity(0.9)
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        webViewManager.reload()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
            }
            .accessibilityIdentifier("niivue.errorOverlay")
        }
    }

    var body: some View {
        VStack {
            HStack {
                if drawingEnabled {
                    shareButton
                }

                // show the name of the opened file if it is a truthy value
                // -------------------------------------------------------------
                if let url = pickedDocumentURL {
                    Text("\(url.lastPathComponent)")
                        .foregroundStyle(.white)
                }
                // -------------------------------------------------------------
                Spacer() // Pushes the button to the right, and text to the left
                // -------------------------------------------------------------
                Button(action: {
                    drawingEnabled = false
                    documentPickerPresented = true
                })
                {
                    Image(systemName: "plus")
                        .padding()
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("niivue.addImage")
                .sheet(isPresented: $documentPickerPresented) {
                    DocumentPicker(presented: $documentPickerPresented) { url in
                        // Task 12: URL-based loading for imported files
                        Task {
                            var importedFile: FileImportService.ImportedFile?
                            do {
                                // Create library directory if needed
                                let libraryDir = FileImportService.defaultLibraryDirectory()
                                try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)

                                // Import the file (asCopy: true already creates a temp copy)
                                let fileImportService = FileImportService()
                                let imported = try await fileImportService.importDocument(
                                    at: url,
                                    destinationDirectory: libraryDir
                                )
                                importedFile = imported

                                // Register with the store for URL lookups
                                await webViewManager.importedFileStore.register(importedFile: imported)

                                // Update UI state
                                await MainActor.run {
                                    pickedDocumentURL = imported.localURL
                                }

                                // Load via URL instead of base64 (eliminates memory overhead)
                                let niivueURL = "niivue://app/files/\(imported.id)"
                                try await webViewManager.loadImageFromUrl(url: niivueURL, fileName: imported.originalFileName)
                            } catch {
                                print("Error importing file: \(error)")

                                let fallbackURL = importedFile?.localURL ?? url
                                let maxBytes = maxBase64FallbackBytes
                                let encodedString = await Task.detached(priority: .userInitiated) {
                                    Base64FileEncoder.encodeFileToBase64(url: fallbackURL, maxBytes: maxBytes)
                                }.value

                                // Fallback to base64 loading if URL-based fails (limited by maxBase64FallbackBytes)
                                await MainActor.run {
                                    pickedDocumentURL = fallbackURL
                                    if let encodedString {
                                        base64EncodedString = encodedString
                                    } else {
                                        webViewManager.lastErrorMessage = "Failed to load file (URL-based load failed; base64 fallback skipped)."
                                    }
                                }
                            }
                        }
                    }
                } // add image (plus) sheet end
                // -------------------------------------------------------------
                // adjust settings button
                Button(action: {
                    settingsSheetPresented = true
                })
                {
                    Image(systemName: "slider.horizontal.3")
                        .padding()
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("niivue.settings")
                .sheet(isPresented: $settingsSheetPresented) {
                    ScrollView {

                        VStack(alignment: .leading) {
                            //-----------------------------------------------------
                            // dismiss button in top right corner of sheet
                            HStack {
                                Spacer() // push button to the right (ios guidelines for sheets)
                                Button("Dismiss") {
                                    settingsSheetPresented.toggle()
                                }
                                .padding()
                            }
                            .padding()
                            //-----------------------------------------------------
                            // picker for the slice type
                            HStack {
                                Text("View type")
                                    .padding()
                                Spacer()
                                Picker("View mode", selection: $sliceType) {
                                    Text("Axial").tag(SliceTypes.Axial.rawValue)
                                    Text("Coronal").tag(SliceTypes.Coronal.rawValue)
                                    Text("Sagittal").tag(SliceTypes.Sagittal.rawValue)
                                    Text("Multiplanar").tag(SliceTypes.Multiplanar.rawValue)
                                    Text("Render").tag(SliceTypes.Render.rawValue)
                                }
                                .pickerStyle(.menu)
                                .accessibilityIdentifier("niivue.settings.viewType")
                                .padding()
                            }
                            //------------------------------------------------------
                            // picker for the layout type of multiplanar
                            HStack {
                                Text("Multiplanar layout ")
                                    .padding()
                                Spacer()
                                Picker("layout mode", selection: $layout) {
                                    Text("Auto").tag(LayoutTypes.Auto.rawValue)
                                    Text("Column").tag(LayoutTypes.Column.rawValue)
                                    Text("Grid").tag(LayoutTypes.Grid.rawValue)
                                    Text("Row").tag(LayoutTypes.Row.rawValue)
                                }
                                .pickerStyle(.menu)
                                .padding()
                            }
                            //------------------------------------------------------
                            // picker for the drag type
                            HStack {
                                Text(dragLabel)
                                    .padding()
                                Spacer()
                                Picker("Drag mode", selection: $dragType) {
                                    Text("None").tag(DragTypes.None.rawValue)
                                    Text("Contrast").tag(DragTypes.Contrast.rawValue)
                                    Text("Measure").tag(DragTypes.Measure.rawValue)
                                    Text("Pan").tag(DragTypes.Pan.rawValue)
                                    Text("Slicer3D").tag(DragTypes.Slicer3D.rawValue)
                                }
                                .pickerStyle(.menu)
                                .padding()
                            }
                            //------------------------------------------------------
                            // picker for the pen type
                            HStack {
                                Text("Pen type")
                                    .padding()
                                Spacer()
                                Picker("Pen type", selection: $penValue) {
                                    Label("Eraser", systemImage: "eraser").tag(PenTypes.Erase.rawValue)
                                    Label("Red", systemImage: "pencil").tag(PenTypes.Red.rawValue)
                                    Label("Green", systemImage: "pencil").tag(PenTypes.Green.rawValue)
                                    Label("Blue", systemImage: "pencil").tag(PenTypes.Blue.rawValue)
                                    Label("Cyan", systemImage: "pencil").tag(PenTypes.Cyan.rawValue)
                                    Label("Yellow", systemImage: "pencil").tag(PenTypes.Yellow.rawValue)
                                    Label("Purple", systemImage: "pencil").tag(PenTypes.Purple.rawValue)
                                }
                                .pickerStyle(.menu)
                                .padding()
                            }
                            //-------------------------------------------------------
                            // drawing enabled switch
                            HStack {
                                Toggle("Drawing enabled", isOn: $drawingEnabled)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // show 3d crosshair switch
                            HStack {
                                Toggle("3D crosshair", isOn: $show3dCrosshair)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // 2d crosshair switch
                            HStack {
                                Toggle("2D crosshair", isOn: $show2dCrosshair)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // filled pen switch
                            HStack {
                                Toggle("Auto fill pen", isOn: $isFilled)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // Corner labels switch
                            HStack {
                                Toggle("Corner text", isOn: $cornerText)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // orientation cube switch
                            HStack {
                                Toggle("Orientation cube", isOn: $orientationCube)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // radiological switch
                            HStack {
                                Toggle("Radiological convention", isOn: $radiological)
                                    .padding()
                            }

                            Spacer() // push content to top to the entire sheet layout is from top to bottom (default is centered)
                        }
                        // allow both medium (half height) and large (full height) sheets
                        // iphone: sheets can be medium or large
                        // ipad: detents are ignored. Sheets can only be large
                        // macOS: sheets are more like modal views (rectangles) centered in the app window
                        .presentationDetents([.medium, .large])
                        .presentationContentInteraction(.scrolls)
                    } // Vstack in sheet
                }

                // Phase 2 UI: Dedicated Volumes sheet
                Button(action: {
                    volumesSheetPresented = true
                }) {
                    Image(systemName: "square.stack.3d.up")
                        .padding()
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("niivue.volumes")
                .sheet(isPresented: $volumesSheetPresented) {
                    NavigationStack {
                        VStack(spacing: 0) {
                            AccessibilityMarkerView(identifier: "niivue.volumesSheet")
                                .frame(width: 1, height: 1)
                                .opacity(0.01)

                            if let message = volumesSheetStatusMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                                    .padding(.top, 8)
                                    .accessibilityIdentifier("niivue.volumesStatus")
                            }

                            List {
                                if webViewManager.volumes.isEmpty {
                                    Text("No volumes loaded")
                                        .foregroundStyle(.secondary)
                                } else {
                                    ForEach(Array(webViewManager.volumes.enumerated()), id: \.element.id) { index, volume in
                                        VStack(alignment: .leading, spacing: 12) {
                                            Text(volume.name)
                                                .font(.headline)
                                                .lineLimit(2)

                                            HStack {
                                                Text("Colormap")
                                                Spacer()
                                                Menu {
                                                    ForEach(availableVolumeColormaps, id: \.self) { colormap in
                                                        Button(colormap) {
                                                            setVolumeColormap(colormap, volumeIndex: index, volumeID: volume.id)
                                                        }
                                                    }
                                                } label: {
                                                    Text(displayedColormap(for: volume.id))
                                                        .lineLimit(1)
                                                }
                                                .accessibilityIdentifier("niivue.volume.colormap.\(index)")
                                            }

                                            VStack(alignment: .leading, spacing: 6) {
                                                HStack {
                                                    Text("Opacity")
                                                    Spacer()
                                                    Text(String(format: "%.2f", volumeOpacityByID[volume.id] ?? 1.0))
                                                        .font(.system(.caption, design: .monospaced))
                                                        .foregroundStyle(.secondary)
                                                }

                                                Slider(value: opacityBinding(volumeID: volume.id, volumeIndex: index), in: 0...1)
                                                    .accessibilityIdentifier("niivue.volume.opacity.\(index)")
                                            }

                                            if volume.nFrame4D > 1 {
                                                let binding = frame4DBinding(
                                                    volumeID: volume.id,
                                                    volumeIndex: index,
                                                    maxFrame: volume.nFrame4D - 1
                                                )
                                                Stepper(
                                                    "Frame \(binding.wrappedValue)",
                                                    value: binding,
                                                    in: 0...(volume.nFrame4D - 1)
                                                )
                                                .accessibilityIdentifier("niivue.volume.frame4d.\(index)")
                                            }
                                        }
                                        .padding(.vertical, 8)
                                    }
                                }
                            }
                            .listStyle(.insetGrouped)
                        }
                        .navigationTitle("Volumes")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { volumesSheetPresented = false }
                            }
                        }
                        .task {
                            await loadVolumeColormapsIfNeeded()
                        }
                    }
                }

                // Phase 2 UI: Dedicated Segmentation sheet
                Button(action: {
                    segmentationSheetPresented = true
                }) {
                    Image(systemName: "pencil.and.outline")
                        .padding()
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("niivue.segmentation")
                .sheet(isPresented: $segmentationSheetPresented) {
                    NavigationStack {
                        VStack(spacing: 0) {
                            AccessibilityMarkerView(identifier: "niivue.segmentationSheet")
                                .frame(width: 1, height: 1)
                                .opacity(0.01)
                            Form {
                                Section {
                                    Button("Import Segmentation Assets") {
                                        segmentationAssetsPickerPresented = true
                                    }
                                    .accessibilityIdentifier("niivue.importSegmentationAssets")
                                    .disabled(segmentationImportInProgress)

                                    Button("Import DICOM Series") {
                                        dicomPickerPresented = true
                                    }
                                    .accessibilityIdentifier("niivue.importDicom")
                                    .disabled(dicomImportInProgress)

                                    if dicomImportInProgress {
                                        ProgressView("Importing DICOM...")
                                            .accessibilityIdentifier("niivue.dicomImportProgress")
                                    }

                                    if let message = dicomImportStatusMessage {
                                        Text(message)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                            .accessibilityIdentifier("niivue.dicomImportStatus")
                                    }

                                    if segmentationImportInProgress {
                                        ProgressView()
                                            .accessibilityIdentifier("niivue.segmentationImportProgress")
                                    }

                                    if let message = segmentationImportStatusMessage {
                                        Text(message)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                            .accessibilityIdentifier("niivue.segmentationImportStatus")
                                    }
                                } header: {
                                    Text("Assets")
                                }

                                Section {
                                    Button("Undo") {
                                        drawUndo()
                                    }
                                    .accessibilityIdentifier("niivue.segmentation.undo")

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text("Draw opacity")
                                            Spacer()
                                            Text(String(format: "%.2f", drawOpacity))
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                        Slider(value: $drawOpacity, in: 0...1)
                                            .accessibilityIdentifier("niivue.segmentation.drawOpacity")
                                            .onChange(of: drawOpacity) { newValue in setDrawOpacity(newValue) }
                                    }

                                    HStack {
                                        Text("Draw colormap")
                                        Spacer()
                                        Menu {
                                            ForEach(availableVolumeColormaps.isEmpty ? ["gray"] : availableVolumeColormaps, id: \.self) { colormap in
                                                Button(colormap) {
                                                    drawColormap = colormap
                                                    setDrawColormap(colormap)
                                                }
                                            }
                                        } label: {
                                            Text(drawColormap)
                                                .lineLimit(1)
                                        }
                                        .accessibilityIdentifier("niivue.segmentation.drawColormap")
                                    }

                                    Toggle("Click-to-segment", isOn: $clickToSegmentEnabled)
                                        .accessibilityIdentifier("niivue.segmentation.clickToSegment")
                                        .onChange(of: clickToSegmentEnabled) { newValue in
                                            setClickToSegmentEnabled(newValue)
                                        }

                                    if let message = segmentationToolStatusMessage {
                                        Text(message)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                            .accessibilityIdentifier("niivue.segmentationToolStatus")
                                    }
                                } header: {
                                    Text("Tools")
                                }
                            }
                        }
                        .navigationTitle("Segmentation")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { segmentationSheetPresented = false }
                            }
                        }
                        .task {
                            await loadVolumeColormapsIfNeeded()
                            if availableVolumeColormaps.contains(drawColormap) == false {
                                drawColormap = availableVolumeColormaps.first ?? drawColormap
                            }
                        }
                    }
                    .sheet(isPresented: $segmentationAssetsPickerPresented) {
                        DocumentPickerMultiple(presented: $segmentationAssetsPickerPresented) { urls in
                            importSegmentationAssets(from: urls)
                        }
                    }
                    .sheet(isPresented: $dicomPickerPresented) {
                        DocumentPickerMultiple(presented: $dicomPickerPresented) { urls in
                            importDicomSeries(from: urls)
                        }
                    }
                }

                // Phase 2 UI: Dedicated Sessions sheet
                Button(action: {
                    sessionsSheetPresented = true
                }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .padding()
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("niivue.sessions")
                .sheet(isPresented: $sessionsSheetPresented) {
                    NavigationStack {
                        VStack(spacing: 0) {
                            AccessibilityMarkerView(identifier: "niivue.sessionsSheet")
                                .frame(width: 1, height: 1)
                                .opacity(0.01)

                            Form {
                                Section {
                                    HStack {
                                        Text("Saved sessions")
                                        Spacer()
                                        Text("\(sessionIDs.count)")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .accessibilityIdentifier("niivue.sessionCount")
                                    }

                                    Button("Save Session") {
                                        saveSession()
                                    }
                                    .accessibilityIdentifier("niivue.saveSession")
                                    .disabled(sessionsInProgress || !webViewManager.isReady)

                                    if sessionsInProgress {
                                        ProgressView()
                                            .accessibilityIdentifier("niivue.sessionsProgress")
                                    }

                                    if let message = sessionsStatusMessage {
                                        Text(message)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                            .accessibilityIdentifier("niivue.sessionsStatus")
                                    }
                                } header: {
                                    Text("Actions")
                                }

                                Section {
                                    if sessionIDs.isEmpty {
                                        Text("No sessions saved")
                                            .foregroundStyle(.secondary)
                                    } else {
                                        ForEach(sessionIDs, id: \.self) { id in
                                            HStack {
                                                Text(id)
                                                    .font(.system(.caption, design: .monospaced))
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.6)
                                                Spacer()
                                                Button("Apply") {
                                                    applySession(id: id)
                                                }
                                                .disabled(sessionsInProgress)
                                            }
                                            .swipeActions {
                                                Button(role: .destructive) {
                                                    deleteSession(id: id)
                                                } label: {
                                                    Label("Delete", systemImage: "trash")
                                                }
                                            }
                                        }
                                    }
                                } header: {
                                    Text("Recents")
                                }
                            }
                        }
                        .navigationTitle("Sessions")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { sessionsSheetPresented = false }
                            }
                        }
                        .task {
                            resetSessionsDirectoryForUITestsIfNeeded()
                            refreshSessionsList()
                        }
                    }
                }
            } // HStack
            .padding(.horizontal) // Adds some padding on the left and right
            .background(Color.black)
            // -------------------------------------------------------------
            // show the drawing toolbar if drawing enabled and only showing axial, sagittal, or coronal slices
            if (drawingEnabled && sliceType != SliceTypes.Multiplanar.rawValue && sliceType != SliceTypes.Render.rawValue) {
                HStack {
                    Button(action: {
                        print("rotate slice type")
                        rotateSliceType()
                    })
                    {
                        let font = Font
                            .system(size: 18)
                            .monospaced()
                        Text(sliceTypeText).bold().font(font)
                    }
                    .padding()
                    Spacer()
                    //-------------------------------------------------
                    Text(decrementText)
                        .foregroundStyle(.white)
                    Button(action: {
                        print("decrement slice")
                        decrementSlice()
                    })
                    {
                        Image(systemName: "minus.rectangle.fill")
                            .padding([.bottom, .top, .trailing], 20)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderless)
                        .controlSize(.large)
                    // --------------------------------------------------
                    Text("Slice")
                        .foregroundStyle(.white)

                    //---------------------------------------------------
                    Button(action: {
                        print("increment slice")
                        incrementSlice()
                    })
                    {
                        Image(systemName: "plus.rectangle.fill")
                            .padding([.bottom, .top, .leading], 20)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderless)
                        .controlSize(.large)
                    Text(incrementText)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal) // Adds some padding on the left and right
                .background(Color.black)
            }
            // -------------------------------------------------------------
            // show the webview with loading overlay and HUD
            ZStack {
                WebView(manager: webViewManager)
                    .onAppear {
                        webViewManager.load()
                    }
                    .background(Color.black)

                loadingOverlay
                hudOverlay

                // Phase 2 Task 2: Volume count display (shown in UI test mode for verification)
                if isUITestLoadMultiple {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text(webViewManager.isReady ? "ready" : "notReady")
                                    .accessibilityIdentifier("niivue.isReady")
                                Text("\(webViewManager.volumes.count)")
                                    .accessibilityIdentifier("niivue.volumeCount")
                                Text(webViewManager.lastErrorMessage ?? "")
                                    .accessibilityIdentifier("niivue.lastError")
                                Text(webViewManager.lastClipPlaneDepth.map { String(format: "%.3f", $0) } ?? "")
                                    .accessibilityIdentifier("niivue.clipPlaneDepth")
                            }
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.black.opacity(0.6))
                            .cornerRadius(4)
                            .padding()
                        }
                    }
                }
            }
            .padding()
        }
        // Load sample image when webview becomes ready (Task 8: event-driven, Task 12: URL-based)
        .onChange(of: webViewManager.isReady) { newValue in
            if newValue {
                Task {
                    do {
                        // Phase 2 Task 2: UI test path loads multiple volumes
                        if isUITestLoadMultiple {
                            print("[ContentView] Loading 2 volumes for UI test")
                            let sample1 = (url: "niivue://app/samples/ui-test-volume-1.nii", name: "ui-test-volume-1.nii")
                            let sample2 = (url: "niivue://app/samples/ui-test-volume-2.nii", name: "ui-test-volume-2.nii")
                            try await webViewManager.loadVolumesFromUrls([sample1, sample2])
                            print("[ContentView] loadVolumesFromUrls returned, volumes.count = \(webViewManager.volumes.count)")
                        } else {
                            // Normal path: load single demo image
                            let sampleURL = "niivue://app/samples/T1w_DEMO.nii.gz"
                            let fileName = "T1w_DEMO.nii.gz"
                            try await webViewManager.loadImageFromUrl(url: sampleURL, fileName: fileName)

                            // Update UI state to show filename
                            await MainActor.run {
                                pickedDocumentURL = Bundle.main.url(forResource: "T1w_DEMO.nii", withExtension: "gz", subdirectory: "samples")
                            }
                        }
                    } catch {
                        print("Error loading sample image: \(error)")

                        // Fallback to base64 if URL-based fails (limited by maxBase64FallbackBytes)
                        if !isUITestLoadMultiple, let url = Bundle.main.url(forResource: "T1w_DEMO.nii", withExtension: "gz", subdirectory: "samples") {
                            let maxBytes = maxBase64FallbackBytes
                            let encodedString = await Task.detached(priority: .userInitiated) {
                                Base64FileEncoder.encodeFileToBase64(url: url, maxBytes: maxBytes)
                            }.value

                            await MainActor.run {
                                pickedDocumentURL = url
                                if let encodedString {
                                    base64EncodedString = encodedString
                                } else {
                                    webViewManager.lastErrorMessage = "Failed to load bundled sample (base64 fallback skipped)."
                                }
                            }
                        }

                        if isUITestLoadMultiple {
                            await MainActor.run {
                                webViewManager.lastErrorMessage = "UI test volume load failed: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: base64EncodedString) { newValue in
            // Call a function or handle the change
            print("Base64 string updated")
            if let safeBase64 = newValue, let fileName = pickedDocumentURL?.lastPathComponent {
                Task {
                    do {
                        try await webViewManager.loadBase64Image(base64: safeBase64, fileName: fileName)
                    } catch {
                        print("Error loading base64 image: \(error)")
                    }
                }
            }
        }
        .onChange(of: sliceType) { newValue in
            print("sliceType updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setSliceType(sliceType: newValue)
                } catch {
                    print("Error setting slice type: \(error)")
                }
            }
            if (newValue == SliceTypes.Axial.rawValue) {
                incrementText = "S" // superior
                decrementText = "I" // inferior
                sliceTypeText = "A"
            } else if (newValue == SliceTypes.Coronal.rawValue) {
                incrementText = "A" // anterior
                decrementText = "P" // posterior
                sliceTypeText = "C"
            } else if (newValue == SliceTypes.Sagittal.rawValue) {
                incrementText = "R" // right
                decrementText = "L" // left
                sliceTypeText = "S"
            }
        }
        .onChange(of: layout) { newValue in
            print("layout updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setLayout(layout: newValue)
                } catch {
                    print("Error setting layout: \(error)")
                }
            }
        }
        .onChange(of: dragType) { newValue in
            print("drag type updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setDragMode(dragMode: newValue)
                } catch {
                    print("Error setting drag mode: \(error)")
                }
            }
        }
        .onChange(of: show3dCrosshair) { newValue in
            print("show3dCrosshair updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.set3dCrosshairVisible(visible: newValue)
                } catch {
                    print("Error setting 3D crosshair: \(error)")
                }
            }
        }
        .onChange(of: show2dCrosshair) { newValue in
            print("show2dCrosshair updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.set2dCrosshairVisible(visible: newValue)
                } catch {
                    print("Error setting 2D crosshair: \(error)")
                }
            }
        }
        .onChange(of: isFilled) { newValue in
            print("isFilled updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setPenValue(penValue: penValue, isFilled: newValue, drawingEnabled: drawingEnabled)
                } catch {
                    print("Error setting pen value: \(error)")
                }
            }
        }
        .onChange(of: drawingEnabled) { newValue in
            print("drawingEnabled updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setPenValue(penValue: penValue, isFilled: isFilled, drawingEnabled: newValue)
                } catch {
                    print("Error setting drawing enabled: \(error)")
                }
            }
        }
        .onChange(of: cornerText) { newValue in
            print("cornerText updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setCornerText(isCorners: newValue)
                } catch {
                    print("Error setting corner text: \(error)")
                }
            }
        }
        .onChange(of: orientationCube) { newValue in
            print("orientationCube updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setOrientationCube(isOrientationCube: newValue)
                } catch {
                    print("Error setting orientation cube: \(error)")
                }
            }
        }
        .onChange(of: radiological) { newValue in
            print("radiological updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setRadiological(isRadiological: newValue)
                } catch {
                    print("Error setting radiological: \(error)")
                }
            }
        }
        .onChange(of: penValue) { newValue in
            print("penValue updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setPenValue(penValue: newValue, isFilled: isFilled, drawingEnabled: drawingEnabled)
                } catch {
                    print("Error setting pen value: \(error)")
                }
            }
        }
        .background(Color.black)
    }
}
