//
//  ContentView.swift
//  NiiVue
//
//  Created by Taylor Hanayik on 11/04/2024.
//

import SwiftUI
import WebKit
import Foundation
import UniformTypeIdentifiers

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var presented: Bool // To control the presentation state
    var onPick: (URL) -> Void // Closure to handle the picked document
    
    /// NiiVue reads far more than NIfTI — mgh/mgz, nrrd/nhdr, mha/mhd, mif/mih,
    /// AFNI head/brik, npy/npz, vmr/v16, src, fib, ecat, iwi.cbor — and almost
    /// none of those have a registered system UTI, so a `UTType(filenameExtension:)`
    /// list greys them out in the picker. Narrowing to `["nii","gz"]` was a
    /// capability regression: it blocked formats the renderer handles fine.
    ///
    /// So the picker stays permissive and the *failure* path carries the weight —
    /// a file NiiVue rejects produces a named alert rather than a silent no-op.
    /// Validation lives in one place; it is just not the picker.
    private static let importTypes: [UTType] = [.data]

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Keep the security-scoped URL. The web view reads it through the native
        // scheme handler, so copying a full volume into tmp/ is unnecessary.
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: Self.importTypes, asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // No need to implement anything here for the picker
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
    }
}

/// Presents the system save UI for a finished export.
/// Mac Catalyst maps this to `NSSavePanel`; iOS/iPadOS shows the Files "Save to"
/// sheet. Using it means the app never has to claim a drawing was "saved to the
/// app folder" — a location the user cannot reach on a Mac.
struct DocumentExporter: UIViewControllerRepresentable {
    @Binding var presented: Bool
    let url: URL
    var onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentExporter
        init(_ exporter: DocumentExporter) { self.parent = exporter }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.presented = false
            parent.onFinish(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.presented = false
            parent.onFinish(false)
        }
    }
}

