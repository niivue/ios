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
import UIKit

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

// MARK: - 2D Gestures: Viewport Interaction (2-Finger Pan + Pinch Zoom)

/// Unified 2-finger navigation handler that supports **simultaneous** pan + zoom (Photos/PACS style).
/// - Pan: `offset += translation` (reset translation each step)
/// - Pinch: `scale *= recognizer.scale` (reset recognizer.scale each step), clamped to `[0.5, 10.0]`
struct ViewportInteractionHandler: UIViewRepresentable {
    enum InstallTarget: Equatable {
        case webView
        case installerView
    }

    @Binding var offset: CGSize
    @Binding var scale: CGFloat
    var installTarget: InstallTarget = .webView
    var accessibilityIdentifier: String? = nil
    var isEnabled: Bool = true
    var isOneFingerPanEnabled: Bool = true
    var simulateTwoFingerPanWithOneFinger: Bool = false
    var pinchSensitivityExponent: CGFloat = 1.0
    var onInstalled: ((String) -> Void)? = nil
    var onPanBegan: ((CGPoint) -> Void)? = nil
    var onPanChanged: ((CGPoint, CGPoint, CGSize) -> Void)? = nil
    var onPanEnded: (() -> Void)? = nil
    var onPinchBegan: ((CGPoint) -> Void)? = nil
    var onPinchChanged: ((CGPoint, CGFloat) -> Void)? = nil
    var onPinchEnded: (() -> Void)? = nil
    var onOneFingerPanBegan: ((CGPoint) -> Void)? = nil
    var onOneFingerPanChanged: ((CGPoint, CGSize, CGSize) -> Void)? = nil
    var onOneFingerPanEnded: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            offset: $offset,
            scale: $scale,
            installTarget: installTarget,
            simulateTwoFingerPanWithOneFinger: simulateTwoFingerPanWithOneFinger,
            pinchSensitivityExponent: pinchSensitivityExponent,
            onInstalled: onInstalled,
            onPanBegan: onPanBegan,
            onPanChanged: onPanChanged,
            onPanEnded: onPanEnded,
            onPinchBegan: onPinchBegan,
            onPinchChanged: onPinchChanged,
            onPinchEnded: onPinchEnded
            ,
            onOneFingerPanBegan: onOneFingerPanBegan,
            onOneFingerPanChanged: onOneFingerPanChanged,
            onOneFingerPanEnded: onOneFingerPanEnded
        )
    }

    private final class InstallerView: UIView {
        var onDidMoveToSuperview: ((UIView?) -> Void)?

        override func didMoveToSuperview() {
            super.didMoveToSuperview()
            onDidMoveToSuperview?(superview)
        }
    }

    func makeUIView(context: Context) -> UIView {
        let view = InstallerView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = installTarget == .installerView
        if let accessibilityIdentifier {
            view.isAccessibilityElement = true
            view.accessibilityIdentifier = accessibilityIdentifier
        }
        view.onDidMoveToSuperview = { [weak coordinator = context.coordinator, weak view] _ in
            guard let view else { return }
            coordinator?.installRecognizersIfNeeded(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.isUserInteractionEnabled = installTarget == .installerView
        uiView.isAccessibilityElement = accessibilityIdentifier != nil
        uiView.accessibilityIdentifier = accessibilityIdentifier
        context.coordinator.setConfiguration(
            isEnabled: isEnabled,
            isOneFingerPanEnabled: isOneFingerPanEnabled,
            simulateTwoFingerPanWithOneFinger: simulateTwoFingerPanWithOneFinger,
            installTarget: installTarget,
            pinchSensitivityExponent: pinchSensitivityExponent
        )
        context.coordinator.syncExternalState(offset: offset, scale: scale)

        DispatchQueue.main.async { [weak coordinator = context.coordinator, weak uiView] in
            guard let coordinator, let uiView else { return }
            coordinator.installRecognizersIfNeeded(from: uiView)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let offsetBinding: Binding<CGSize>
        private let scaleBinding: Binding<CGFloat>
        private let onInstalled: ((String) -> Void)?
        private let onPanBegan: ((CGPoint) -> Void)?
        private let onPanChanged: ((CGPoint, CGPoint, CGSize) -> Void)?
        private let onPanEnded: (() -> Void)?
        private let onPinchBegan: ((CGPoint) -> Void)?
        private let onPinchChanged: ((CGPoint, CGFloat) -> Void)?
        private let onPinchEnded: (() -> Void)?
        private let onOneFingerPanBegan: ((CGPoint) -> Void)?
        private let onOneFingerPanChanged: ((CGPoint, CGSize, CGSize) -> Void)?
        private let onOneFingerPanEnded: (() -> Void)?
        private var installTarget: InstallTarget

        private weak var installedOnView: UIView?
        private var twoFingerPanRecognizer: UIPanGestureRecognizer?
        private var pinchRecognizer: UIPinchGestureRecognizer?
        private var oneFingerDragRecognizer: UILongPressGestureRecognizer?

        private var oneFingerDragStartLocation: CGPoint?
        private var oneFingerDragLastLocation: CGPoint?
        private var oneFingerDragLastTimestamp: TimeInterval?

        private var isEnabled: Bool = true
        private var isOneFingerPanEnabled: Bool = true
        private var simulateTwoFingerPanWithOneFinger: Bool = false
        private var pinchSensitivityExponent: CGFloat = 1.0
        private var lastSyncedOffset: CGSize = .zero
        private var lastSyncedScale: CGFloat = 1.0

        private let minScale: CGFloat = 0.5
        private let maxScale: CGFloat = 10.0

        init(
            offset: Binding<CGSize>,
            scale: Binding<CGFloat>,
            installTarget: InstallTarget,
            simulateTwoFingerPanWithOneFinger: Bool,
            pinchSensitivityExponent: CGFloat,
            onInstalled: ((String) -> Void)?,
            onPanBegan: ((CGPoint) -> Void)?,
            onPanChanged: ((CGPoint, CGPoint, CGSize) -> Void)?,
            onPanEnded: (() -> Void)?,
            onPinchBegan: ((CGPoint) -> Void)?,
            onPinchChanged: ((CGPoint, CGFloat) -> Void)?,
            onPinchEnded: (() -> Void)?,
            onOneFingerPanBegan: ((CGPoint) -> Void)?,
            onOneFingerPanChanged: ((CGPoint, CGSize, CGSize) -> Void)?,
            onOneFingerPanEnded: (() -> Void)?
        ) {
            self.offsetBinding = offset
            self.scaleBinding = scale
            self.installTarget = installTarget
            self.simulateTwoFingerPanWithOneFinger = simulateTwoFingerPanWithOneFinger
            self.pinchSensitivityExponent = pinchSensitivityExponent
            self.onInstalled = onInstalled
            self.onPanBegan = onPanBegan
            self.onPanChanged = onPanChanged
            self.onPanEnded = onPanEnded
            self.onPinchBegan = onPinchBegan
            self.onPinchChanged = onPinchChanged
            self.onPinchEnded = onPinchEnded
            self.onOneFingerPanBegan = onOneFingerPanBegan
            self.onOneFingerPanChanged = onOneFingerPanChanged
            self.onOneFingerPanEnded = onOneFingerPanEnded
            super.init()
            self.lastSyncedOffset = offset.wrappedValue
            self.lastSyncedScale = scale.wrappedValue
        }

        func setConfiguration(
            isEnabled: Bool,
            isOneFingerPanEnabled: Bool,
            simulateTwoFingerPanWithOneFinger: Bool,
            installTarget: InstallTarget,
            pinchSensitivityExponent: CGFloat
        ) {
            self.isEnabled = isEnabled
            self.isOneFingerPanEnabled = isOneFingerPanEnabled
            self.simulateTwoFingerPanWithOneFinger = simulateTwoFingerPanWithOneFinger
            self.installTarget = installTarget
            self.pinchSensitivityExponent = pinchSensitivityExponent
            twoFingerPanRecognizer?.isEnabled = isEnabled
            pinchRecognizer?.isEnabled = isEnabled
            oneFingerDragRecognizer?.isEnabled = isEnabled && isOneFingerPanEnabled
        }

        func syncExternalState(offset: CGSize, scale: CGFloat) {
            if offset != lastSyncedOffset {
                lastSyncedOffset = offset
            }
            if scale != lastSyncedScale {
                lastSyncedScale = scale
            }
        }

        private func findWebView(in view: UIView) -> WKWebView? {
            if let view = view as? WKWebView { return view }
            for child in view.subviews {
                if let match = findWebView(in: child) {
                    return match
                }
            }
            return nil
        }

        private func resolveInstallTarget(from installerView: UIView) -> UIView? {
            if installTarget == .installerView {
                return installerView
            }

            var current: UIView? = installerView
            for _ in 0..<12 {
                guard let currentView = current else { break }
                if let webView = findWebView(in: currentView) {
                    return webView
                }
                current = currentView.superview
            }
            return installerView.superview
        }

        func installRecognizersIfNeeded(from installerView: UIView) {
            guard let view = resolveInstallTarget(from: installerView) else { return }
            guard installedOnView !== view else { return }

            if let installedOnView {
                if let twoFingerPanRecognizer {
                    installedOnView.removeGestureRecognizer(twoFingerPanRecognizer)
                }
                if let pinchRecognizer {
                    installedOnView.removeGestureRecognizer(pinchRecognizer)
                }
                if let oneFingerDragRecognizer {
                    installedOnView.removeGestureRecognizer(oneFingerDragRecognizer)
                }
            }

            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.minimumNumberOfTouches = 2
            pan.maximumNumberOfTouches = 2
            pan.allowedScrollTypesMask = .all
            pan.cancelsTouchesInView = true
            pan.delegate = self
            view.addGestureRecognizer(pan)
            self.twoFingerPanRecognizer = pan

            let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
            pinch.cancelsTouchesInView = true
            pinch.delegate = self
            view.addGestureRecognizer(pinch)
            self.pinchRecognizer = pinch

            let oneFingerDrag = UILongPressGestureRecognizer(target: self, action: #selector(handleOneFingerDrag(_:)))
            oneFingerDrag.minimumPressDuration = 0
            oneFingerDrag.allowableMovement = 10_000
            oneFingerDrag.numberOfTouchesRequired = 1
            oneFingerDrag.cancelsTouchesInView = true
            oneFingerDrag.delegate = self
            view.addGestureRecognizer(oneFingerDrag)
            self.oneFingerDragRecognizer = oneFingerDrag

            installedOnView = view
            setConfiguration(
                isEnabled: isEnabled,
                isOneFingerPanEnabled: isOneFingerPanEnabled,
                simulateTwoFingerPanWithOneFinger: simulateTwoFingerPanWithOneFinger,
                installTarget: installTarget,
                pinchSensitivityExponent: pinchSensitivityExponent
            )
            onInstalled?(String(describing: type(of: view)))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard isEnabled, let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                onPanBegan?(recognizer.location(in: view))

            case .changed:
                let translation = recognizer.translation(in: view)
                recognizer.setTranslation(.zero, in: view)

                var newOffset = offsetBinding.wrappedValue
                newOffset.width += translation.x
                newOffset.height += translation.y
                offsetBinding.wrappedValue = newOffset
                lastSyncedOffset = newOffset

                let end = recognizer.location(in: view)
                let start = CGPoint(x: end.x - translation.x, y: end.y - translation.y)
                onPanChanged?(start, end, newOffset)

            case .ended, .cancelled, .failed:
                onPanEnded?()

            default:
                break
            }
        }

        @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            guard isEnabled, let view = recognizer.view else { return }

            switch recognizer.state {
            case .began:
                onPinchBegan?(recognizer.location(in: view))

            case .changed:
                let exponent = max(0.1, min(1.0, pinchSensitivityExponent))
                let adjusted = pow(Double(recognizer.scale), Double(exponent))
                var newScale = scaleBinding.wrappedValue * CGFloat(adjusted)
                recognizer.scale = 1.0
                newScale = min(max(newScale, minScale), maxScale)
                scaleBinding.wrappedValue = newScale
                lastSyncedScale = newScale
                onPinchChanged?(recognizer.location(in: view), newScale)

            case .ended, .cancelled, .failed:
                onPinchEnded?()

            default:
                break
            }
        }

        @objc private func handleOneFingerDrag(_ recognizer: UILongPressGestureRecognizer) {
            guard isEnabled, let view = recognizer.view else { return }

            guard isOneFingerPanEnabled else { return }

            let location = recognizer.location(in: view)
            let now = ProcessInfo.processInfo.systemUptime

            switch recognizer.state {
            case .began:
                oneFingerDragStartLocation = location
                oneFingerDragLastLocation = location
                oneFingerDragLastTimestamp = now
                if simulateTwoFingerPanWithOneFinger {
                    onPanBegan?(location)
                } else {
                    onOneFingerPanBegan?(location)
                }

            case .changed:
                guard let start = oneFingerDragStartLocation,
                      let last = oneFingerDragLastLocation,
                      let lastTimestamp = oneFingerDragLastTimestamp else { return }

                let translation = CGSize(width: location.x - start.x, height: location.y - start.y)
                let delta = CGSize(width: location.x - last.x, height: location.y - last.y)
                let dt = max(now - lastTimestamp, 0.0001)
                let velocity = CGSize(width: delta.width / dt, height: delta.height / dt)

                oneFingerDragLastLocation = location
                oneFingerDragLastTimestamp = now

                if simulateTwoFingerPanWithOneFinger {
                    var newOffset = offsetBinding.wrappedValue
                    newOffset.width += delta.width
                    newOffset.height += delta.height
                    offsetBinding.wrappedValue = newOffset
                    lastSyncedOffset = newOffset

                    let startPoint = CGPoint(x: location.x - delta.width, y: location.y - delta.height)
                    onPanChanged?(startPoint, location, newOffset)
                } else {
                    onOneFingerPanChanged?(location, translation, velocity)
                }

            case .ended, .cancelled, .failed:
                oneFingerDragStartLocation = nil
                oneFingerDragLastLocation = nil
                oneFingerDragLastTimestamp = nil
                if simulateTwoFingerPanWithOneFinger {
                    onPanEnded?()
                } else {
                    onOneFingerPanEnded?()
                }

            default:
                break
            }
        }
    }
}


struct ContentView: View {
    @EnvironmentObject var sharedData: SharedData

    private static let autoApplyCTPresetUserDefaultsKey = "autoApplyCTPreset"
    private static let fallbackCTUrinaryPresets: [String] = [
        "ct_urinary_adaptive",
        "ct_urinary_combined",
        "ct_urinary_excretory",
        "ct_urinary_stones"
    ]

    @AppStorage(Self.autoApplyCTPresetUserDefaultsKey) private var autoApplyCTPreset: Bool = true
    @StateObject private var webViewManager: WebViewManager

    init() {
        let storedAutoApply = UserDefaults.standard.object(forKey: Self.autoApplyCTPresetUserDefaultsKey) as? Bool ?? true
        _webViewManager = StateObject(wrappedValue: WebViewManager(autoApplyCTPresetDefault: storedAutoApply))
    }

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

    // MARK: - CT Presets (CT Adaptive Engine)

    @State private var ctPresetSheetPresented = false
    @State private var ctPresetStatusMessage: String?
    @State private var selectedCTPreset: String = "ct_urinary_adaptive"
    @State private var availableCTPresets: [String] = []

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

    // Phase 2 UX: 2D viewport interaction state (2-finger pan + pinch zoom).
    @State private var twoFingerPanOffset: CGSize = .zero
    @State private var twoFingerPanEventCount: Int = 0
    @State private var twoFingerPanInstallCount: Int = 0
    @State private var twoFingerPanInstalledViewType: String = ""
    @State private var twoFingerViewportScale: CGFloat = 1.0
    @State private var twoFingerPinchEventCount: Int = 0

    // Phase 2 UX: 2D tool mode (1-finger scroll vs. window/level).
    @State private var toolMode: ToolMode = .scroll
    @State private var windowWidth: Double = 1.0
    @State private var windowLevel: Double = 0.0
    @State private var windowLevelEventCount: Int = 0
    @State private var windowLevelIsDragging: Bool = false
    @State private var windowLevelDragStartWindowWidth: Double?
    @State private var windowLevelDragStartWindowLevel: Double?

    /// Phase 2 Task 2: Check if we should load multiple volumes for UI testing
    private var isUITestLoadMultiple: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-load-multiple")
    }

    private var isUITestSessionsTemp: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-sessions-temp")
    }

    private var isUITestSimulateTwoFingerPan: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-simulate-two-finger-pan")
    }

    private var isUITestSimulateTwoFingerPinch: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-simulate-two-finger-pinch")
    }

    private var uiTestDicomRelativeDirectory: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--ui-test-dicom-dir") else { return nil }
        let valueIndex = args.index(after: index)
        guard valueIndex < args.endIndex else { return nil }
        let value = args[valueIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private var isUITestMode: Bool {
        isUITestLoadMultiple ||
            isUITestSessionsTemp ||
            isUITestSimulateTwoFingerPan ||
            isUITestSimulateTwoFingerPinch ||
            uiTestDicomRelativeDirectory != nil
    }

    private var is2DSliceType: Bool {
        sliceType == SliceTypes.Axial.rawValue ||
            sliceType == SliceTypes.Coronal.rawValue ||
            sliceType == SliceTypes.Sagittal.rawValue
    }

    private var is2DWebViewSliceType: Bool {
        webViewManager.currentSliceType == SliceTypes.Axial.rawValue ||
            webViewManager.currentSliceType == SliceTypes.Coronal.rawValue ||
            webViewManager.currentSliceType == SliceTypes.Sagittal.rawValue
    }

    enum ToolMode: Int {
        case scroll = 0
        case windowLevel = 1
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
    private let windowLevelPointsPerHU: Double = 2.0

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

    private func collectDicomFiles(from pickedURLs: [URL]) -> [URL] {
        let fileManager = FileManager.default

        func isDicomCandidateFile(_ url: URL) -> Bool {
            let ext = url.pathExtension.lowercased()
            return ext == "dcm" || ext == "dicom" || ext.isEmpty
        }

        func isDirectory(_ url: URL) -> Bool {
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        func isRegularFile(_ url: URL) -> Bool {
            // Treat unknown as a file, since some providers may omit this.
            (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != false
        }

        var results: [URL] = []

        for url in pickedURLs {
            if isDirectory(url) {
                guard let enumerator = fileManager.enumerator(
                    at: url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else {
                    continue
                }

                for case let entryURL as URL in enumerator {
                    if isDirectory(entryURL) { continue }
                    guard isRegularFile(entryURL) else { continue }
                    guard isDicomCandidateFile(entryURL) else { continue }
                    results.append(entryURL)
                }
            } else {
                guard isRegularFile(url) else { continue }
                guard isDicomCandidateFile(url) else { continue }
                results.append(url)
            }
        }

        // Deterministic order helps reproducibility (and matches manifest ordering).
        return results.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func importDicomSeries(from pickedURLs: [URL]) {
        Task {
            await MainActor.run {
                dicomImportInProgress = true
                dicomImportStatusMessage = "Scanning selection…"
            }

            defer {
                Task { @MainActor in
                    dicomImportInProgress = false
                }
            }

            // Expand folders and filter to DICOM candidates (.dcm, .dicom, or files without extension).
            let dicomURLs = collectDicomFiles(from: pickedURLs)

            guard !dicomURLs.isEmpty else {
                await MainActor.run {
                    dicomImportStatusMessage = "No DICOM files found in selection."
                }
                return
            }

            let duplicates = Dictionary(grouping: dicomURLs, by: { $0.lastPathComponent })
                .filter { $0.value.count > 1 }
                .map(\.key)

            guard duplicates.isEmpty else {
                await MainActor.run {
                    let message = "Selection contains duplicate filenames (unsupported): \(duplicates.sorted().joined(separator: ", "))."
                    dicomImportStatusMessage = message
                    webViewManager.lastErrorMessage = message
                }
                return
            }

            await MainActor.run {
                dicomImportStatusMessage = "Importing \(dicomURLs.count) DICOM file(s)…"
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
                    let message = "Failed to load DICOM series: \(error.localizedDescription)"
                    dicomImportStatusMessage = message
                    webViewManager.lastErrorMessage = message
                }
            }
        }
    }

    // MARK: - CT Presets (CT Adaptive Engine)

    @MainActor
    private func loadCTUrinaryPresetsIfPossible() async {
        if availableCTPresets.isEmpty {
            availableCTPresets = Self.fallbackCTUrinaryPresets
        }

        guard webViewManager.isReady else { return }

        do {
            let presets = try await webViewManager.listCTUrinaryPresets()
            availableCTPresets = presets.isEmpty ? Self.fallbackCTUrinaryPresets : presets
            ctPresetStatusMessage = nil
        } catch {
            ctPresetStatusMessage = "Failed to load CT presets: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func syncAutoApplyCTPresetToJS(_ enabled: Bool) {
        guard webViewManager.isReady else { return }
        Task {
            do {
                try await webViewManager.setAutoApplyCTPreset(enabled: enabled)
            } catch {
                await MainActor.run {
                    ctPresetStatusMessage = "Failed to update auto-apply: \(error.localizedDescription)"
                }
            }
        }
    }

    private func displayNameForCTPreset(_ preset: String) -> String {
        switch preset {
        case "ct_urinary_adaptive":
            return "Adaptive (Auto-Detect)"
        case "ct_urinary_combined":
            return "Vessels + Parenchyma"
        case "ct_urinary_excretory":
            return "Excretory Phase"
        case "ct_urinary_stones":
            return "Stone Detection"
        default:
            return preset.capitalized.replacingOccurrences(of: "_", with: " ")
        }
    }

    @MainActor
    private func applyAdaptiveCTPresetNowIfPossible() {
        guard webViewManager.volumes.isEmpty == false else { return }
        Task {
            do {
                try await webViewManager.applyAdaptiveCTUrinaryPreset(volumeIndex: 0)
            } catch {
                await MainActor.run {
                    ctPresetStatusMessage = "Failed to apply adaptive preset: \(error.localizedDescription)"
                }
            }
        }
    }

    @MainActor
    private func applySelectedCTPresetNow() {
        guard webViewManager.volumes.isEmpty == false else { return }
        Task {
            do {
                try await webViewManager.applyCTUrinaryPreset(volumeIndex: 0, presetName: selectedCTPreset)
            } catch {
                await MainActor.run {
                    ctPresetStatusMessage = "Failed to apply CT preset: \(error.localizedDescription)"
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
        if webViewManager.lastLocationString != nil || windowLevelIsDragging {
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        if let locationString = webViewManager.lastLocationString {
                            Text(locationString)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                                .accessibilityIdentifier("niivue.hud")
                        }

                        if windowLevelIsDragging {
                            Text("WW \(Int(windowWidth.rounded()))  WL \(Int(windowLevel.rounded()))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                                .accessibilityIdentifier("niivue.windowLevelOverlay")
                        }
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
            .allowsHitTesting(false)
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
                // 2D tool mode: Window/Level (contrast/brightness) vs Stack Scroll
                Button(action: {
                    guard sliceType == SliceTypes.Axial.rawValue || sliceType == SliceTypes.Coronal.rawValue || sliceType == SliceTypes.Sagittal.rawValue else {
                        toolMode = .scroll
                        return
                    }

                    toolMode = (toolMode == .windowLevel) ? .scroll : .windowLevel
                    windowLevelIsDragging = false
                    windowLevelDragStartWindowWidth = nil
                    windowLevelDragStartWindowLevel = nil
                    windowLevelEventCount = 0

                    // Our 2D gesture system owns 1-finger drags (stack scroll + window/level).
                    // Disable Niivue's internal drag handling so the underlying web content
                    // doesn't also move the crosshair while the native layer is processing drags.
                    Task {
                        try? await webViewManager.setDragMode(dragMode: DragTypes.None.rawValue)
                    }

                    if toolMode == .windowLevel {
                        Task {
                            if let updated = try? await webViewManager.getIntensityWindow(volumeIndex: 0) {
                                await MainActor.run {
                                    windowWidth = max(1.0, updated.windowWidth)
                                    windowLevel = updated.windowLevel
                                }
                            }
                        }
                    }
                }) {
                    Image(systemName: "sun.max")
                        .padding()
                        .foregroundColor(toolMode == .windowLevel ? .yellow : .white)
                }
                .accessibilityIdentifier("niivue.tool.windowLevel")
                .disabled(!(sliceType == SliceTypes.Axial.rawValue || sliceType == SliceTypes.Coronal.rawValue || sliceType == SliceTypes.Sagittal.rawValue))
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

                // CT Adaptive Engine UI: Dedicated CT Presets sheet
                Button(action: {
                    ctPresetSheetPresented = true
                }) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .padding()
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("niivue.ctPresets")
                .sheet(isPresented: $ctPresetSheetPresented) {
                    NavigationStack {
                        VStack(spacing: 0) {
                            AccessibilityMarkerView(identifier: "niivue.ctPresetSheet")
                                .frame(width: 1, height: 1)
                                .opacity(0.01)

                            if let message = ctPresetStatusMessage {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .accessibilityIdentifier("niivue.ctPresetStatus")
                            }

                            Form {
                                if let analysis = webViewManager.lastCTPresetAnalysis {
                                    Section {
                                        HStack {
                                            Text("Phase")
                                            Spacer()
                                            Text(analysis.phase)
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                                .accessibilityIdentifier("niivue.ctPresetAnalysis.phase")
                                        }
                                        HStack {
                                            Text("Confidence")
                                            Spacer()
                                            Text(String(format: "%.2f", analysis.confidence))
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                        HStack {
                                            Text("Window")
                                            Spacer()
                                            Text(String(format: "%.0f…%.0f HU", analysis.calMin, analysis.calMax))
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    } header: {
                                        Text("Last Analysis")
                                    }
                                }

                                Section {
                                    Toggle("Auto-apply adaptive preset", isOn: $autoApplyCTPreset)
                                        .accessibilityIdentifier("niivue.ctPresetAutoApply")
                                        .onChange(of: autoApplyCTPreset) { newValue in
                                            syncAutoApplyCTPresetToJS(newValue)
                                            if newValue {
                                                applyAdaptiveCTPresetNowIfPossible()
                                            }
                                        }
                                } header: {
                                    Text("Automatic Detection")
                                } footer: {
                                    Text("Automatically applies the adaptive CT preset when new volumes finish loading.")
                                        .font(.caption)
                                }

                                Section {
                                    Picker("Preset", selection: $selectedCTPreset) {
                                        ForEach(availableCTPresets.isEmpty ? Self.fallbackCTUrinaryPresets : availableCTPresets, id: \.self) { preset in
                                            Text(displayNameForCTPreset(preset)).tag(preset)
                                        }
                                    }
                                    .accessibilityIdentifier("niivue.ctPresetPicker")
                                    .onChange(of: selectedCTPreset) { _ in
                                        applySelectedCTPresetNow()
                                    }
                                } header: {
                                    Text("Preset Selection")
                                }

                                Section {
                                    Button("Apply Preset Now") {
                                        applySelectedCTPresetNow()
                                    }
                                    .accessibilityIdentifier("niivue.ctPresetApply")
                                    .disabled(webViewManager.volumes.isEmpty)
                                } header: {
                                    Text("Manual Control")
                                }
                            }
                        }
                        .navigationTitle("CT Presets")
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { ctPresetSheetPresented = false }
                            }
                        }
                        .task(id: webViewManager.isReady) {
                            await loadCTUrinaryPresetsIfPossible()
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
                    .onChange(of: webViewManager.isReady) { isReady in
                        guard isReady else { return }
                        syncAutoApplyCTPresetToJS(autoApplyCTPreset)
                    }
                    .overlay(
                        ViewportInteractionHandler(
                            offset: $twoFingerPanOffset,
                            scale: $twoFingerViewportScale,
                            installTarget: is2DWebViewSliceType ? .installerView : .webView,
                            accessibilityIdentifier: isUITestSimulateTwoFingerPinch ? "niivue.viewportInteractionSurface" : nil,
                            isEnabled: webViewManager.currentSliceType == 0 || webViewManager.currentSliceType == 1 || webViewManager.currentSliceType == 2,
                            isOneFingerPanEnabled: is2DWebViewSliceType,
                            simulateTwoFingerPanWithOneFinger: isUITestSimulateTwoFingerPan,
                            pinchSensitivityExponent: 0.9,
                            onInstalled: { viewType in
                                twoFingerPanInstallCount += 1
                                twoFingerPanInstalledViewType = viewType
                            },
                            onPanBegan: { _ in
                                twoFingerPanEventCount = 0
                            },
                            onPanChanged: { start, end, _ in
                                twoFingerPanEventCount += 1
                                let delta = CGSize(width: end.x - start.x, height: end.y - start.y)
                                webViewManager.enqueue2DPanDelta(
                                    deltaX: Double(delta.width),
                                    deltaY: Double(delta.height),
                                    endX: Double(end.x),
                                    endY: Double(end.y)
                                )
                            },
                            onPanEnded: {
                                webViewManager.flushPendingGestureCommandsNow()
                            },
                            onPinchBegan: { _ in
                                twoFingerPinchEventCount = 0
                            },
                            onPinchChanged: { location, newScale in
                                twoFingerPinchEventCount += 1
                                webViewManager.enqueue2DZoom(
                                    scale: Double(newScale),
                                    anchorX: Double(location.x),
                                    anchorY: Double(location.y)
                                )
                            },
                            onPinchEnded: {
                                webViewManager.flushPendingGestureCommandsNow()
                            },
                            onOneFingerPanBegan: { _ in
                                switch toolMode {
                                case .scroll:
                                    webViewManager.handleStackScrollDragBegan(translationY: 0, velocityY: 0)

                                case .windowLevel:
                                    guard is2DWebViewSliceType else { return }
                                    windowLevelIsDragging = true
                                    windowLevelDragStartWindowWidth = windowWidth
                                    windowLevelDragStartWindowLevel = windowLevel
                                    windowLevelEventCount = 0
                                }
                            },
                            onOneFingerPanChanged: { _, translation, velocity in
                                switch toolMode {
                                case .scroll:
                                    webViewManager.handleStackScrollDragChanged(
                                        translationY: Double(translation.height),
                                        velocityY: Double(velocity.height)
                                    )

                                case .windowLevel:
                                    guard is2DWebViewSliceType else { return }
                                    guard let startWW = windowLevelDragStartWindowWidth,
                                          let startWL = windowLevelDragStartWindowLevel else { return }

                                    var newWidth = startWW + (Double(translation.width) * windowLevelPointsPerHU)
                                    newWidth = max(1.0, newWidth)
                                    let newLevel = startWL - (Double(translation.height) * windowLevelPointsPerHU)

                                    windowWidth = newWidth
                                    windowLevel = newLevel
                                    windowLevelEventCount += 1

                                    webViewManager.enqueueIntensityWindow(
                                        volumeIndex: 0,
                                        windowWidth: newWidth,
                                        windowLevel: newLevel
                                    )
                                }
                            },
                            onOneFingerPanEnded: {
                                switch toolMode {
                                case .scroll:
                                    webViewManager.handleStackScrollDragEnded()

                                case .windowLevel:
                                    windowLevelIsDragging = false
                                    windowLevelDragStartWindowWidth = nil
                                    windowLevelDragStartWindowLevel = nil
                                    webViewManager.flushPendingGestureCommandsNow()
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(is2DWebViewSliceType)
                    )
                    .background(Color.black)

                loadingOverlay
                hudOverlay

                // Phase 2: UI-test instrumentation overlay
                if isUITestMode {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            VStack(alignment: .trailing, spacing: 8) {
                                Text(webViewManager.isReady ? "ready" : "notReady")
                                    .accessibilityIdentifier("niivue.isReady")
                                Text("\(webViewManager.volumes.count)")
                                    .accessibilityIdentifier("niivue.volumeCount")
                                Text("\(webViewManager.currentSliceIndex ?? -1)")
                                    .accessibilityIdentifier("niivue.sliceIndex")
                                Text("\(webViewManager.currentCrosshairSliceIndex ?? -1)")
                                    .accessibilityIdentifier("niivue.crosshairSliceIndex")
                                Text("\(webViewManager.currentTotalSlices ?? -1)")
                                    .accessibilityIdentifier("niivue.totalSlices")
                                Text("\(webViewManager.currentSliceType)")
                                    .accessibilityIdentifier("niivue.sliceType")
                                Text("\(webViewManager.stackScrollDebugEventCount)")
                                    .accessibilityIdentifier("niivue.stackScrollEvents")
                                Text(String(format: "%.3f", windowWidth))
                                    .accessibilityIdentifier("niivue.windowWidth")
                                Text(String(format: "%.3f", windowLevel))
                                    .accessibilityIdentifier("niivue.windowLevel")
                                Text("\(windowLevelEventCount)")
                                    .accessibilityIdentifier("niivue.windowLevelEvents")
                                Text("\(Int(twoFingerPanOffset.width))")
                                    .accessibilityIdentifier("niivue.twoFingerPanOffsetX")
                                Text("\(Int(twoFingerPanOffset.height))")
                                    .accessibilityIdentifier("niivue.twoFingerPanOffsetY")
                                Text("\(twoFingerPanEventCount)")
                                    .accessibilityIdentifier("niivue.twoFingerPanEvents")
                                Text(String(format: "%.3f", twoFingerViewportScale))
                                    .accessibilityIdentifier("niivue.viewportScale")
                                Text("\(twoFingerPinchEventCount)")
                                    .accessibilityIdentifier("niivue.viewportPinchEvents")
                                Text("\(twoFingerPanInstallCount)")
                                    .accessibilityIdentifier("niivue.twoFingerPanInstallCount")
                                Text(twoFingerPanInstalledViewType)
                                    .accessibilityIdentifier("niivue.twoFingerPanInstalledView")
                                Text(dicomImportStatusMessage ?? "")
                                    .accessibilityIdentifier("niivue.dicomImportStatusGlobal")
                                Text(webViewManager.lastErrorMessage ?? "")
                                    .accessibilityIdentifier("niivue.lastError")
                                Text(webViewManager.lastJSLogMessage ?? "")
                                    .accessibilityIdentifier("niivue.lastJSLog")
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
                    .allowsHitTesting(false)
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
                        } else if let relativeDir = uiTestDicomRelativeDirectory {
                            await MainActor.run {
                                dicomImportInProgress = true
                                dicomImportStatusMessage = "Loading DICOM fixture…"
                            }

                            defer {
                                Task { @MainActor in
                                    dicomImportInProgress = false
                                }
                            }

                            let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                            let fixtureDir = documentsDir.appendingPathComponent(relativeDir, isDirectory: true)

                            let fileURLs: [URL]
                            do {
                                fileURLs = try FileManager.default.contentsOfDirectory(
                                    at: fixtureDir,
                                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                                    options: [.skipsHiddenFiles]
                                )
                            } catch {
                                await MainActor.run {
                                    dicomImportStatusMessage = "Failed to read fixture dir: \(error.localizedDescription)"
                                }
                                return
                            }

                            let dicomFiles = fileURLs
                                .filter { url in
                                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
                                    guard values?.isDirectory != true else { return false }
                                    guard values?.isRegularFile != false else { return false }
                                    let ext = url.pathExtension.lowercased()
                                    return ext == "dcm" || ext == "dicom" || ext.isEmpty
                                }
                                .sorted { $0.lastPathComponent < $1.lastPathComponent }

                            guard !dicomFiles.isEmpty else {
                                await MainActor.run {
                                    dicomImportStatusMessage = "Failed: no DICOM files found in fixture dir."
                                }
                                return
                            }

                            await MainActor.run {
                                dicomImportStatusMessage = "Loading \(dicomFiles.count) DICOM file(s)…"
                            }

                            let seriesId = await dicomSeriesStore.register(files: dicomFiles)
                            webViewManager.urlSchemeHandler.dicomSeriesStore = dicomSeriesStore

                            let manifestURL = "niivue://app/dicom/\(seriesId)/niivue-manifest.txt"
                            do {
                                try await webViewManager.loadDicomSeriesFromManifestURL(manifestURL)
                                await MainActor.run {
                                    dicomImportStatusMessage = "Loaded \(dicomFiles.count) DICOM file(s)."
                                }
                            } catch {
                                await MainActor.run {
                                    let message = "Failed to load DICOM series: \(error.localizedDescription)"
                                    dicomImportStatusMessage = message
                                    webViewManager.lastErrorMessage = message
                                }
                            }
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

		                        if let updated = try? await webViewManager.getIntensityWindow(volumeIndex: 0) {
		                            await MainActor.run {
		                                windowWidth = max(1.0, updated.windowWidth)
		                                windowLevel = updated.windowLevel
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
            if !(newValue == SliceTypes.Axial.rawValue || newValue == SliceTypes.Coronal.rawValue || newValue == SliceTypes.Sagittal.rawValue) {
                toolMode = .scroll
                windowLevelIsDragging = false
                windowLevelDragStartWindowWidth = nil
                windowLevelDragStartWindowLevel = nil
            }
            Task {
                do {
                    try await webViewManager.setSliceType(sliceType: newValue)

                    // In 2D slice views, the native gesture system owns dragging. Disable Niivue drag mode to
                    // prevent the underlying web content from competing with native gestures.
                    if newValue == SliceTypes.Axial.rawValue || newValue == SliceTypes.Coronal.rawValue || newValue == SliceTypes.Sagittal.rawValue {
                        try await webViewManager.setDragMode(dragMode: DragTypes.None.rawValue)
                    } else {
                        try await webViewManager.setDragMode(dragMode: dragType)
                    }
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
            guard !is2DSliceType else {
                // 2D slice views are driven by native gestures; ignore dragMode changes here.
                return
            }
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
