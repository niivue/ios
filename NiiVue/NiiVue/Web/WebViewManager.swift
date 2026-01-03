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

    /// Last location string from Niivue onLocationChange (Phase 2 Task 1: HUD)
    @Published var lastLocationString: String?

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
    private var urlSchemeHandler: NiivueURLSchemeHandler!

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
            guard let jsonString = body as? String,
                  let data = jsonString.data(using: .utf8) else { return }
            do {
                let volumeInfo = try JSONDecoder().decode(VolumeInfo.self, from: data)
                // Update or append volume
                if let index = volumes.firstIndex(where: { $0.id == volumeInfo.id }) {
                    volumes[index] = volumeInfo
                } else {
                    volumes.append(volumeInfo)
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
        let urlEscaped = try JavaScriptQuote.jsonStringLiteral(url)
        let nameEscaped = try JavaScriptQuote.jsonStringLiteral(fileName)
        _ = try await evaluator.callAsyncString("return await window.loadImageFromUrl(\(urlEscaped), \(nameEscaped))")
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