/// Serves the bundled web app over a custom scheme instead of `file://`.
///
/// Vite emits `<script type="module" crossorigin src="./assets/…">`, and a
/// `file://` page is an opaque origin, so module loading is CORS-blocked. The
/// previous workaround was two undocumented WebKit preferences set via KVC
/// (`allowFileAccessFromFileURLs`, `allowUniversalAccessFromFileURLs`), which
/// are private API — an App Store risk, an uncatchable `NSUnknownKeyException`
/// if WebKit ever renames them, and they handed page JavaScript read access to
/// the whole app container.
///
/// A custom scheme gives the page a real, ordinary origin, so same-origin module
/// loading just works. Requests are resolved strictly inside `root`; anything
/// that escapes it is refused. A single security-scoped user document can also be
/// exposed below the same origin, which lets NiiVue fetch the source without a
/// native Data/base64/WebKit payload chain.
final class BundleSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "niivue-app"
    static let host = "app"

    private let root: URL
    private let documentLock = NSLock()
    private var document: (token: String, url: URL, fileName: String)?
    private let readsLock = NSLock()
    private var reads: [ObjectIdentifier: ReadState] = [:]

    private static let chunkSize = 1024 * 1024

    /// `cancelled` is **main-queue confined**, and so is every `task.*` call —
    /// see `deliver(_:_:)`. A lock here would not be enough: WebKit marks a task
    /// stopped *before* it calls `webView(_:stop:)`, so any "check a flag, then
    /// send" sequence that spans two queues can still send to a stopped task,
    /// and `WKURLSchemeTask` answers that with an Objective-C exception Swift
    /// cannot catch. Sharing one queue with `stop` is what makes it atomic.
    private final class ReadState {
        var cancelled = false
    }

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        super.init()
    }

    /// Entry point for the served app.
    static func indexURL() -> URL {
        URL(string: "\(scheme)://\(host)/index.html")!
    }

    /// Register the current user-picked document and return a same-origin URL
    /// whose path contains only an opaque token and the original filename.
    func registerDocument(_ url: URL, fileName: String) -> URL {
        let token = UUID().uuidString
        documentLock.lock()
        document = (token: token, url: url, fileName: fileName)
        documentLock.unlock()

        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        // Encode the filename ourselves rather than letting the `path` setter do
        // it: that setter leaves a literal `%` alone, so a file named `a%2Fb.nii`
        // would round-trip through `url.path` as `a/b.nii` — four path components
        // instead of three, and a refused load. Escaping everything non-alphanumeric
        // makes the decode exact for any filename the system can produce.
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        components.percentEncodedPath = "/document/\(token)/\(encoded)"
        return components.url!
    }

    private static let mimeTypes = [
        "html": "text/html", "js": "text/javascript", "mjs": "text/javascript",
        "css": "text/css", "json": "application/json", "png": "image/png",
        "jpg": "image/jpeg", "jpeg": "image/jpeg", "svg": "image/svg+xml",
        "wasm": "application/wasm", "gz": "application/gzip",
        "map": "application/json", "woff2": "font/woff2",
    ]

    private func fileURL(for url: URL) -> URL? {
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.first == "document" {
            guard parts.count == 3 else { return nil }
            documentLock.lock()
            let registered = document
            documentLock.unlock()
            guard registered?.token == parts[1], registered?.fileName == parts[2] else { return nil }
            return registered?.url
        }

        let relative = parts.joined(separator: "/")
        let candidate = root.appendingPathComponent(relative)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootParts = root.pathComponents
        let candidateParts = candidate.pathComponents
        guard candidateParts.count > rootParts.count,
              Array(candidateParts.prefix(rootParts.count)) == rootParts else {
            return nil
        }
        return candidate
    }

    /// Nil if the response cannot be built with its security headers. Failing
    /// closed matters: the `URLResponse` fallback this replaced would have served
    /// the page with no CSP and no `nosniff` rather than not at all.
    private func response(for requestURL: URL, fileURL: URL, mime: String) -> URLResponse? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let length = (attributes?[.size] as? NSNumber)?.int64Value ?? -1
        var headers = [
            "Content-Type": mime,
            "Content-Security-Policy": "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; connect-src 'self'; img-src 'self' data: blob:; font-src 'self'; worker-src 'self' blob:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
            "X-Content-Type-Options": "nosniff",
        ]
        if length >= 0 {
            headers["Content-Length"] = String(length)
        }
        return HTTPURLResponse(url: requestURL,
                               statusCode: 200,
                               httpVersion: "HTTP/1.1",
                               headerFields: headers)
    }

    private func finishRead(_ id: ObjectIdentifier) {
        readsLock.lock()
        reads.removeValue(forKey: id)
        readsLock.unlock()
    }

    /// Run `body` on the main queue unless the task has been stopped, reporting
    /// whether it ran. `webView(_:stop:)` is delivered on the main queue too, so
    /// the cancellation check and the `task.*` call cannot be split by a stop.
    ///
    /// Deliberately `sync`, not `async`: it makes the read loop wait for each
    /// chunk to be handed over, so a large file cannot pile up as hundreds of
    /// pending main-queue blocks each holding a megabyte. Nothing on the main
    /// queue ever waits on this handler, so there is no inversion.
    @discardableResult
    private func deliver(_ state: ReadState, _ body: () -> Void) -> Bool {
        var ran = false
        DispatchQueue.main.sync {
            guard !state.cancelled else { return }
            body()
            ran = true
        }
        return ran
    }

    private func serve(_ task: WKURLSchemeTask,
                       requestURL: URL,
                       fileURL: URL,
                       mime: String,
                       state: ReadState,
                       id: ObjectIdentifier) {
        defer { finishRead(id) }
        do {
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            guard let response = response(for: requestURL, fileURL: fileURL, mime: mime) else {
                deliver(state) { task.didFailWithError(URLError(.cannotParseResponse)) }
                return
            }
            guard deliver(state, { task.didReceive(response) }) else { return }

            while true {
                guard let chunk = try handle.read(upToCount: Self.chunkSize), !chunk.isEmpty else {
                    break
                }
                guard deliver(state, { task.didReceive(chunk) }) else { return }
            }
            deliver(state) { task.didFinish() }
        } catch {
            deliver(state) { task.didFailWithError(error) }
        }
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        // Only serve our own host.
        guard url.host == Self.host else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        guard let fileURL = fileURL(for: url) else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        let ext = fileURL.pathExtension.lowercased()
        let mime = Self.mimeTypes[ext] ?? "application/octet-stream"
        let id = ObjectIdentifier(urlSchemeTask as AnyObject)
        let state = ReadState()
        readsLock.lock()
        reads[id] = state
        readsLock.unlock()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            self.serve(urlSchemeTask,
                      requestURL: url,
                      fileURL: fileURL,
                      mime: mime,
                      state: state,
                      id: id)
        }
    }

    /// Delivered on the main queue, which is what makes `deliver(_:_:)` safe.
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask as AnyObject)
        readsLock.lock()
        let state = reads[id]
        readsLock.unlock()
        state?.cancelled = true
    }
}

/// Prevent WKUserContentController from retaining its owner through the
/// script-message handler registration.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// Drives the NiiVue web app inside a WKWebView.
///
/// Every viewer command goes through `window.niivueBridge` (installed by
/// `React/src/bridge.ts`); the web app reports back over the script message
/// handlers registered below.
class WebViewManager: NSObject, ObservableObject, WKScriptMessageHandler, WKNavigationDelegate {
    let webView: WKWebView

    /// True once the web app has attached NiiVue and installed `window.niivueBridge`.
    /// Nothing may be sent to the bridge before this flips.
    @Published var isViewerReady = false
    /// Latest crosshair position, as the JSON mm array NiiVue reports.
    /// Deliberately NOT `@Published`: it updates on every pointer move, and no
    /// view reads it — publishing would re-evaluate ContentView's whole body at
    /// drag rate for nothing.
    private(set) var location: String = ""

    private let contentController: WKUserContentController
    private let messageHandler: WeakScriptMessageHandler
    /// Held for clarity of ownership; `WKWebViewConfiguration` also retains it.
    private let schemeHandler: BundleSchemeHandler
    private var scopedDocumentURL: URL?
    private var scopedDocumentAccess = false
    /// Invalidates completions belonging to a page that WebKit has reloaded.
    private var pageSession = 0

    /// Message handler names the web app posts to.
    private static let channels = ["updateUI", "logMessage", "locationChange"]

