//
//  PreviewViewController.swift
//  NiiVue Quick Look preview extension
//
//  Milestone 3 scope: the scoped file transport and the lifecycle around it.
//  The request now carries an opaque same-origin document URL, and every path
//  out of a preview — completion, timeout, replacement, dismissal, deinit — is
//  generation-scoped so a stale callback cannot touch a newer preview.
//
//  Rendering the volume is Milestone 4. This milestone proves the bytes arrive:
//  the page fetches the document URL and reports the transferred byte count.
//

import UIKit
import WebKit
import QuickLook
import os

private let log = Logger(subsystem: "com.niivue.mobile.QuickLookPreview", category: "preview")

/// Structured failure codes, shared with the page's `FailureCode` union in
/// `quicklook.ts`. Bare strings cross the boundary; keep the two in sync.
///
/// `cancelled` is the one code that is recorded but never sent: by the time a
/// preview is cancelled the page is being torn down, so there is nobody left to
/// show it to. It exists so a dismissal is distinguishable from a failure in
/// the log rather than collapsing into `internal`.
enum PreviewFailure: String {
    case unreadable
    case unsupported
    case timeout
    case graphicsUnavailable = "graphics-unavailable"
    case cancelled
    case resourceLimit = "resource-limit"
    case internalFailure = "internal"
}

/// Prevents `WKUserContentController` from retaining the controller through the
/// script-message registration. Without this the controller — and with it the
/// web view, the scheme handler, and the security scope — outlives every
/// preview, which is exactly what this milestone's "twenty open/dismiss cycles"
/// gate is looking for.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(controller, didReceive: message)
    }
}

class PreviewViewController: UIViewController, QLPreviewingController, WKScriptMessageHandler, WKNavigationDelegate, UIGestureRecognizerDelegate {

    /// Files arriving as plain gzip. See `disposition(for:)`.
    private static let gzipType = "org.gnu.gnu-zip-archive"
    /// A page that never reports back must not hang Quick Look forever.
    private static let readinessTimeout: TimeInterval = 10
    /// The page came up but never finished with the document.
    private static let loadTimeout: TimeInterval = 20
    /// How long the page gets to draw its own timeout panel before the native
    /// side stops waiting for it.
    private static let timeoutGrace: TimeInterval = 2
    /// Bytes on disk. An unreadable size fails closed rather than passing the
    /// cap as zero.
    private static let maxFileBytes = 256 * 1024 * 1024
    /// Bytes **one decoded frame** may occupy, which the file cap does not
    /// bound — a small gzip can claim any dimensions. Set equal to the file cap
    /// so the rule is one sentence: a preview will not decode more than it
    /// would accept as a file. Measured headroom (Milestone 0.5) was one 9.1 MB
    /// volume costing ~300 MB across the shared WebKit processes, most of it
    /// baseline; that is one data point, not a profile, so this is a guard
    /// against hostile headers rather than a tuned budget. Raising it needs
    /// per-device measurement.
    private static let maxDecodedBytes = 256 * 1024 * 1024
    /// Cheap to read, and it is the only header we can measure without a
    /// format-specific parser. Everything else falls back to the file cap.
    private static let headerPeekBytes = 1024

    /// Extensions NiiVue loads through `loadMeshes` rather than `loadVolumes`.
    /// Milestone 5 owns the mesh path; the classification lives here because the
    /// native side is what knows the filename.
    private static let meshExtensions: Set<String> = ["gii", "mz3", "tck", "trk", "trx"]

    private var webView: WKWebView!
    private let messageHandler = WeakScriptMessageHandler()
    private var schemeHandler: PreviewSchemeHandler!

