//
//  WebViewManager.swift
//  NiiVue
//
//  Task 4: Refactored WebViewManager with safe quoting + async evaluation
//  Task 6: Single source of truth for loading/error UI
//

import Foundation
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

    /// List of currently loaded volumes (Phase 2: volume notifications)
    @Published var volumes: [VolumeInfo] = []

    /// Sources used to load the current `volumes` stack (Phase 2 Task 6: sessions).
    /// Used to reload volumes on session restore.
    @Published var volumeSources: [SessionSnapshotV1.VolumeSource] = []

    /// Last location string from Niivue onLocationChange (Phase 2 Task 1: HUD)
    @Published var lastLocationString: String?

    /// Last clip plane depth reported by Niivue (Phase 2 UI: 3D slice scrolling instrumentation)
    @Published var lastClipPlaneDepth: Double?

    // MARK: - Volume Info

    struct VolumeInfo: Codable, Equatable {
        let id: String
        let name: String
        let nFrame4D: Int
    }

    // MARK: - WebView

    let webView: WKWebView
    private let evaluator: JavaScriptEvaluating
    private let initializationTimeoutNanoseconds: UInt64
    private var timeoutTask: Task<Void, Never>?

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
        initializationTimeoutNanoseconds: UInt64 = 30_000_000_000
    ) {
        let config = WKWebViewConfiguration()

        // Task 11: Create and register custom URL scheme handler for niivue://
        // This must be done BEFORE creating the WKWebView
        let handler = NiivueURLSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: "niivue")

        let wk = WKWebView(frame: .zero, configuration: config)
        self.webView = wk
        self.evaluator = evaluator ?? wk
        self.initializationTimeoutNanoseconds = initializationTimeoutNanoseconds
        self.urlSchemeHandler = handler
        self.importedFileStore = ImportedFileStore()
        super.init()

        // Task 12: Wire importedFileStore to URL scheme handler
        urlSchemeHandler.importedFileStore = importedFileStore

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
        config.userContentController.add(scriptMessageHandler, name: "messageHandler")

        // WebView configuration
        webView.allowsBackForwardNavigationGestures = false
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
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let locationString = dict["string"] as? String else { return }
            lastLocationString = locationString

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
        _ = try await evaluator.callAsyncString("return await window.loadBase64Image(\(b64), \(name))")
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
        _ = try await evaluator.callAsyncString("return await window.loadImageFromUrl(\(urlEscaped), \(nameEscaped))")
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

        _ = try await evaluator.callAsyncString("return await window.loadVolumesFromUrls(\(jsonArray))")

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

        _ = try await evaluator.callAsyncString("return await window.addVolumesFromUrls(\(jsonArray))")
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

        _ = try await evaluator.callAsyncString("return await window.loadMeshesFromUrls(\(jsonArray))")
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
        try await evaluator.evaluateCommand("window.setOpacity(\(volumeIndex), \(opacity))")
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

    // MARK: - DICOM Import (Phase 2 Task 9)

    /// Loads a DICOM series from a manifest URL.
    /// The manifest is a text file containing one DICOM filename per line.
    /// - Parameter manifestUrl: The manifest URL (e.g., niivue://app/dicom/series1/niivue-manifest.txt)
    func loadDicomSeriesFromManifestURL(_ manifestUrl: String) async throws {
        let urlEscaped = try JavaScriptQuote.jsonStringLiteral(manifestUrl)
        try await evaluator.evaluateCommand("window.loadDicomSeriesFromManifest(\(urlEscaped))")
    }

    // MARK: - View Controls

    /// Sets the slice type (0=Axial, 1=Coronal, 2=Sagittal, 3=Multiplanar, 4=Render).
    func setSliceType(sliceType: Int) async throws {
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

    // MARK: - Drawing Export (Task 5: async)

    /// Saves the current drawing and returns the base64-encoded NIfTI data.
    /// - Returns: Base64-encoded drawing data, or nil if no drawing exists.
    func saveDrawing() async throws -> String? {
        try await evaluator.callAsyncString("return await window.saveDrawing()")
    }
}