    override init() {
        let controller = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = controller

        // Serve the app over a custom scheme rather than file://. This replaces
        // the two private WebKit preferences the app used to set via KVC.
        let bundleRoot = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist")!
            .deletingLastPathComponent()
        let handler = BundleSchemeHandler(root: bundleRoot)
        config.setURLSchemeHandler(handler, forURLScheme: BundleSchemeHandler.scheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = UIColor.black
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        // Web Inspector attaches arbitrary JS to a page that has file access;
        // keep that out of Release builds.
#if DEBUG
        webView.isInspectable = true
#endif
        // The viewer fills the web view; the native UI supplies all scrolling.
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false

        self.contentController = controller
        self.webView = webView
        self.schemeHandler = handler
        self.messageHandler = WeakScriptMessageHandler()
        super.init()

        messageHandler.delegate = self
        webView.navigationDelegate = self
        for channel in Self.channels {
            controller.add(messageHandler, name: channel)
        }
    }

    /// Set when the web content process dies, for the host UI to surface.
    @Published var recoveryMessage: String?
    /// Recover automatically at most once per image. Reloading re-sends the same
    /// volume, so if that volume is what exhausted memory an unguarded reload
    /// crashes again immediately and loops forever.
    private var didAutoReload = false
    private var lastReloadAt = Date.distantPast
    /// Set when the crash-loop guard declines to reload. Nothing else would ever
    /// call `load()` again — `WebView.onAppear` fired once, at launch — so the
    /// app would sit as a black rectangle with every bridge call dropped until it
    /// was force-quit, and the remedy the alert implies (open a smaller image)
    /// would silently do nothing. `allowAutoReload()` is the way back.
    private var pageIsDead = false

    /// The web content process can be jetsammed under memory pressure, and WebKit
    /// also evicts it after prolonged backgrounding. Without handling this the view
    /// goes blank and every bridge call fails silently. Note the drawing lives only
    /// in the page — a restart loses it.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // Every completion belonging to the dead page is stale, including one
        // whose request generation happens to match the current Swift state.
        isViewerReady = false
        // A termination long after the last reload is an ordinary WebKit eviction
        // (prolonged backgrounding), not the volume killing the renderer — those
        // arrive within seconds of the load. Only a quick repeat means "this image
        // is the problem", so only that case stays latched.
        let sinceLastReload = Date().timeIntervalSince(lastReloadAt)
        if didAutoReload && sinceLastReload < Self.crashLoopWindow {
            pageIsDead = true
            recoveryMessage = "The viewer stopped again after restarting. The image may be too large for this device. Opening a smaller image will restart it."
            return
        }
        didAutoReload = true
        lastReloadAt = Date()
        recoveryMessage = "The viewer restarted, so any unsaved drawing was lost."
        load()
    }

    /// A repeat termination within this window is treated as the image crashing the
    /// renderer; beyond it, as an unrelated eviction that should still recover.
    private static let crashLoopWindow: TimeInterval = 60

    /// Increments on every `load()`. The readiness watchdog compares against it so
    /// an earlier load's timer cannot fire during a later load's startup window —
    /// which previously both raised a spurious alert AND latched the watchdog off
    /// for the load that was actually at risk.
    private var loadGeneration = 0