    /// The single completion gate. Nil once fired; every path checks it, so a
    /// late JavaScript message or a timeout cannot complete a request twice —
    /// Quick Look treats a double completion as a programming error.
    private var completion: ((Error?) -> Void)?
    private var request: PreviewRequest?
    /// Set when the native side already knows the preview cannot succeed. The
    /// page is still loaded, so the failure is shown in our own fallback panel
    /// rather than as a blank canvas.
    private var pendingFailure: PreviewFailure?
    /// Bumped on every request and on teardown. Timers and JavaScript
    /// completions carry the generation they were issued under and are dropped
    /// if it has moved on — Quick Look may reuse one controller for a second
    /// file, and the first file's 10 s timer must not fire into it.
    private var generation = 0
    /// True only when `startAccessingSecurityScopedResource` returned true, so
    /// the balancing `stop` is never called spuriously.
    private var scopedURL: URL?
    /// Set when the page reports `ready`, cleared by teardown. Separates "the
    /// shell never came up" from "the shell is up and the file is slow" — two
    /// failures with different deadlines and different remedies.
    private var pageIsReady = false
    /// `preparePreviewOfFile` entry. The exit gate is measured from here to the
    /// page's `loaded`, and cold extension launch is reported separately
    /// because it is not ours to fix — see `processStart`.
    private var startedAt: Date?
    /// When this extension process began, so a first preview can be told apart
    /// from a warm one in the log.
    private static let processStart = Date()

    private struct PreviewRequest {
        let displayName: String
        let fileSize: Int
        let family: String
        let documentURL: URL
    }

    private enum Disposition {
        case render
        /// Not ours. Hand it back so whatever would normally preview it can.
        case decline
    }

    // MARK: - Lifecycle

    override func loadView() {
        let config = WKWebViewConfiguration()
        let root = Bundle.main.url(forResource: "quicklook", withExtension: "html", subdirectory: "dist")!
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        schemeHandler = PreviewSchemeHandler(root: root)
        config.setURLSchemeHandler(schemeHandler, forURLScheme: PreviewSchemeHandler.scheme)
        messageHandler.delegate = self
        config.userContentController.add(messageHandler, name: "qlPreview")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        // OPAQUE, unlike the host app's web view.
        //
        // The app sets `isOpaque = false` so its SwiftUI background shows
        // through; Milestone 2 copied that here, where it is actively harmful.
        // A Quick Look panel is movable by its background, and a non-opaque view
        // lets a click read as landing on that background — so a rotate-drag
        // moved the whole window, and NiiVue kept tracking a pointer whose
        // window was sliding out from under it, which is the jitter. The page is
        // solid black regardless, so nothing is lost by owning every pixel.
        webView.isOpaque = true
        webView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        // A preview is not a browser: no swipe-back, no link navigation.
        webView.allowsBackForwardNavigationGestures = false

        // The root view handed to Quick Look is an opaque container, not the web
        // view itself, and it carries a pan recognizer that claims drags.
        //
        // A Quick Look panel is movable by its background. On Catalyst the
        // decision is made by the host's AppKit window, out of our process, so
        // the only lever we have is to make the gesture unambiguously ours:
        // UIKit claims the sequence, and `cancelsTouchesInView = false` means
        // the web view still receives every event, so NiiVue's rotation and
        // crosshair tracking are untouched.
        //
        // UNVERIFIED from here — it cannot be exercised without Finder, and two
        // earlier attempts at this symptom (preventDefault in the page, then
        // `isOpaque`) were each necessary but not sufficient. Both are kept
        // because they fixed real, separate problems.
        let container = UIView()
        container.isOpaque = true
        container.backgroundColor = .black
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)

        let claim = UIPanGestureRecognizer(target: self, action: #selector(absorbDrag(_:)))
        claim.cancelsTouchesInView = false
        claim.delaysTouchesBegan = false
        claim.delaysTouchesEnded = false
        claim.delegate = self
        container.addGestureRecognizer(claim)

        view = container
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    /// Intentionally empty: the recognizer exists to claim the drag for UIKit,
    /// not to act on it. NiiVue does the actual work from its own pointer
    /// events, which still arrive because the recognizer cancels nothing.
    @objc private func absorbDrag(_ recognizer: UIPanGestureRecognizer) {}

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Dismissal during a load must release the file and stop the transfer
        // promptly rather than at deinit, which Quick Look may defer.
        teardown(reason: .cancelled)
    }

