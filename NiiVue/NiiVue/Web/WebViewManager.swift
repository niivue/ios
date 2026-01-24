//
//  WebViewManager.swift
//  NiiVue
//
//  Task 4: Refactored WebViewManager with safe quoting + async evaluation
//  Task 6: Single source of truth for loading/error UI
//

import Foundation
import UIKit
import WebKit

/// Manages the WKWebView and provides a type-safe bridge to the Niivue JS app.
/// Uses JSON-safe escaping for all JavaScript calls and async/await for all evaluations.
@MainActor
final class WebViewManager: NSObject, ObservableObject {
    // MARK: - Published State (Task 6: Single Source of Truth)

    /// Whether the web view has finished loading and is ready for commands
    @Published var isReady: Bool = false

    /// Last error message, if any (nil when no error)
    @Published var lastErrorMessage: String?

    /// Last log message received from the JS layer (for diagnostics / UI tests).
    @Published var lastJSLogMessage: String?

    /// Last log level received from the JS layer (e.g., "debug", "info", "warn", "error").
    @Published var lastJSLogLevel: String?

    /// Last debug message emitted by the custom `niivue://` URL scheme handler.
    /// This is useful for diagnosing large DICOM loads without relying on device console logs.
    @Published var lastURLSchemeDebugMessage: String?

    /// Last CT adaptive preset analysis reported from JS (phase/window/colormap).
    @Published var lastCTPresetAnalysis: CTPresetAnalysis?

    /// List of currently loaded volumes (Phase 2: volume notifications)
    @Published var volumes: [VolumeInfo] = []

    /// Sources used to load the current `volumes` stack (Phase 2 Task 6: sessions).
    /// Used to reload volumes on session restore.
    @Published var volumeSources: [SessionSnapshotV1.VolumeSource] = []

    // MARK: - Volume Visibility (Opacity Cache)

    private var lastKnownOpacityByVolumeID: [String: Double] = [:]
    private var hiddenOpacityBackupByVolumeID: [String: Double] = [:]

    /// Last location string from Niivue onLocationChange (Phase 2 Task 1: HUD)
    @Published var lastLocationString: String?

    /// Last crosshair voxel coordinate reported by Niivue (used for gesture-driven stack scrolling).
    @Published var lastLocationVox: SIMD3<Int>?

    /// Last crosshair voxel coordinate reported by Niivue (`scene.crosshairPos` converted to vox).
    /// Prefer this over `lastLocationVox` when driving slice navigation, since `lastLocationVox` may represent the
    /// cursor-under-finger rather than the crosshair itself.
    @Published var lastCrosshairVox: SIMD3<Int>?

    /// Volume dimensions in RAS order from Niivue (dimsRAS: [_, x, y, z]).
    @Published var volumeDimsRAS: [Int]?

    /// Last clip plane depth reported by Niivue (Phase 2 UI: 3D slice scrolling instrumentation)
    @Published var lastClipPlaneDepth: Double?

    /// Current slice type last set by Swift (0=Axial, 1=Coronal, 2=Sagittal, 3=Multiplanar, 4=Render).
    /// Used for native gesture behavior and UI test instrumentation.
    @Published var currentSliceType: Int = 3

    /// UI test instrumentation: counts stack-scroll pan updates received by native gesture layer.
    @Published var stackScrollDebugEventCount: Int = 0

    /// UI test instrumentation: click-to-segment apply counter (JS → Swift).
    @Published var lastClickToSegmentApplyCount: Int?

    /// UI test instrumentation: sum of drawing bitmap values after click-to-segment (JS → Swift).
    @Published var lastClickToSegmentDrawSum: Double?

    /// UI test instrumentation: volume of last click-to-segment region in mm^3 (JS → Swift).
    @Published var lastClickToSegmentVolumeMM3: Double?

    /// UI test instrumentation: volume of last click-to-segment region in mL (JS → Swift).
    @Published var lastClickToSegmentVolumeML: Double?

    /// UI test instrumentation: last drawing operation name (JS → Swift).
    @Published var lastDrawingOperation: String?

    /// UI test instrumentation: sum of drawing bitmap values after the last drawing operation (JS → Swift).
    @Published var lastDrawingDrawSum: Double?

    // MARK: - DICOM Load Coordination (JS → Swift)

    struct DicomLoadStatus: Codable, Equatable {
        let requestId: Int
        let ok: Bool
        let elapsedMs: Double?
        let error: String?
    }

    @Published var lastDicomLoadStatus: DicomLoadStatus?

    private var nextDicomLoadRequestId: Int = 1
    private var pendingDicomLoads: [Int: CheckedContinuation<Void, Error>] = [:]

    // MARK: - Volume Info

    struct VolumeInfo: Codable, Equatable {
        let id: String
        let name: String
        let nFrame4D: Int
    }

    // MARK: - CT Preset Analysis (JS → Swift reporting)

    struct CTPresetAnalysis: Codable, Equatable {
        let phase: String
        let confidence: Double
        let calMin: Double
        let calMax: Double
        let windowWidth: Double
        let windowLevel: Double
        let colormap: String
    }

    // MARK: - Click-to-Segment Debug (JS → Swift reporting)

    struct ClickToSegmentDebug: Codable, Equatable {
        let applyCount: Int
        let drawSum: Double
    }

    struct ClickToSegmentResult: Codable, Equatable {
        let mm3: Double?
        let mL: Double?
    }

    // MARK: - Drawing Debug (JS → Swift reporting)

    struct DrawingDebug: Codable, Equatable {
        let operation: String
        let drawSum: Double
    }

    // MARK: - WebView

    let webView: WKWebView
    private let evaluator: JavaScriptEvaluating
    private let autoApplyCTPresetDefault: Bool
    private let initializationTimeoutNanoseconds: UInt64
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Native Gestures (2D Stack Scroll)

    /// Baseline sensitivity for stack scrolling. Higher = slower (more pixels required per slice).
    /// Tuned for a "weighted" PACS feel: not too sensitive, not too sluggish.
    private var stackScrollBasePixelsPerSlice: Double = 13.0
    private let stackScrollMinPixelsPerSliceFactor: Double = 0.9
    private let stackScrollMaxPixelsPerSliceFactor: Double = 1.3
    private let stackScrollVelocitySlowThreshold: Double = 300.0
    private let stackScrollVelocityFastThreshold: Double = 1500.0
    private var stackScrollPixelsPerSliceForGesture: Double?
    private var stackScrollInitialSliceIndex: Int?
    private var stackScrollLastAppliedSliceIndex: Int?
    private var stackScrollAxis: Int?

    // MARK: - Gesture Command Coalescing (Performance / Smoothness)