    /// Report a page that loads but never completes the handshake. Without this a
    /// silent startup failure looks identical to a slow start: a black canvas with
    /// every native command dropped and no explanation.
    private func startReadinessWatchdog() {
        loadGeneration += 1
        let generation = loadGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            guard let self, generation == self.loadGeneration, !self.isViewerReady else { return }
            self.recoveryMessage = "The viewer did not finish starting. Reopening the app may help."
        }
    }

    /// Re-arm automatic recovery. Called when the user picks a new image, so the
    /// one-shot guard applies per image rather than per app launch — and it is
    /// also the only route out of a latched crash loop. Reviving here rather than
    /// in the alert is deliberate: a user pick is proof the user chose a
    /// *different* image, which is exactly the condition the latch was waiting
    /// for. `load()` is asynchronous, so the pending URL its caller sets straight
    /// afterwards is replayed by the new ready handshake.
    func allowAutoReload() {
        didAutoReload = false
        if pageIsDead {
            pageIsDead = false
            load()
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        recoveryMessage = "The viewer could not load: \(error.localizedDescription)"
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let pathParts = url?.path.split(separator: "/")
        let isBundlePage = url?.scheme == BundleSchemeHandler.scheme
            && url?.host == BundleSchemeHandler.host
            && pathParts?.first != "document"
        decisionHandler(isBundlePage ? .allow : .cancel)
    }

    deinit {
        webView.stopLoading()
        webView.navigationDelegate = nil
        for channel in Self.channels {
            contentController.removeScriptMessageHandler(forName: channel)
        }
        if scopedDocumentAccess, let scopedDocumentURL {
            scopedDocumentURL.stopAccessingSecurityScopedResource()
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? String ?? ""
        switch message.name {
        case "updateUI":
            // "ready" is the handshake; anything else is a startup failure the page
            // could not otherwise report (both graphics backends unavailable).
            if body == "ready" {
                isViewerReady = true
            } else {
                recoveryMessage = "The viewer could not start. \(body.replacingOccurrences(of: "error: ", with: ""))"
            }
        case "logMessage":
            print("niivue: \(body)")
        case "locationChange":
            location = body
        default:
            break
        }
    }

    /// Decode a base64 `.nii.gz` payload to a temporary file for export.
    ///
    /// Writing straight into Documents only surfaces the file on iOS, via
    /// `UIFileSharingEnabled`. Under Mac Catalyst that path is inside the app
    /// container and is effectively unreachable, so the caller presents a save
    /// panel over this temp file instead. Decoding and writing run off the main
    /// thread: the payload can be hundreds of megabytes and this is called from
    /// the WebKit completion handler, which lands on the main queue.
    private func writeDrawingToTemp(_ base64String: String,
                                    baseImageUrl: String,
                                    completion: @escaping (URL?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = Data(base64Encoded: base64String) else {
                print("Error: Base64 string is malformed.")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let dateString = dateFormatter.string(from: Date())
            // The bridge always returns gzipped NIfTI, so name the output for what
            // it is rather than inheriting the source image's extension.
            var stem = (baseImageUrl as NSString).lastPathComponent
            for suffix in [".nii.gz", ".nii"] where stem.lowercased().hasSuffix(suffix) {
                stem = String(stem.dropLast(suffix.count))
                break
            }
            // A short uuid keeps two saves in the same second from colliding.
            let id = UUID().uuidString.prefix(8)
            let name = "drawing_\(dateString)_\(id)_\(stem).nii.gz"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try data.write(to: url, options: .atomic)
                print("Drawing staged at \(url.lastPathComponent) (\(data.count) bytes)")
                DispatchQueue.main.async { completion(url) }
            } catch {
                print("Failed to write drawing:", error.localizedDescription)
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    // load the default page from the react app
    func load() {
        isViewerReady = false
        pageSession += 1
        // Served by BundleSchemeHandler, so this is an ordinary same-origin load —
        // no file:// sandbox exceptions needed.
        webView.load(URLRequest(url: BundleSchemeHandler.indexURL()))
        startReadinessWatchdog()
    }

    /// Run a `window.niivueBridge` call, logging any JS-side failure.
    private func call(_ expression: String) {
        guard isViewerReady else {
            print("niivueBridge not ready; dropped \(expression)")
            return
        }
        webView.evaluateJavaScript("window.niivueBridge.\(expression)") { _, error in
            if let error {
                print("niivueBridge.\(expression) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Keep the selected document's security scope for as long as the viewer may
    /// need to reload it after a WebKit content-process restart.
    func prepareDocumentAccess(_ url: URL) {
        guard scopedDocumentURL != url else { return }
        if scopedDocumentAccess, let scopedDocumentURL {
            scopedDocumentURL.stopAccessingSecurityScopedResource()
        }
        scopedDocumentURL = url
        scopedDocumentAccess = url.startAccessingSecurityScopedResource()
    }

    /// Hand NiiVue a same-origin URL for the selected file. The native handler
    /// streams the file in chunks, avoiding Data → base64 → IPC → atob → File.
    func loadImage(url: URL, fileName: String, completion: ((Bool) -> Void)? = nil) {
        guard isViewerReady else {
            print("niivueBridge not ready; could not load \(fileName)")
            completion?(false)
            return
        }
        prepareDocumentAccess(url)
        let session = pageSession
        let documentURL = schemeHandler.registerDocument(url, fileName: fileName)
        webView.callAsyncJavaScript(
            "return await window.niivueBridge.loadImageURL(url, fileName);",
            arguments: ["url": documentURL.absoluteString, "fileName": fileName],
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self, self.pageSession == session, self.isViewerReady else {
                // The page was replaced. Its ContentView request will be retried
                // by the new ready handshake; do not report the old callback as a
                // file failure.
                return
            }
            switch result {
            case .success(let value):
                completion?(value as? Bool == true)
            case .failure(let error):
                print("loadImage failed: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }

    /// Why an export ended. Collapsing all of these to `nil` told every user that
    /// a failed gzip, a torn-down page or an unwritable temp directory meant
    /// "draw something first", which is only true for `nothingToSave`.
    enum SaveOutcome {
        case staged(URL)
        case nothingToSave
        case failed(String)
        /// The page was replaced mid-save. The recovery alert already explains
        /// that, so the caller should stay quiet — but it must still clear its
        /// in-flight flag, which is why this is a case and not a dropped callback.
        case superseded
    }

    /// Must match `TEARDOWN_ERROR` in `React/src/bridge.ts`.
    private static let teardownError = "niivue-bridge: viewer torn down"

    /// Export the drawing layer to a temporary file, ready to hand to a save panel.
    /// `saveVolume` is asynchronous in NiiVue 1.0, so this awaits the JS promise.
    func saveDrawing(baseImageUrl: String, completion: @escaping (SaveOutcome) -> Void) {
        guard isViewerReady else {
            completion(.failed("The viewer is not running."))
            return
        }
        let session = pageSession
        webView.callAsyncJavaScript(
            "return await window.niivueBridge.saveDrawing();",
            in: nil,
            in: .page
        ) { [weak self] result in
            guard let self, self.pageSession == session, self.isViewerReady else {
                completion(.superseded)
                return
            }
            switch result {
            case .success(let value):
                guard let base64 = value as? String, !base64.isEmpty else {
                    print("saveDrawing: nothing to save")
                    completion(.nothingToSave)
                    return
                }
                self.writeDrawingToTemp(base64, baseImageUrl: baseImageUrl) { url in
                    guard let url else {
                        completion(.failed("The drawing could not be written to disk."))
                        return
                    }
                    completion(.staged(url))
                }
            case .failure(let error):
                let description = error.localizedDescription
                print("saveDrawing failed: \(description)")
                // The bridge throws this sentinel when queued work outlives the
                // controller; blaming the drawing for it would be wrong.
                completion(.failed(description.contains(Self.teardownError)
                    ? "The viewer restarted before the drawing could be saved."
                    : description))
            }
        }
    }

    func setCrosshairColor() {
        call("setCrosshairColor()")
    }

    // set multiplanar layout in Niivue
    // 0 = auto
    // 1 = column
    // 2 = grid
    // 3 = row
    func setLayout(layout: Int) {
        call("setLayout(\(layout))")
    }

    // Show the crosshair or not. NiiVue 1.0 draws the 2D in-plane cross and the
    // 3D cross with one renderer behind one flag, so this is a single toggle
    // (0.41.1 could control them separately).
    func setCrosshairVisible(visible: Bool) {
        call("setCrosshairVisible(\(visible))")
    }

    // set sliceType in Niivue
    func setSliceType(sliceType: Int) {
        call("setSliceType(\(sliceType))")
    }

    // set drag mode in Niivue
    func setDragMode(dragMode: Int) {
        call("setDragMode(\(dragMode))")
    }

    // set pen value for drawing in Niivue
    func setPenValue(penValue: Int, isFilled: Bool, drawingEnabled: Bool) {
        call("setPenValue(\(penValue), \(isFilled), \(drawingEnabled))")
    }

    // show the L/R/A/P/S/I orientation labels or not.
    // NiiVue 1.0 dropped the corner-vs-edge placement option, so this is a
    // straight visibility toggle.
    func setOrientationText(visible: Bool) {
        call("setOrientationText(\(visible))")
    }

    // set orientation cube
    func setOrientationCube(isOrientationCube: Bool) {
        call("setOrientationCube(\(isOrientationCube))")
    }

    // set radiological or not
    func setRadiological(isRadiological: Bool) {
        call("setRadiological(\(isRadiological))")
    }

    // move slice by one vox in any plane
    func moveCrosshairInVox(_ x: Int, _ y: Int, _ z: Int) {
        call("moveCrosshairInVox(\(x),\(y),\(z))")
    }

}

struct WebView: UIViewRepresentable {
    let manager: WebViewManager

    func makeUIView(context: Context) -> WKWebView {
        return manager.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // This function can be used to update the view when SwiftUI state changes.
        // However, with the WebViewManager handling WebView actions, this may not be needed.
    }
}


struct ContentView: View {
    @EnvironmentObject var sharedData: SharedData
    @StateObject private var webViewManager = WebViewManager()
    @State private var documentPickerPresented = false
    @State private var settingsSheetPresented = false
    @State private var pickedDocumentURL: URL?
    @State private var pendingImageURL: URL?
    /// Monotonic token for the pending load. A pending URL is deliberately kept
    /// separate from the accepted URL so a failed replacement cannot rename the
    /// drawing that is still on screen.
    @State private var imageLoadRequest = 0
    @State private var loadingImageRequest: Int?
    @State private var sliceType = SliceTypes.Multiplanar.rawValue // default sliceType is multiplanar
    @State private var layout = LayoutTypes.Auto.rawValue // the default is Auto
    // NiiVue 1.0's own default for the primary (left / one-finger) drag.
    @State private var dragType = DragTypes.MoveCrosshair.rawValue
    // NiiVue 1.0 collapsed the separate 2D/3D crosshair controls into one flag.
    @State private var showCrosshair = true
    @State private var penValue = PenTypes.Red.rawValue // default is red
    @State private var drawingEnabled = false // can the user draw?
    @State private var isFilled = true // is the pen filled or not?
    @State private var orientationText = true // show the L/R/A/P/S/I labels?
    @State private var orientationCube = false // by default the 3D orientation cube is hidden
    @State private var radiological = false // use radiological convention or not in Niivue
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var saveInFlight = false
    @State private var exportPresented = false
    @State private var exportURL: URL?
    /// Height of the app window, measured from the root view. Mac Catalyst sizes a
    /// sheet from its content rather than honouring `presentationDetents`, so the
    /// settings panel has to ask for a concrete height — and it should not exceed
    /// the window it sits in.
    @State private var windowHeight: CGFloat = 720
    @State private var incrementText = ""
    @State private var decrementText = ""
    @State private var sliceTypeText = ""
    
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
    
    // Raw values are NiiVue's DRAG_MODE constants, passed across the bridge as
    // bare ints. `MoveCrosshair` is 8 — the enum is deliberately non-contiguous.
    enum DragTypes: Int, CaseIterable, Identifiable {
        case MoveCrosshair = 8
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
    // This picker drives NiiVue's `primaryDragMode`, i.e. the LEFT / one-finger
    // drag — not the secondary (right) drag, which stays on `contrast`.
    // Mac Catalyst still reports `os(iOS)` as true, so the platform check has to
    // be `targetEnvironment(macCatalyst)` — an `os(macOS)` branch here is dead code.
#if targetEnvironment(macCatalyst)
    let dragLabel = "Drag action (left drag)"
#else
    let dragLabel = "Drag action (one-finger drag)"
#endif
    
    
    /// Largest source file accepted by the example. This is an input/storage
    /// policy, not a complete voxel-memory bound: decompressed size still belongs
    /// to NiiVue and depends on the header's dimensions and datatype.
    static let maxImportBytes = 256 * 1024 * 1024

    static func formatBytes(_ bytes: Int) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytes))
    }

    /// Queue a source URL for NiiVue. The scheme handler owns the file read, so
    /// this path does not first materialise the entire file in Swift.
    ///
    /// - Parameter userInitiated: true for a real user pick. Only a user pick
    ///   re-arms automatic crash recovery: the recovery path itself re-reads
    ///   through this function, and re-arming there would let a volume that kills
    ///   the web content process be retried forever.
    func loadImage(from url: URL, userInitiated: Bool = true) {
        webViewManager.prepareDocumentAccess(url)
        // Refuse oversized files up front, with a message naming the limit —
        // the alternative is an avoidable large fetch with no explanation.
        // Fail CLOSED: an unreadable size must not sail past the cap as zero.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            ?? (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
            ?? nil
        guard let size else {
            saveAlertMessage = "Could not determine the size of \(url.lastPathComponent), so it was not opened."
            showingSaveAlert = true
            return
        }
        if size > Self.maxImportBytes {
            saveAlertMessage = """
                \(url.lastPathComponent) is \(Self.formatBytes(size)). \
                The viewer can open images up to \(Self.formatBytes(Self.maxImportBytes)).
                """
            showingSaveAlert = true
            return
        }
        if userInitiated {
            webViewManager.allowAutoReload()
        }
        imageLoadRequest += 1
        pendingImageURL = url
    }
    
    func incrementSlice() {
        if (sliceType == SliceTypes.Axial.rawValue) {
            webViewManager.moveCrosshairInVox(0, 0, 1)
        } else if (sliceType == SliceTypes.Coronal.rawValue) {
            webViewManager.moveCrosshairInVox(0, 1, 0)
        } else if (sliceType == SliceTypes.Sagittal.rawValue) {
            webViewManager.moveCrosshairInVox(1, 0, 0)
        }
    }
    
    func decrementSlice() {
        if (sliceType == SliceTypes.Axial.rawValue) {
            webViewManager.moveCrosshairInVox(0, 0, -1)
        } else if (sliceType == SliceTypes.Coronal.rawValue) {
            webViewManager.moveCrosshairInVox(0, -1, 0)
        } else if (sliceType == SliceTypes.Sagittal.rawValue) {
            webViewManager.moveCrosshairInVox(-1, 0, 0)
        }
    }
    
    func rotateSliceType() {
        sliceType = (sliceType + 1) % 3
    }
    
    var shareButton: some View {
        Button(action: {
            guard !saveInFlight, !exportPresented else { return }
            saveInFlight = true
            webViewManager.saveDrawing(baseImageUrl: pickedDocumentURL?.lastPathComponent ?? "image.nii.gz") { outcome in
                saveInFlight = false
                switch outcome {
                case .staged(let url):
                    // Let the user choose the destination. On Catalyst this is a
                    // real NSSavePanel; on iOS/iPadOS it is the Files "Save to"
                    // sheet. Either way the file lands somewhere reachable.
                    exportURL = url
                    exportPresented = true
                case .nothingToSave:
                    saveAlertMessage = "Nothing was saved — draw something first."
                    showingSaveAlert = true
                case .failed(let reason):
                    saveAlertMessage = "The drawing could not be saved. \(reason)"
                    showingSaveAlert = true
                case .superseded:
                    // The recovery alert covers it; a second alert would only
                    // blame the drawing for the page dying.
                    break
                }
            }
        })
        {
            Image(systemName: "square.and.arrow.down")
                .padding()
                .foregroundColor(.white)
        }
    }

    /// The export sheet is attached to the ROOT view, not to `shareButton`.
    /// `shareButton` is only in the hierarchy `if drawingEnabled`, so a save that
    /// completes after the user turns drawing off would set `exportPresented` on a
    /// view that no longer exists: no panel, and the staged temp file orphaned
    /// because `onFinish` never runs.
    @ViewBuilder
    var exportSheet: some View {
        if let exportURL {
            DocumentExporter(presented: $exportPresented, url: exportURL) { saved in
                // The staged copy has served its purpose on every outcome — the
                // export panel copied it out, or the user cancelled. Leaving it
                // behind accumulates full-size volumes in tmp/.
                try? FileManager.default.removeItem(at: exportURL)
                self.exportURL = nil
                saveAlertMessage = saved
                    ? "Drawing saved."
                    : "Save cancelled — the drawing is still open."
                showingSaveAlert = true
            }
        }
    }

    /// Read the sample volume shipped in the bundle and hand it to the viewer.
    func loadDemoImage() {
        guard pickedDocumentURL == nil, pendingImageURL == nil else { return }
        guard let url = Bundle.main.url(forResource: "T1w_DEMO.nii", withExtension: "gz", subdirectory: "samples") else {
            print("bundled sample image is missing")
            return
        }
        // Not user-initiated: recovery is already armed at launch, and re-arming
        // here would let a demo volume that kills the content process retry forever.
        loadImage(from: url, userInitiated: false)
    }

    func loadSelectedImage() {
        guard webViewManager.isViewerReady, let url = pendingImageURL else { return }
        let request = imageLoadRequest
        guard loadingImageRequest != request else { return }
        loadingImageRequest = request
        webViewManager.loadImage(url: url, fileName: url.lastPathComponent) { success in
            // A completion from an older request must not accept its URL, clear a
            // newer pending selection, or hide the newer file's eventual failure.
            guard request == imageLoadRequest, loadingImageRequest == request else { return }
            loadingImageRequest = nil
            pendingImageURL = nil
            guard success else {
                saveAlertMessage = "Could not open \(url.lastPathComponent). The file may be unsupported, or too large for this device."
                showingSaveAlert = true
                return
            }
            pickedDocumentURL = url
            // The new volume arrived, so the previous drawing is gone (the bridge
            // closes it only after the swap succeeded). Reflect that in the UI.
            drawingEnabled = false
        }
    }

    /// Settings panel.
    ///
    /// `Form` rather than a hand-built `VStack` of padded `HStack`s: it supplies
    /// the platform's own row metrics and label/control alignment, which is what
    /// makes this legible on a Mac Catalyst window as well as an iPhone sheet.
    /// The dismiss control is a standard `.confirmationAction` toolbar button —
    /// on Catalyst that is a real titled panel with a Done button (and Escape
    /// closes it), on iPad/iPhone it is the usual top-trailing Done.
    var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("View") {
                    Picker("View type", selection: $sliceType) {
                        Text("Axial").tag(SliceTypes.Axial.rawValue)
                        Text("Coronal").tag(SliceTypes.Coronal.rawValue)
                        Text("Sagittal").tag(SliceTypes.Sagittal.rawValue)
                        Text("Multiplanar").tag(SliceTypes.Multiplanar.rawValue)
                        Text("Render").tag(SliceTypes.Render.rawValue)
                    }
                    Picker("Multiplanar layout", selection: $layout) {
                        Text("Auto").tag(LayoutTypes.Auto.rawValue)
                        Text("Column").tag(LayoutTypes.Column.rawValue)
                        Text("Grid").tag(LayoutTypes.Grid.rawValue)
                        Text("Row").tag(LayoutTypes.Row.rawValue)
                    }
                    Picker(dragLabel, selection: $dragType) {
                        Text("Move crosshair").tag(DragTypes.MoveCrosshair.rawValue)
                        Text("Contrast").tag(DragTypes.Contrast.rawValue)
                        Text("Measure").tag(DragTypes.Measure.rawValue)
                        Text("Pan").tag(DragTypes.Pan.rawValue)
                        Text("Slicer3D").tag(DragTypes.Slicer3D.rawValue)
                        Text("None").tag(DragTypes.None.rawValue)
                    }
                }

                Section("Drawing") {
                    Toggle("Drawing enabled", isOn: $drawingEnabled)
                    Picker("Pen", selection: $penValue) {
                        Label("Eraser", systemImage: "eraser").tag(PenTypes.Erase.rawValue)
                        Label("Red", systemImage: "pencil").tag(PenTypes.Red.rawValue)
                        Label("Green", systemImage: "pencil").tag(PenTypes.Green.rawValue)
                        Label("Blue", systemImage: "pencil").tag(PenTypes.Blue.rawValue)
                        Label("Cyan", systemImage: "pencil").tag(PenTypes.Cyan.rawValue)
                        Label("Yellow", systemImage: "pencil").tag(PenTypes.Yellow.rawValue)
                        Label("Purple", systemImage: "pencil").tag(PenTypes.Purple.rawValue)
                    }
                    Toggle("Auto fill pen", isOn: $isFilled)
                }

                Section("Display") {
                    Toggle("Crosshair", isOn: $showCrosshair)
                    Toggle("Orientation labels", isOn: $orientationText)
                    Toggle("Orientation cube", isOn: $orientationCube)
                    Toggle("Radiological convention", isOn: $radiological)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { settingsSheetPresented = false }
                }
            }
        }
        // Catalyst presents a fixed-size panel and ignores presentationDetents, so
        // it needs an explicit size. Grouped `Form` sections are roomy, and macOS 26
        // window chrome eats more of the panel again, so take nearly the full window
        // height rather than the small default — clamped so it never overflows the
        // window or collapses on a short one.
#if targetEnvironment(macCatalyst)
        .frame(width: 520, height: min(max(windowHeight - 40, 480), 1000))
#else
        .presentationDetents([.medium, .large])
#endif
    }

    func applyViewerSettings() {
        webViewManager.setSliceType(sliceType: sliceType)
        webViewManager.setLayout(layout: layout)
        webViewManager.setDragMode(dragMode: dragType)
        webViewManager.setCrosshairVisible(visible: showCrosshair)
        webViewManager.setPenValue(penValue: penValue, isFilled: isFilled, drawingEnabled: drawingEnabled)
        webViewManager.setOrientationText(visible: orientationText)
        webViewManager.setOrientationCube(isOrientationCube: orientationCube)
        webViewManager.setRadiological(isRadiological: radiological)
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
                    
//                    Text("\(sharedData.location)") TODO: implement
                }
                // -------------------------------------------------------------
                Spacer() // Pushes the button to the right, and text to the left
                // -------------------------------------------------------------
                Button(action: {
                    // Do NOT clear `drawingEnabled` here. The drawing is only
                    // discarded once a new volume actually loads (bridge.ts closes
                    // it after loadVolumes succeeds); clearing it up front hid the
                    // save button and lost the drawing even if the user cancelled.
                    documentPickerPresented = true
                })
                {
                    Image(systemName: "plus")
                        .padding()
                        .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
                }
                .sheet(isPresented: $documentPickerPresented) {
                    DocumentPicker(presented: $documentPickerPresented) { url in
                        // Handle the picked document URL
                        loadImage(from: url)
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
                        .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
                }
                .sheet(isPresented: $settingsSheetPresented) {
                    settingsSheet
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
                            .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
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
                            .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
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
            // show the webview
            WebView(manager: webViewManager)
                .onAppear {
                    webViewManager.load()
                } // onAppear
                .background(Color.black)
                .padding()
        }
        // The web app posts "updateUI" once NiiVue is attached and the bridge is
        // installed; that replaces the old fixed delay before the first load.
        .onChange(of: webViewManager.isViewerReady) { ready in
            if ready {
                // A load callback from the dead page is ignored. Clear its marker
                // so a pending file is replayed by this new page session.
                loadingImageRequest = nil
                loadDemoImage()
                // The source URL is intentionally retained instead of its bytes;
                // replay it after a WebKit content-process restart.
                if pendingImageURL == nil, let pickedDocumentURL {
                    loadImage(from: pickedDocumentURL, userInitiated: false)
                }
                loadSelectedImage()
                applyViewerSettings()
            }
        }
        .onChange(of: imageLoadRequest) { _ in
            if webViewManager.isViewerReady {
                loadSelectedImage()
            }
        }
        .onChange(of: webViewManager.recoveryMessage) { message in
            saveInFlight = false
            guard let message else { return }
            saveAlertMessage = message
            showingSaveAlert = true
            // Reset, or a second identical message compares equal and never fires
            // onChange — two crashes in a row would alert only once.
            webViewManager.recoveryMessage = nil
        }
        .onChange(of: sliceType) { newValue in
            print("sliceType updated to: \(newValue)")
            webViewManager.setSliceType(sliceType: newValue)
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
            webViewManager.setLayout(layout: newValue)
        }
        .onChange(of: dragType) { newValue in
            print("drag type updated to: \(newValue)")
            webViewManager.setDragMode(dragMode: newValue)
        }
        .onChange(of: showCrosshair) { newValue in
            webViewManager.setCrosshairVisible(visible: newValue)
        }
        .onChange(of: isFilled) { newValue in
            print("isFilled updated to: \(newValue)")
            webViewManager.setPenValue(penValue: penValue, isFilled: newValue, drawingEnabled: drawingEnabled)
        }
        .onChange(of: drawingEnabled) { newValue in
            print("drawingEnabled updated to: \(newValue)")
            webViewManager.setPenValue(penValue: penValue, isFilled: isFilled, drawingEnabled: newValue)
        }
        .onChange(of: orientationText) { newValue in
            print("orientationText updated to: \(newValue)")
            webViewManager.setOrientationText(visible: newValue)
        }
        .onChange(of: orientationCube) { newValue in
            print("orientationCube updated to: \(newValue)")
            webViewManager.setOrientationCube(isOrientationCube: newValue)
        }
        .onChange(of: radiological) { newValue in
            print("radiological updated to: \(newValue)")
            webViewManager.setRadiological(isRadiological: newValue)
        }
        .onChange(of: penValue) { newValue in
            print("penValue updated to: \(newValue)")
            webViewManager.setPenValue(penValue: newValue, isFilled: isFilled, drawingEnabled: drawingEnabled)
        }
        .alert(saveAlertMessage, isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        }
        .sheet(isPresented: $exportPresented) { exportSheet }
        // `DocumentExporter.onFinish` covers the two delegate outcomes, but a
        // swipe-dismissed SwiftUI sheet dismantles the representable without
        // routing through either — leaving a full-size volume in tmp/ and a
        // non-nil exportURL that makes the next save orphan another one. This is
        // idempotent: on the delegate paths exportURL is already nil by now, and
        // the picker copies the file before its callback fires, so a removal can
        // never race the export itself.
        .onChange(of: exportPresented) { presented in
            guard !presented, let url = exportURL else { return }
            try? FileManager.default.removeItem(at: url)
            exportURL = nil
        }
        .background(Color.black)
#if targetEnvironment(macCatalyst)
        // Only the Catalyst settings frame reads this; measuring on iOS would write
        // state on every rotation for a value nothing consumes.
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { windowHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { windowHeight = $0 }
            }
        )
#endif
    }
}