    deinit {
        // Not on the main thread by contract. Everything that must run there is
        // captured and hopped; the rest is safe anywhere.
        schemeHandler?.invalidateDocument()
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
        }
        let dying: WKWebView? = webView
        DispatchQueue.main.async {
            dying?.stopLoading()
            dying?.configuration.userContentController.removeAllScriptMessageHandlers()
        }
    }

    /// Release everything the current preview holds and invalidate its
    /// generation. Idempotent; safe to call from dismissal and from a
    /// replacement request.
    private func teardown(reason: PreviewFailure) {
        generation &+= 1
        // A pending Quick Look completion must still be answered, or Quick Look
        // waits on a preview nobody is producing any more.
        finish(nil)
        request = nil
        pendingFailure = nil
        pageIsReady = false
        webView?.stopLoading()
        // Dropping the token first means an in-flight page cannot start a new
        // read of the file we are about to release.
        schemeHandler?.invalidateDocument()
        if let scopedURL {
            scopedURL.stopAccessingSecurityScopedResource()
            self.scopedURL = nil
        }
        if reason != .cancelled {
            log.notice("preview torn down: \(reason.rawValue, privacy: .public)")
        }
    }

    // MARK: - Routing

    /// Decide whether this file is ours to draw.
    ///
    /// We claim `org.gnu.gnu-zip-archive` because that is the only way `.nii.gz`
    /// can reach us — macOS resolves a type from the last extension component
    /// only, so a compound `nii.gz` UTI never matches. That makes us the
    /// previewer for *every* `.gz` on the machine, which is a responsibility.
    ///
    /// Content decides, not the filename. NIfTIViewQL and MIQ both discriminate
    /// by name, which mis-accepts a renamed file and mis-rejects a correctly
    /// formed one. The filename is consulted only when the bytes are
    /// inconclusive — i.e. a gzip variant this reader cannot inflate — where a
    /// user who named a file `.nii.gz` is better served by trying and failing
    /// visibly than by being told it is a foreign archive.
    private func disposition(for url: URL, type: String, header: Data?) -> Disposition {
        guard type == Self.gzipType else { return .render }
        if let header {
            return VolumeSniff.isNIfTI(header) ? .render : .decline
        }
        return url.lastPathComponent.lowercased().hasSuffix(".nii.gz") ? .render : .decline
    }

    /// A bounded prefix of the file, inflated if it is gzip. Runs off the main
    /// thread — see `preparePreviewOfFile`.
    private static func peekHeader(at url: URL) -> Data? {
        if let inflated = GzipPeek.inflatePrefix(ofFileAt: url) { return inflated }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: headerPeekBytes)
    }

    /// Which NiiVue loader the page should use. A gzipped file is classified on
    /// the extension *under* the `.gz`, so `surface.gii.gz` is still a mesh.
    private func family(for url: URL) -> String {
        var name = url.lastPathComponent.lowercased()
        if name.hasSuffix(".gz") {
            name = String(name.dropLast(3))
        }
        let ext = (name as NSString).pathExtension
        return Self.meshExtensions.contains(ext) ? "mesh" : "volume"
    }

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        startedAt = Date()
        // Quick Look is not documented to load the view before preparing, and
        // every path below touches the web view. Forcing it here turns a
        // hypothetical ordering change from a nil-unwrap crash into a no-op.
        loadViewIfNeeded()
        // Quick Look may hand a second file to the same controller. Release the
        // first one's file, token and timers before anything of the second's is
        // registered.
        teardown(reason: .cancelled)
        completion = handler
        let current = generation

        // Milestone 0.5 measured the previewed file as already readable inside
        // the sandbox, so this normally returns false. Claim it anyway — it
        // costs nothing and is the documented contract for provider-backed
        // files — and only balance it when it actually succeeded.
        if url.startAccessingSecurityScopedResource() {
            scopedURL = url
        }

        // Reading and inflating the header is file I/O, and this is Quick
        // Look's callback: it must not block. Everything that touches the
        // controller hops back to the main queue, where the generation check
        // makes a superseded preview's work harmless.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
            let header = Self.peekHeader(at: url)
            // Fails closed: an unreadable size refuses the file rather than
            // passing the cap as zero.
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            DispatchQueue.main.async {
                guard let self, self.generation == current else { return }
                self.begin(url: url, type: type, header: header, fileSize: size)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readinessTimeout) { [weak self] in
            // `pageIsReady`, not just `completion != nil`. The shell reporting
            // `ready` is what this timer is waiting for; once that has happened
            // a slow *load* is the load timeout's business. Checking only for an
            // outstanding completion killed any legitimate render still running
            // at ten seconds and told the user the preview "could not start".
            guard let self, self.generation == current, !self.pageIsReady,
                  self.completion != nil else { return }
            // Invalidate first: Quick Look is about to be told this preview
            // failed, so a header read still in flight must not come back and
            // start loading the document into a request nobody is waiting for.
            self.generation &+= 1
            // The shell itself never came up, so there is no fallback panel to
            // show the failure in. Completing with an error hands Quick Look
            // back its own panel, which beats an indefinite spinner.
            log.error("preview page never reported ready")
            self.finish(NSError(domain: "com.niivue.mobile.QuickLookPreview", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The preview could not start.",
            ]))
        }
    }

    /// Main-queue continuation of `preparePreviewOfFile`, once the header has
    /// been read off it.
    private func begin(url: URL, type: String, header: Data?, fileSize: Int?) {
        guard disposition(for: url, type: type, header: header) == .render else {
            // Declining, rather than drawing our own panel over someone else's
            // archive, is what NIfTIViewQL does and it is the better citizen:
            // a .tar.gz keeps whatever preview it would otherwise have had.
            log.notice("declining foreign archive")
            finish(NSError(domain: "com.niivue.mobile.QuickLookPreview", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not a NIfTI volume.",
            ]))
            return
        }

        if let failure = budgetFailure(fileSize: fileSize, header: header, url: url) {
            pendingFailure = failure
            log.error("refusing file: \(failure.rawValue, privacy: .public)")
        } else {
            request = PreviewRequest(displayName: url.lastPathComponent,
                                     fileSize: fileSize ?? -1,
                                     family: family(for: url),
                                     documentURL: schemeHandler.registerDocument(url, fileName: url.lastPathComponent))
        }

        webView.load(URLRequest(url: PreviewSchemeHandler.pageURL()))
    }

    /// Why this file must not be handed to the page, if it must not be.
    ///
    /// Both limits are checked before a single byte reaches WebKit. The decoded
    /// check is the one that matters for a hostile file: the size cap passes a
    /// small gzip that claims enormous dimensions, and the allocation it
    /// provokes happens inside the content process, where running out is a
    /// crash rather than an error we can report.
    private func budgetFailure(fileSize: Int?, header: Data?, url: URL?) -> PreviewFailure? {
        guard let fileSize else { return .unreadable }
        if fileSize > Self.maxFileBytes { return .resourceLimit }
        // Two independent bounds, because neither covers the other.
        //
        // The header budget is exact and gives a truthful message, but needs a
        // parser per format, so it only covers NIfTI.
        if let header, let decoded = VolumeSniff.decodedSize(header) {
            if decoded > Self.maxDecodedBytes {
                log.error("header claims \(decoded / (1024 * 1024)) MB decoded")
                return .resourceLimit
            }
        }
        // The inflate bound is format-agnostic and is the ONLY thing standing
        // between a compressed MGZ/NRRD/GIFTI bomb and the content process: a
        // 2.65 MB gzip measured at 5.4 GiB resident. It stops as soon as the
        // limit is passed, so the cost is the limit, not the expansion.
        if let url, VolumeSniff.inflatedSizeExceeds(url, Self.maxDecodedBytes) {
            log.error("gzip payload exceeds the decoded budget")
            return .resourceLimit
        }
        return nil
    }

    private static func failed(_ message: String) -> NSError {
        NSError(domain: "com.niivue.mobile.QuickLookPreview", code: 4,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    /// Fire the completion gate exactly once.
    private func finish(_ error: Error?) {
        guard let pending = completion else { return }
        completion = nil
        pending(error)
    }

    // MARK: - Page messages

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? String,
              let data = body.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stage = payload["stage"] as? String else { return }

        switch stage {
        case "ready":
            pageIsReady = true
            dispatchRequest()
        case "loaded":
            // The Milestone 7 gate, reported at the one point that can measure
            // it. `launch` is the cold-start cost Quick Look imposes before we
            // are called at all; it is deliberately separate from `prepare`,
            // which is the part this code controls.
            if let startedAt {
                let prepare = Date().timeIntervalSince(startedAt) * 1000
                let launch = startedAt.timeIntervalSince(Self.processStart) * 1000
                log.notice("preview loaded in \(prepare, format: .fixed(precision: 0)) ms (extension launch \(launch, format: .fixed(precision: 0)) ms)")
            }
            finish(nil)
        case "failed":
            let code = payload["code"] as? String ?? PreviewFailure.internalFailure.rawValue
            log.error("preview failed: \(code, privacy: .public)")
            // Still a successful *request*: the page is showing its own fallback,
            // which the product contract requires over a blank canvas. Completing
            // with an error here would replace that with Quick Look's generic
            // panel and lose the explanation.
            finish(nil)
        default:
            break
        }
    }

    /// Hand the page its one request, or its one failure.
    private func dispatchRequest() {
        let current = generation
        if let failure = pendingFailure {
            call("await window.niivuePreview.fail(code);", ["code": failure.rawValue])
            return
        }
        guard let request else { return }
        let payload: [String: Any] = [
            "url": request.documentURL.absoluteString,
            "displayName": request.displayName,
            "fileSize": request.fileSize,
            "family": request.family,
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else {
            // `render` was never called, so the page is sitting on its spinner.
            finish(Self.failed("The preview could not start."))
            return
        }
        // callAsyncJavaScript with an argument, never string interpolation into
        // source — the filename is attacker-influenced text.
        call("await window.niivuePreview.render(JSON.parse(request));", ["request": text])

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.loadTimeout) { [weak self] in
            guard let self, self.generation == current, self.completion != nil else { return }
            // The shell is up, so the page can explain this itself.
            log.error("document load timed out")
            self.call("await window.niivuePreview.fail(code);", ["code": PreviewFailure.timeout.rawValue])
            // Asking the page to explain itself only works if the page is
            // alive. A hung or jetsammed content process will never run that
            // call and never post `failed`, which left the completion pending
            // for good. Complete natively if the page has not answered shortly.
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeoutGrace) { [weak self] in
                guard let self, self.generation == current, self.completion != nil else { return }
                log.error("page did not answer the timeout; completing natively")
                self.finish(NSError(domain: "com.niivue.mobile.QuickLookPreview", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "The preview timed out.",
                ]))
            }
        }
    }

    private func call(_ script: String, _ arguments: [String: Any]) {
        let current = generation
        webView.callAsyncJavaScript(script, arguments: arguments, in: nil, in: .page) { [weak self] result in
            guard let self, self.generation == current else { return }
            if case .failure(let error) = result {
                // The page is mid-spinner or mid-draw and will not recover.
                log.error("page call failed: \(error.localizedDescription, privacy: .public)")
                self.finish(Self.failed("The preview could not be drawn."))
            }
        }
    }

    // MARK: - Navigation policy

    /// Only our own bundled page may ever load. With the network entitlement
    /// present for WebKit's sake, this and the CSP are what keep the extension
    /// genuinely offline.
    ///
    /// The document route is fetch-only and must never become the top-level
    /// document — the same rule the host app applies to its picked-file route.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let allowed = url?.scheme == PreviewSchemeHandler.scheme
            && url?.host == PreviewSchemeHandler.host
            && url?.path.split(separator: "/").first != "document"
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("preview page failed to load: \(error.localizedDescription, privacy: .public)")
        // Nothing ever rendered — the container is solid black. Completing with
        // success here hands the user a blank panel and calls it a preview.
        finish(Self.failed("The preview could not be loaded."))
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("preview content process terminated")
        // This is where a resource-limit kill lands. The web view is blank, so
        // the only honest answer to Quick Look is an error.
        finish(Self.failed("The preview ran out of resources."))
    }
}