    private let gestureFlushIntervalNanoseconds: UInt64 = 8_000_000 // ~125Hz cap (good on 120Hz devices)
    private var gestureFlushTask: Task<Void, Never>?

    private var pendingCrosshairDelta: SIMD3<Int> = .zero
    private var pendingIntensityWindow: (volumeIndex: Int, windowWidth: Double, windowLevel: Double)?
    private var pending2DPan: (deltaX: Double, deltaY: Double, endX: Double, endY: Double)?
    private var pending2DZoom: (scale: Double, anchorX: Double, anchorY: Double)?

    // MARK: - URL Scheme Handler (Task 11)

    /// The URL scheme handler for serving files via niivue://
    /// Internal access allows ContentView to set dicomSeriesStore for Phase 2 Task 9.
    var urlSchemeHandler: NiivueURLSchemeHandler!

    /// The imported file store for resolving file IDs to URLs
    var importedFileStore: ImportedFileStore!

    // MARK: - Weak Script Message Handler (prevents retain cycle)

    /// WKUserContentController strongly retains its handlers.
    /// This weak proxy breaks the cycle: WKWebView -> config -> userContentController -> WeakHandler -> WebViewManager
    @MainActor
    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        weak var owner: WebViewManager?

        init(owner: WebViewManager) {
            self.owner = owner
            super.init()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            owner?.handleScriptMessage(name: message.name, body: message.body)
        }
    }

    private lazy var scriptMessageHandler = WeakScriptMessageHandler(owner: self)

    // MARK: - URL for loading the React app (Task 11: custom scheme)

    /// The URL for loading the React app via niivue:// custom scheme.
    /// This loads from the bundled dist/ directory via NiivueURLSchemeHandler.
    private var url: URL {
        URL(string: "niivue://app/index.html")!
    }

    // MARK: - Initialization

    /// Creates a new WebViewManager.
    /// - Parameters:
    ///   - evaluator: Optional JavaScript evaluator for testing. Defaults to using the webView.
    ///   - initializationTimeoutNanoseconds: Timeout for initialization (default 30s).
    init(
        evaluator: JavaScriptEvaluating? = nil,
        autoApplyCTPresetDefault: Bool = true,
        initializationTimeoutNanoseconds: UInt64 = 30_000_000_000
    ) {
        let config = WKWebViewConfiguration()

        // Task 11: Create and register custom URL scheme handler for niivue://
        // This must be done BEFORE creating the WKWebView
        let handler = NiivueURLSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: "niivue")

        // CT Adaptive Engine (Option B): Swift sets a default for auto-apply before the web app runs.
        // Inject into the `.page` world so the React/Niivue scripts see `window.autoApplyCTPreset`.
        let autoApplyLiteral = autoApplyCTPresetDefault ? "true" : "false"
        let autoApplyScript = WKUserScript(
            source: "window.autoApplyCTPreset = \(autoApplyLiteral);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        config.userContentController.addUserScript(autoApplyScript)

        let wk = WKWebView(frame: .zero, configuration: config)
        self.webView = wk
        self.evaluator = evaluator ?? wk
        self.autoApplyCTPresetDefault = autoApplyCTPresetDefault
        self.initializationTimeoutNanoseconds = initializationTimeoutNanoseconds
        self.urlSchemeHandler = handler
        self.importedFileStore = ImportedFileStore()
        super.init()

        // Task 12: Wire importedFileStore to URL scheme handler
        urlSchemeHandler.importedFileStore = importedFileStore
        urlSchemeHandler.preprocessedVolumeCache = PreprocessedVolumeCache()
        urlSchemeHandler.onDebugUpdate = { [weak self] message in
            self?.lastURLSchemeDebugMessage = message
        }

        // Only configure the webView if we're not using a mock evaluator
        if evaluator == nil {
            setupWebView()
        }

        // Start initialization timeout (Task 6)
        startInitializationTimeout()
    }

    private func setupWebView() {
        let config = webView.configuration

        // Register script message handlers using weak proxy
        config.userContentController.add(scriptMessageHandler, name: "finishedLoading")
        config.userContentController.add(scriptMessageHandler, name: "volumeLoaded")
        config.userContentController.add(scriptMessageHandler, name: "locationChange")
        config.userContentController.add(scriptMessageHandler, name: "clipPlaneChanged")
        config.userContentController.add(scriptMessageHandler, name: "updateUI")
        config.userContentController.add(scriptMessageHandler, name: "logMessage")
        config.userContentController.add(scriptMessageHandler, name: "messageHandler")

        // WebView configuration
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.isScrollEnabled = false
        webView.underPageBackgroundColor = UIColor.black
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        #if DEBUG
        webView.isInspectable = true
        #endif
    }

    // MARK: - Initialization Timeout (Task 6)

    private func startInitializationTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: self?.initializationTimeoutNanoseconds ?? 30_000_000_000)
                // If we're still not ready after timeout, set error
                await MainActor.run {
                    if self?.isReady == false {
                        self?.lastErrorMessage = "WebView initialization timeout"
                    }
                }
            } catch {
                // Task was cancelled (normal case when ready received)
            }
        }
    }

    // MARK: - Script Message Handling

    /// Handles messages received from JavaScript.
    /// Called from WeakScriptMessageHandler or directly in tests.
    func handleScriptMessage(name: String, body: Any) {
        switch name {
        case "finishedLoading":
            isReady = true
            lastErrorMessage = nil
            lastJSLogMessage = nil
            lastJSLogLevel = nil
            lastURLSchemeDebugMessage = nil
            lastClickToSegmentApplyCount = nil
            lastClickToSegmentDrawSum = nil
            lastClickToSegmentVolumeMM3 = nil
            lastClickToSegmentVolumeML = nil
            timeoutTask?.cancel()

        case "volumeLoaded":
            print("[WebViewManager] Received volumeLoaded message: \(body)")
            guard let jsonString = body as? String,
                  let data = jsonString.data(using: .utf8) else {
                print("[WebViewManager] Failed to get string from body")
                return
            }
            do {
                let volumeInfo = try JSONDecoder().decode(VolumeInfo.self, from: data)
                // Update or append volume
                if let index = volumes.firstIndex(where: { $0.id == volumeInfo.id }) {
                    volumes[index] = volumeInfo
                    print("[WebViewManager] Updated volume: \(volumeInfo.name), total: \(volumes.count)")
                } else {
                    volumes.append(volumeInfo)
                    print("[WebViewManager] Appended volume: \(volumeInfo.name), total: \(volumes.count)")
                }
            } catch {
                print("[WebViewManager] Failed to decode volumeLoaded: \(error)")
            }

        case "locationChange":
            // Phase 2 Task 1: HUD location readout
            guard let jsonString = body as? String,
                  let data = jsonString.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            if let locationString = dict["string"] as? String {
                lastLocationString = locationString
            }

            if let voxAny = dict["vox"] as? [Any], voxAny.count >= 3 {
                let voxInts = voxAny.prefix(3).compactMap { ($0 as? NSNumber)?.intValue }
                if voxInts.count == 3 {
                    lastLocationVox = SIMD3(voxInts[0], voxInts[1], voxInts[2])
                }
            }

            if let crosshairAny = dict["crosshairVox"] as? [Any], crosshairAny.count >= 3 {
                let voxInts = crosshairAny.prefix(3).compactMap { ($0 as? NSNumber)?.intValue }
                if voxInts.count == 3 {
                    lastCrosshairVox = SIMD3(voxInts[0], voxInts[1], voxInts[2])
                }
            }

            if let dimsAny = dict["dimsRAS"] as? [Any], dimsAny.count >= 4 {
                let dimsInts = dimsAny.compactMap { ($0 as? NSNumber)?.intValue }
                if dimsInts.count >= 4 {
                    volumeDimsRAS = dimsInts
                }
            }

        case "clipPlaneChanged":
            struct ClipPlaneChanged: Codable {
                let depth: Double
            }

            guard let jsonString = body as? String,
                  let data = jsonString.data(using: .utf8) else {
                return
            }
            if let payload = try? JSONDecoder().decode(ClipPlaneChanged.self, from: data) {
                lastClipPlaneDepth = payload.depth
            }

        case "updateUI":
            struct UpdateUIEnvelope<T: Decodable>: Decodable {
                let type: String
                let payload: T?
            }

            guard let jsonString = body as? String,
                  let data = jsonString.data(using: .utf8) else {
                return
            }

            if let envelope = try? JSONDecoder().decode(UpdateUIEnvelope<CTPresetAnalysis>.self, from: data),
               envelope.type == "ctPresetAnalysis",
               let payload = envelope.payload {
                lastCTPresetAnalysis = payload
                return
            }

            if let envelope = try? JSONDecoder().decode(UpdateUIEnvelope<ClickToSegmentDebug>.self, from: data),
               envelope.type == "clickToSegmentDebug",
               let payload = envelope.payload {
                lastClickToSegmentApplyCount = payload.applyCount
                lastClickToSegmentDrawSum = payload.drawSum
                return
            }

            if let envelope = try? JSONDecoder().decode(UpdateUIEnvelope<ClickToSegmentResult>.self, from: data),
               envelope.type == "clickToSegmentResult",
               let payload = envelope.payload {
                lastClickToSegmentVolumeMM3 = payload.mm3
                lastClickToSegmentVolumeML = payload.mL
                return
            }

            if let envelope = try? JSONDecoder().decode(UpdateUIEnvelope<DrawingDebug>.self, from: data),
               envelope.type == "drawingDebug",
               let payload = envelope.payload {
                lastDrawingOperation = payload.operation
                lastDrawingDrawSum = payload.drawSum
                return
            }

            if let envelope = try? JSONDecoder().decode(UpdateUIEnvelope<DicomLoadStatus>.self, from: data),
               envelope.type == "dicomLoad",
               let payload = envelope.payload {
                lastDicomLoadStatus = payload

                if let pending = pendingDicomLoads.removeValue(forKey: payload.requestId) {
                    if payload.ok {
                        pending.resume()
                    } else {
                        let message = payload.error ?? "Unknown DICOM load error"
                        pending.resume(throwing: NSError(domain: "NiiVue.DICOM", code: 2, userInfo: [NSLocalizedDescriptionKey: message]))
                    }
                }
                return
            }

            // Keep log noise low; most updateUI messages are for UI tests/debug only.
            // print("[WebViewManager] updateUI: \(body)")

        case "logMessage":
            struct JSLogMessage: Codable {
                let level: String
                let message: String
                let timestamp: Double?
            }

            guard let jsonString = body as? String else {
                print("[WebViewManager] logMessage (non-string): \(body)")
                lastJSLogMessage = String(describing: body)
                lastJSLogLevel = "unknown"
                return
            }

            if let data = jsonString.data(using: .utf8),
               let payload = try? JSONDecoder().decode(JSLogMessage.self, from: data) {
                lastJSLogLevel = payload.level
                lastJSLogMessage = payload.message
                print("[WebViewManager][JS][\(payload.level)] \(payload.message)")

                if payload.level == "error" {
                    lastErrorMessage = payload.message
                }
            } else {
                lastJSLogLevel = "unknown"
                lastJSLogMessage = jsonString
                print("[WebViewManager][JS] \(jsonString)")
            }

        default:
            print("[WebViewManager] Unhandled message: \(name)")
        }
    }

    // MARK: - Loading

    /// Loads the React app via the custom niivue:// scheme (Task 11).
    /// The NiivueURLSchemeHandler serves the bundled dist/ files.
    func load() {
        webView.load(URLRequest(url: url))
    }

    /// Reloads the web view (for retry after error).
    func reload() {
        lastErrorMessage = nil
        isReady = false
        startInitializationTimeout()
        load()
    }

    // MARK: - Volume Loading

    enum PreprocessedVolumeError: Error {
        case cacheUnavailable
        case failedToStore
    }

    /// Executes an async JS call where Swift doesn't need the return value.
    ///
    /// `WKWebView.callAsyncJavaScript` can throw `WKError.Code.javaScriptResultTypeIsUnsupported`
    /// if a Promise resolves (or rejects) with a value that can't be bridged to Foundation types.
    /// This wrapper ensures the JS boundary is always:
    /// - resolved with `null` (bridges as `NSNull`)
    /// - rejected with a `String` (bridgable, deterministic failure reason)
    private func callAsyncVoid(_ awaitedCall: String) async throws {
        guard isReady else {
            lastErrorMessage = NiivueError.webViewNotReady.localizedDescription
            throw NiivueError.webViewNotReady
        }

        let functionBody = """
        try {
          \(awaitedCall)
          return null;
        } catch (e) {
          throw String(e);
        }
        """
        do {
            _ = try await evaluator.callAsyncStringSafe(functionBody)
        } catch {
            let wrapped = NiivueError.wrap(error, context: awaitedCall)
            lastErrorMessage = wrapped.localizedDescription
            throw wrapped
        }
    }

    /// Loads a base64-encoded image into Niivue.
    /// - Parameters:
    ///   - base64: Base64-encoded image data
    ///   - fileName: Name of the file (for format detection)
    func loadBase64Image(base64: String, fileName: String) async throws {
        lastErrorMessage = nil
        volumes.removeAll()
        volumeSources.removeAll()
        let b64 = try JavaScriptQuote.jsonStringLiteral(base64)
        let name = try JavaScriptQuote.jsonStringLiteral(fileName)
        try await callAsyncVoid("await window.loadBase64Image(\(b64), \(name));")
    }

    /// Loads an image from a URL into Niivue (Task 12: URL-based loading).
    /// This eliminates base64 encoding overhead for large files.
    /// - Parameters:
    ///   - url: URL string (typically niivue://app/files/<id> for imported files)
    ///   - fileName: Original filename for format detection
    func loadImageFromUrl(url: String, fileName: String) async throws {
        lastErrorMessage = nil
        volumes.removeAll()
        volumeSources = [.init(url: url, name: fileName)]
        let urlEscaped = try JavaScriptQuote.jsonStringLiteral(url)
        let nameEscaped = try JavaScriptQuote.jsonStringLiteral(fileName)
        try await callAsyncVoid("await window.loadImageFromUrl(\(urlEscaped), \(nameEscaped));")
    }

    /// Loads a preprocessed volume from the native cache via `niivue://app/preprocessed/...`.
    /// Ensures the file exists in `PreprocessedVolumeCache` before Niivue requests it.
    func loadPreprocessedVolume(
        studyID: String,
        itemID: String,
        sourceURL: URL,
        parameters: CTPreprocessingParameters
    ) async throws {
        guard let cache = urlSchemeHandler.preprocessedVolumeCache else {
            throw PreprocessedVolumeError.cacheUnavailable
        }

        let cached: PreprocessedResult? = await cache.getCached(studyID: studyID, itemID: itemID, parameters: parameters)
        let resolved: PreprocessedResult

        if let cached {
            resolved = cached
        } else {
            let start = Date()
            let result = PreprocessedResult(
                outputURL: sourceURL,
                processingTime: Date().timeIntervalSince(start),
                parameters: parameters
            )
            try await cache.store(studyID: studyID, itemID: itemID, result: result)

            guard let stored = await cache.getCached(studyID: studyID, itemID: itemID, parameters: parameters) else {
                throw PreprocessedVolumeError.failedToStore
            }
            resolved = stored
        }

        let fileName = resolved.outputURL.lastPathComponent
        let preprocessedURL = Self.preprocessedVolumeURL(
            studyID: studyID,
            itemID: itemID,
            parametersHash: parameters.parametersHash,
            fileName: fileName
        )

        try await loadImageFromUrl(url: preprocessedURL, fileName: fileName)
    }

    private static func preprocessedVolumeURL(
        studyID: String,
        itemID: String,
        parametersHash: String,
        fileName: String
    ) -> String {
        "niivue://app/preprocessed/\(studyID)/\(itemID)/\(parametersHash)/\(fileName)"
    }

    /// Loads multiple volumes from URLs (Phase 2 Task 2: multi-volume overlays).
    /// - Parameter volumeSpecs: Array of (url, name) pairs for volumes to load
    func loadVolumesFromUrls(_ volumeSpecs: [(url: String, name: String)]) async throws {
        lastErrorMessage = nil
        volumes.removeAll()
        volumeSources = volumeSpecs.map { .init(url: $0.url, name: $0.name) }

        // Build JSON array string
        let volumeArray = try volumeSpecs.map { spec -> String in
            let urlEscaped = try JavaScriptQuote.jsonStringLiteral(spec.url)
            let nameEscaped = try JavaScriptQuote.jsonStringLiteral(spec.name)
            return "{\"url\":\(urlEscaped),\"name\":\(nameEscaped)}"
        }
        let jsonArray = "[\(volumeArray.joined(separator: ","))]"

        try await callAsyncVoid("await window.loadVolumesFromUrls(\(jsonArray));")

        // Query Niivue's volume count to update our tracking
        // (onImageLoaded callbacks may be deferred)
        try await syncVolumeCount()
    }

    /// Adds volumes from URLs without clearing existing volumes (Phase 2 UI: segmentation masks/textures).
    /// - Parameter volumeSpecs: Array of (url, name) pairs to append as additional volumes.
    func addVolumesFromUrls(_ volumeSpecs: [(url: String, name: String)]) async throws {
        lastErrorMessage = nil
        volumeSources.append(contentsOf: volumeSpecs.map { .init(url: $0.url, name: $0.name) })

        // Build JSON array string
        let volumeArray = try volumeSpecs.map { spec -> String in
            let urlEscaped = try JavaScriptQuote.jsonStringLiteral(spec.url)
            let nameEscaped = try JavaScriptQuote.jsonStringLiteral(spec.name)
            return "{\"url\":\(urlEscaped),\"name\":\(nameEscaped)}"
        }
        let jsonArray = "[\(volumeArray.joined(separator: ","))]"

        try await callAsyncVoid("await window.addVolumesFromUrls(\(jsonArray));")
        try await syncVolumeCount()
    }

    /// Loads meshes from URLs (Phase 2 UI: segmentation meshes).
    /// - Parameter meshSpecs: Array of (url, name) pairs for meshes to load.
    func loadMeshesFromUrls(_ meshSpecs: [(url: String, name: String)]) async throws {
        lastErrorMessage = nil

        let meshArray = try meshSpecs.map { spec -> String in
            let urlEscaped = try JavaScriptQuote.jsonStringLiteral(spec.url)
            let nameEscaped = try JavaScriptQuote.jsonStringLiteral(spec.name)
            return "{\"url\":\(urlEscaped),\"name\":\(nameEscaped)}"
        }
        let jsonArray = "[\(meshArray.joined(separator: ","))]"

        try await callAsyncVoid("await window.loadMeshesFromUrls(\(jsonArray));")
    }

    /// Exports a thin viewer state snapshot as JSON (Phase 2 UI: sessions).
    /// - Returns: JSON string representing viewer state.
    func exportViewerStateJSON() async throws -> String {
        lastErrorMessage = nil
        return try await evaluator.callAsyncString("return window.exportViewerState()") ?? "{}"
    }

    /// Exports a session snapshot that includes volume sources + thin viewer state (Phase 2 Task 6).
    func exportSessionSnapshotJSON() async throws -> String {
        let viewerStateJSON = try await exportViewerStateJSON()
        let snapshot = try SessionSnapshotV1.make(volumeSources: volumeSources, viewerStateJSON: viewerStateJSON)
        let data = try JSONEncoder().encode(snapshot)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Applies a previously-exported viewer state JSON string (Phase 2 UI: sessions).
    /// This updates per-volume settings (colormap/opacity/frame) for currently loaded volumes.
    /// - Parameter json: Viewer state JSON string returned by `exportViewerStateJSON()`.
    func applyViewerStateJSON(_ json: String) async throws {
        lastErrorMessage = nil
        let jsonEscaped = try JavaScriptQuote.jsonStringLiteral(json)
        try await evaluator.evaluateCommand("window.applyViewerState(\(jsonEscaped))")
    }

    /// Restores a persisted session JSON string (Phase 2 Task 6).
    /// Supports both v1 session snapshots and legacy viewer-state-only JSON.
    func restoreSessionJSON(_ json: String) async throws {
        lastErrorMessage = nil

        if let data = json.data(using: .utf8),
           let snapshot = try? JSONDecoder().decode(SessionSnapshotV1.self, from: data) {
            if !snapshot.volumeSources.isEmpty {
                let specs = snapshot.volumeSources.map { (url: $0.url, name: $0.name) }
                try await loadVolumesFromUrls(specs)
            }

            let viewerStateJSON = try snapshot.viewerStateJSONString()
            try await applyViewerStateJSON(viewerStateJSON)
            return
        }

        // Legacy: thin viewer-state only
        try await applyViewerStateJSON(json)
    }

    /// Syncs the volume list from Niivue JS to Swift.
    /// This is a workaround for cases where onImageLoaded callbacks don't arrive.
    private func syncVolumeCount() async throws {
        // Use callAsyncString which properly handles the return value
        guard let jsonString = try await evaluator.callAsyncString("return window.getVolumeInfoList()"),
              let data = jsonString.data(using: .utf8) else {
            print("[WebViewManager] Failed to get volume info from Niivue")
            return
        }

        do {
            let volumeInfos = try JSONDecoder().decode([VolumeInfo].self, from: data)
            print("[WebViewManager] Niivue reports \(volumeInfos.count) volumes, we had \(volumes.count)")
            volumes = volumeInfos
        } catch {
            print("[WebViewManager] Failed to decode volume info: \(error)")
        }
    }

    // MARK: - CT Presets (CT Adaptive Engine)

    /// Sets whether the adaptive CT preset should auto-apply when new volumes finish loading (Option B).
    func setAutoApplyCTPreset(enabled: Bool) async throws {
        try await CTPresetService.setAutoApplyCTPreset(evaluator: evaluator, enabled: enabled)
    }

    /// Applies the adaptive urinary CT preset to the given volume index.
    func applyAdaptiveCTUrinaryPreset(volumeIndex: Int = 0) async throws {
        try await CTPresetService.applyAdaptivePreset(evaluator: evaluator, volumeIndex: volumeIndex)
    }

    /// Applies a named urinary CT preset to the given volume index.
    func applyCTUrinaryPreset(volumeIndex: Int = 0, presetName: String) async throws {
        try await CTPresetService.applyPreset(evaluator: evaluator, volumeIndex: volumeIndex, presetName: presetName)
    }

    /// Lists available urinary CT presets registered by the React layer.
    func listCTUrinaryPresets() async throws -> [String] {
        try await CTPresetService.listPresets(evaluator: evaluator)
    }

    // MARK: - Overlay Controls (Phase 2 Task 3) & 4D Time-Series (Phase 2 Task 4)

    /// Sets the colormap for a volume by index.
    /// - Parameters:
    ///   - volumeIndex: Index of the volume in nv.volumes
    ///   - colormap: Name of the colormap (e.g., "gray", "hot", "red")
    func setColormap(volumeIndex: Int, colormap: String) async throws {
        let colormapEscaped = try JavaScriptQuote.jsonStringLiteral(colormap)
        try await evaluator.evaluateCommand("window.setColormap(\(volumeIndex), \(colormapEscaped))")
    }

    /// Sets the opacity for a volume by index.
    /// - Parameters:
    ///   - volumeIndex: Index of the volume in nv.volumes
    ///   - opacity: Opacity value (0.0 to 1.0)
    func setOpacity(volumeIndex: Int, opacity: Double) async throws {
        if volumes.indices.contains(volumeIndex) {
            let volumeID = volumes[volumeIndex].id
            lastKnownOpacityByVolumeID[volumeID] = opacity
        }
        try await evaluator.evaluateCommand("window.setOpacity(\(volumeIndex), \(opacity))")
    }

    /// Temporarily hides/shows a volume by setting opacity to 0 and restoring the previous opacity.
    func setVolumeVisible(volumeIndex: Int, isVisible: Bool) async throws {
        if isVisible {
            let restoredOpacity: Double

            if volumes.indices.contains(volumeIndex) {
                let volumeID = volumes[volumeIndex].id
                restoredOpacity = hiddenOpacityBackupByVolumeID[volumeID]
                    ?? lastKnownOpacityByVolumeID[volumeID]
                    ?? 1.0
                hiddenOpacityBackupByVolumeID[volumeID] = nil
            } else {
                restoredOpacity = 1.0
            }

            let appliedOpacity = restoredOpacity > 0 ? restoredOpacity : 1.0
            try await setOpacity(volumeIndex: volumeIndex, opacity: appliedOpacity)
            return
        }

        if volumes.indices.contains(volumeIndex) {
            let volumeID = volumes[volumeIndex].id
            let currentOpacity = lastKnownOpacityByVolumeID[volumeID] ?? 1.0
            if currentOpacity > 0 {
                hiddenOpacityBackupByVolumeID[volumeID] = currentOpacity
            } else if hiddenOpacityBackupByVolumeID[volumeID] == nil {
                hiddenOpacityBackupByVolumeID[volumeID] = 1.0
            }
        }

        try await setOpacity(volumeIndex: volumeIndex, opacity: 0.0)
    }

    /// Removes a volume from the scene by index.
    /// Keeps Swift-side `volumeSources` aligned and re-syncs `volumes` from the JS layer.
    func removeVolumeByIndex(volumeIndex: Int) async throws {
        lastErrorMessage = nil

        let removedVolumeID = volumes.indices.contains(volumeIndex) ? volumes[volumeIndex].id : nil

        try await evaluator.evaluateCommand("window.removeVolumeByIndex(\(volumeIndex))")

        if volumeSources.indices.contains(volumeIndex) {
            volumeSources.remove(at: volumeIndex)
        }

        if let removedVolumeID {
            lastKnownOpacityByVolumeID.removeValue(forKey: removedVolumeID)
            hiddenOpacityBackupByVolumeID.removeValue(forKey: removedVolumeID)
        }

        try await syncVolumeCount()
    }

    /// Gets the list of available colormaps.
    /// - Returns: Array of colormap names
    func listColormaps() async throws -> [String] {
        guard let jsonString = try await evaluator.evaluateString("JSON.stringify(window.listColormaps())"),
              let data = jsonString.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Phase 2 Task 4: Sets the 4D frame for a volume by index.
    /// - Parameters:
    ///   - volumeIndex: Index of the volume in nv.volumes
    ///   - frame: Frame number to display (0-indexed)
    func setFrame4D(volumeIndex: Int, frame: Int) async throws {
        try await evaluator.evaluateCommand("window.setFrame4D(\(volumeIndex), \(frame))")
    }

    // MARK: - Segmentation/Draw Tooling (Phase 2 Task 5)

    /// Undoes the last drawing operation.
    func drawUndo() async throws {
        try await evaluator.evaluateCommand("window.drawUndo()")
    }

    /// Sets the opacity for drawings.
    /// - Parameter opacity: Opacity value (0.0 to 1.0)
    func setDrawOpacity(opacity: Double) async throws {
        try await evaluator.evaluateCommand("window.setDrawOpacity(\(opacity))")
    }

    /// Sets the colormap for drawings.
    /// - Parameter colormap: Name of the colormap
    func setDrawColormap(colormap: String) async throws {
        let colormapEscaped = try JavaScriptQuote.jsonStringLiteral(colormap)
        try await evaluator.evaluateCommand("window.setDrawColormap(\(colormapEscaped))")
    }

    /// Enables or disables click-to-segment mode.
    /// - Parameter enabled: Whether click-to-segment is enabled
    func setClickToSegmentEnabled(enabled: Bool) async throws {
        try await evaluator.evaluateCommand("window.setClickToSegmentEnabled(\(enabled))")
    }

    /// Applies a click-to-segment action at a screen point (CSS pixels) in the Niivue canvas.
    func clickToSegmentAtScreenPoint(x: Double, y: Double) async throws {
        try await evaluator.evaluateCommand("window.clickToSegmentAtScreenPoint(\(x), \(y))")
    }

    /// Applies Otsu thresholding to the drawing bitmap.
    /// - Parameter levels: (2-4) number of classes for thresholding.
    func drawOtsu(levels: Int) async throws {
        try await evaluator.evaluateCommand("window.drawOtsu(\(levels))")
    }

    // MARK: - DICOM Import (Phase 2 Task 9)

    /// Loads a DICOM series from a manifest URL.
    /// The manifest is a text file containing one DICOM filename per line.
    /// - Parameter manifestUrl: The manifest URL (e.g., niivue://app/dicom/series1/niivue-manifest.txt)
    func loadDicomSeriesFromManifestURL(_ manifestUrl: String) async throws {
        lastErrorMessage = nil
        let urlEscaped = try JavaScriptQuote.jsonStringLiteral(manifestUrl)

        let requestId = nextDicomLoadRequestId
        nextDicomLoadRequestId += 1
        lastDicomLoadStatus = nil

        // DICOM conversion can take several minutes on-device. Await the JS promise directly via
        // `callAsyncJavaScript`, but force the resolved value to be a string so bridging is reliable.
        let result = try await Task<String, Error>.withTimeout(
            seconds: 600,
            operation: "loadDicomSeriesFromManifestURL"
        ) {
            try await self.evaluator.callAsyncString(
                """
                try {
                  await window.loadDicomSeriesFromManifest(\(urlEscaped), \(requestId));
                  return "ok";
                } catch (error) {
                  let message = "";
                  try {
                    if (error && typeof error === "object" && "message" in error) {
                      // @ts-ignore
                      message = String(error.message);
                    } else {
                      message = String(error);
                    }
                  } catch (coercionError) {
                    message = "Unknown error";
                  }
                  return "error:" + message;
                }
                """
            )
        }

        guard let result else {
            throw NiivueError.javaScriptPromiseRejected(
                reason: "No result returned from JavaScript.",
                script: "window.loadDicomSeriesFromManifest(\(manifestUrl), requestId=\(requestId))"
            )
        }

        if result.hasPrefix("error:") {
            throw NiivueError.javaScriptPromiseRejected(
                reason: String(result.dropFirst("error:".count)),
                script: "window.loadDicomSeriesFromManifest(\(manifestUrl), requestId=\(requestId))"
            )
        }

        // Query Niivue's volume count to update our tracking (onImageLoaded callbacks may be deferred).
        try await syncVolumeCount()
    }

    // MARK: - View Controls

    /// Sets the slice type (0=Axial, 1=Coronal, 2=Sagittal, 3=Multiplanar, 4=Render).
    func setSliceType(sliceType: Int) async throws {
        currentSliceType = sliceType
        try await evaluator.evaluateCommand("window.setSliceType(\(sliceType))")
    }

    /// Sets the multiplanar layout (0=Auto, 1=Column, 2=Grid, 3=Row).
    func setLayout(layout: Int) async throws {
        try await evaluator.evaluateCommand("window.setLayout(\(layout))")
    }

    /// Sets whether the 3D crosshair is visible.
    func set3dCrosshairVisible(visible: Bool) async throws {
        try await evaluator.evaluateCommand("window.set3dCrosshairVisible(\(visible))")
    }

    /// Sets whether the 2D crosshair is visible.
    func set2dCrosshairVisible(visible: Bool) async throws {
        try await evaluator.evaluateCommand("window.set2dCrosshairVisible(\(visible))")
    }

    /// Sets the drag mode (0=None, 1=Contrast, 2=Measure, 3=Pan, 4=Slicer3D).
    func setDragMode(dragMode: Int) async throws {
        try await evaluator.evaluateCommand("window.setDragMode(\(dragMode))")
    }

    // MARK: - Drawing Controls

    /// Sets the pen value for drawing.
    /// - Parameters:
    ///   - penValue: Pen color index (0=Erase, 1=Red, etc.)
    ///   - isFilled: Whether the pen fills regions
    ///   - drawingEnabled: Whether drawing is enabled
    func setPenValue(penValue: Int, isFilled: Bool, drawingEnabled: Bool) async throws {
        try await evaluator.evaluateCommand("window.setPenValue(\(penValue), \(isFilled), \(drawingEnabled))")
    }

    /// Sets the crosshair color.
    func setCrosshairColor() async throws {
        try await evaluator.evaluateCommand("window.setCrosshairColor()")
    }

    /// Sets whether corner orientation text is visible.
    func setCornerText(isCorners: Bool) async throws {
        try await evaluator.evaluateCommand("window.setCornerText(\(isCorners))")
    }

    /// Sets whether the orientation cube is visible.
    func setOrientationCube(isOrientationCube: Bool) async throws {
        try await evaluator.evaluateCommand("window.setOrientationCube(\(isOrientationCube))")
    }

    /// Sets whether radiological convention is used.
    func setRadiological(isRadiological: Bool) async throws {
        try await evaluator.evaluateCommand("window.setRadiological(\(isRadiological))")
    }

    /// Moves the crosshair by the specified voxel offsets.
    func moveCrosshairInVox(_ x: Int, _ y: Int, _ z: Int) async throws {
        try await evaluator.evaluateCommand("window.moveCrosshairInVox(\(x),\(y),\(z))")
    }

    // MARK: - 2D Pan (Two-Finger)

    /// Captures the current 2D pan baseline for a subsequent drag pan operation.
    func beginTwoFingerPan() async throws {
        try await evaluator.evaluateCommand("window.beginTwoFingerPan()")
    }

    /// Applies 2D panning by treating the gesture as a screen-space drag from start → end.
    /// - Parameters:
    ///   - startX/startY/endX/endY: Coordinates in *screen/CSS pixels* relative to the Niivue canvas.
    func pan2DFromScreenDrag(startX: Double, startY: Double, endX: Double, endY: Double) async throws {
        try await evaluator.evaluateCommand("window.pan2DFromScreenDrag(\(startX),\(startY),\(endX),\(endY))")
    }

    /// Applies a single incremental 2D pan step (used for high-frequency updates where the native recognizer
    /// resets translation each frame).
    /// - Parameters:
    ///   - startX/startY/endX/endY: Coordinates in *screen/CSS pixels* relative to the Niivue canvas.
    func pan2DFromScreenDragIncremental(startX: Double, startY: Double, endX: Double, endY: Double) async throws {
        try await evaluator.evaluateCommand("window.pan2DFromScreenDragIncremental(\(startX),\(startY),\(endX),\(endY))")
    }

    /// Sets the 2D zoom (pan2Dxyzmm[3]) and adjusts pan so the zoom anchors around a given screen point.
    /// - Parameters:
    ///   - scale: Desired zoom scale (clamped in JS to [0.5, 10.0]).
    ///   - anchorX/anchorY: Anchor point in *screen/CSS pixels* relative to the Niivue canvas.
    func set2DZoomAtScreenPoint(scale: Double, anchorX: Double, anchorY: Double) async throws {
        try await evaluator.evaluateCommand("window.set2DZoomAtScreenPoint(\(scale),\(anchorX),\(anchorY))")
    }

    // MARK: - Gesture Command Coalescing API (2D Pan / Zoom / Window-Level)

    /// Coalesces incremental 2D pan deltas and flushes them to the JS layer at a capped rate.
    func enqueue2DPanDelta(deltaX: Double, deltaY: Double, endX: Double, endY: Double) {
        if var existing = pending2DPan {
            existing.deltaX += deltaX
            existing.deltaY += deltaY
            existing.endX = endX
            existing.endY = endY
            pending2DPan = existing
        } else {
            pending2DPan = (deltaX: deltaX, deltaY: deltaY, endX: endX, endY: endY)
        }
        scheduleGestureFlushIfNeeded()
    }

    /// Coalesces 2D zoom updates by keeping only the latest scale + anchor.
    func enqueue2DZoom(scale: Double, anchorX: Double, anchorY: Double) {
        let clampedScale = max(0.5, min(scale, 10.0))
        pending2DZoom = (scale: clampedScale, anchorX: anchorX, anchorY: anchorY)
        scheduleGestureFlushIfNeeded()
    }

    /// Coalesces Window/Level updates by keeping only the latest WW/WL.
    func enqueueIntensityWindow(volumeIndex: Int = 0, windowWidth: Double, windowLevel: Double) {
        pendingIntensityWindow = (volumeIndex: volumeIndex, windowWidth: max(1.0, windowWidth), windowLevel: windowLevel)
        scheduleGestureFlushIfNeeded()
    }

    /// Flushes any pending gesture updates immediately (useful on gesture end).
    func flushPendingGestureCommandsNow() {
        Task { @MainActor [weak self] in
            await self?.flushPendingGestureCommands()
        }
    }

    // MARK: - 2D Window/Level (Contrast & Brightness)

    struct IntensityWindow: Codable, Equatable {
        let windowWidth: Double
        let windowLevel: Double
        let calMin: Double
        let calMax: Double
    }

    /// Returns the current window/level for a volume, derived from Niivue's `cal_min`/`cal_max`.
    func getIntensityWindow(volumeIndex: Int = 0) async throws -> IntensityWindow {
        guard let jsonString = try await evaluator.callAsyncString("return window.getIntensityWindow(\(volumeIndex))"),
              let data = jsonString.data(using: .utf8) else {
            throw NSError(domain: "WebViewManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to get intensity window JSON"])
        }
        return try JSONDecoder().decode(IntensityWindow.self, from: data)
    }

    /// Sets window/level by translating WW/WL into `cal_min`/`cal_max` and refreshing the 2D layers.
    func setIntensityWindow(volumeIndex: Int = 0, windowWidth: Double, windowLevel: Double) async throws {
        try await evaluator.evaluateCommand("window.setIntensityWindow(\(windowWidth),\(windowLevel),\(volumeIndex))")
    }

    // MARK: - 2D Stack Scroll

    private func stackScrollAxis(for sliceType: Int) -> Int? {
        switch sliceType {
        case 0: return 2 // axial -> z
        case 1: return 1 // coronal -> y
        case 2: return 0 // sagittal -> x
        default: return nil
        }
    }

    /// Current slice index for the active 2D slice type (Axial/Coronal/Sagittal).
    /// Returns nil when not in a 2D slice view or when voxel state is unavailable.
    var currentSliceIndex: Int? {
        guard let axis = stackScrollAxis(for: currentSliceType),
              let vox = (lastCrosshairVox ?? lastLocationVox) else { return nil }
        return axisValue(in: vox, axis: axis)
    }

    /// Slice index derived specifically from `scene.crosshairPos` (converted to vox).
    /// Useful for distinguishing crosshair vs. cursor-under-finger updates.
    var currentCrosshairSliceIndex: Int? {
        guard let axis = stackScrollAxis(for: currentSliceType),
              let vox = lastCrosshairVox else { return nil }
        return axisValue(in: vox, axis: axis)
    }

    /// Total number of slices along the active 2D slice type axis.
    var currentTotalSlices: Int? {
        guard let axis = stackScrollAxis(for: currentSliceType),
              let total = totalSlices(for: axis) else { return nil }
        return total
    }

    private func axisValue(in vox: SIMD3<Int>, axis: Int) -> Int {
        switch axis {
        case 0: return vox.x
        case 1: return vox.y
        case 2: return vox.z
        default: return 0
        }
    }

    private func settingAxisValue(in vox: SIMD3<Int>, axis: Int, to value: Int) -> SIMD3<Int> {
        switch axis {
        case 0: return SIMD3(value, vox.y, vox.z)
        case 1: return SIMD3(vox.x, value, vox.z)
        case 2: return SIMD3(vox.x, vox.y, value)
        default: return vox
        }
    }

    private func totalSlices(for axis: Int) -> Int? {
        guard let dims = volumeDimsRAS, dims.count >= 4 else { return nil }
        let i = axis + 1
        guard i >= 1, i < dims.count else { return nil }
        return dims[i]
    }

    func handleStackScrollDragBegan(translationY _: Double, velocityY _: Double) {
        guard let axis = stackScrollAxis(for: currentSliceType),
              let vox = (lastCrosshairVox ?? lastLocationVox),
              (totalSlices(for: axis) ?? 0) > 0 else {
            resetStackScrollState()
            return
        }

        let currentIndex = axisValue(in: vox, axis: axis)

        stackScrollDebugEventCount = 0
        stackScrollAxis = axis
        stackScrollInitialSliceIndex = currentIndex
        stackScrollLastAppliedSliceIndex = currentIndex
        stackScrollPixelsPerSliceForGesture = nil
        pendingCrosshairDelta = .zero
    }

    /// Called from SwiftUI to implement 2D “stack scroll” (scrub slices).
    /// - Parameters:
    ///   - translationY: Drag translation in points, positive when dragging down.
    ///   - velocityY: Drag velocity in points/sec, positive when moving down.
    func handleStackScrollDragChanged(translationY: Double, velocityY: Double) {
        guard let axis = stackScrollAxis(for: currentSliceType),
              let vox = (lastCrosshairVox ?? lastLocationVox),
              let total = totalSlices(for: axis),
              total > 0 else {
            resetStackScrollState()
            return
        }

        if stackScrollInitialSliceIndex == nil || stackScrollAxis != axis {
            handleStackScrollDragBegan(translationY: translationY, velocityY: velocityY)
        }

        stackScrollDebugEventCount += 1
        guard let initialSliceIndex = stackScrollInitialSliceIndex,
              let lastAppliedIndex = stackScrollLastAppliedSliceIndex else { return }

        if stackScrollPixelsPerSliceForGesture == nil {
            stackScrollPixelsPerSliceForGesture = stackScrollPixelsPerSlice(forVelocityY: velocityY)
        }

        let pixelsPerSlice = stackScrollPixelsPerSliceForGesture ?? stackScrollBasePixelsPerSlice
        let steps = -Int(translationY / pixelsPerSlice)
        var newIndex = initialSliceIndex + steps
        newIndex = max(0, min(newIndex, total - 1))

        let delta = newIndex - lastAppliedIndex
        guard delta != 0 else { return }

        stackScrollLastAppliedSliceIndex = newIndex
        let updated = settingAxisValue(in: vox, axis: axis, to: newIndex)
        lastLocationVox = updated
        lastCrosshairVox = updated

        switch axis {
        case 0:
            pendingCrosshairDelta.x += delta
        case 1:
            pendingCrosshairDelta.y += delta
        case 2:
            pendingCrosshairDelta.z += delta
        default:
            break
        }
        scheduleGestureFlushIfNeeded()
    }

    func handleStackScrollDragEnded() {
        flushPendingGestureCommandsNow()
        resetStackScrollState()
    }

    private func resetStackScrollState() {
        stackScrollAxis = nil
        stackScrollInitialSliceIndex = nil
        stackScrollLastAppliedSliceIndex = nil
        stackScrollPixelsPerSliceForGesture = nil
    }

    private func stackScrollPixelsPerSlice(forVelocityY velocityY: Double) -> Double {
        let speed = abs(velocityY)
        let factor: Double

        if speed <= stackScrollVelocitySlowThreshold {
            factor = stackScrollMaxPixelsPerSliceFactor
        } else if speed >= stackScrollVelocityFastThreshold {
            factor = stackScrollMinPixelsPerSliceFactor
        } else {
            let t = (speed - stackScrollVelocitySlowThreshold) / (stackScrollVelocityFastThreshold - stackScrollVelocitySlowThreshold)
            factor = stackScrollMaxPixelsPerSliceFactor + (stackScrollMinPixelsPerSliceFactor - stackScrollMaxPixelsPerSliceFactor) * t
        }

        return stackScrollBasePixelsPerSlice * factor
    }

    private func scheduleGestureFlushIfNeeded() {
        guard gestureFlushTask == nil else { return }

        gestureFlushTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: gestureFlushIntervalNanoseconds)
                } catch {
                    break
                }

                await flushPendingGestureCommands()

                if hasPendingGestureCommands == false {
                    gestureFlushTask = nil
                    break
                }
            }
        }
    }

    private var hasPendingGestureCommands: Bool {
        pendingCrosshairDelta != .zero ||
            pendingIntensityWindow != nil ||
            pending2DPan != nil ||
            pending2DZoom != nil
    }

    private func flushPendingGestureCommands() async {
        guard isReady else {
            pendingCrosshairDelta = .zero
            pendingIntensityWindow = nil
            pending2DPan = nil
            pending2DZoom = nil
            return
        }

        let crosshairDelta = pendingCrosshairDelta
        let intensityWindow = pendingIntensityWindow
        let pan = pending2DPan
        let zoom = pending2DZoom

        pendingCrosshairDelta = .zero
        pendingIntensityWindow = nil
        pending2DPan = nil
        pending2DZoom = nil

        var commands: [String] = []

        if crosshairDelta != .zero {
            commands.append("window.moveCrosshairInVox(\(crosshairDelta.x),\(crosshairDelta.y),\(crosshairDelta.z))")
        }

        if let zoom {
            commands.append("window.set2DZoomAtScreenPoint(\(zoom.scale),\(zoom.anchorX),\(zoom.anchorY))")
        }

        if let pan {
            let startX = pan.endX - pan.deltaX
            let startY = pan.endY - pan.deltaY
            commands.append("window.pan2DFromScreenDragIncremental(\(startX),\(startY),\(pan.endX),\(pan.endY))")
        }

        if let intensityWindow {
            commands.append("window.setIntensityWindow(\(intensityWindow.windowWidth),\(intensityWindow.windowLevel),\(intensityWindow.volumeIndex))")
        }

        guard commands.isEmpty == false else { return }

        do {
            try await evaluator.evaluateCommand(commands.joined(separator: ";"))
        } catch {
            print("[WebViewManager] Gesture flush failed: \(error)")
        }
    }

    // MARK: - Drawing Export (Task 5: async)

    /// Saves the current drawing and returns the base64-encoded NIfTI data.
    /// - Returns: Base64-encoded drawing data, or nil if no drawing exists.
    func saveDrawing() async throws -> String? {
        try await evaluator.callAsyncString("return await window.saveDrawing()")
    }
}
