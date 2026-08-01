//
//  PreviewViewController.swift
//  NiiVue Quick Look preview extension
//
//  Milestone 2 scope: the preview shell. A bundled page in a WKWebView, a typed
//  message contract, a single completion gate, and a readiness timeout. The
//  request carries **no document URL** — the scoped transport is Milestone 3 —
//  so this milestone provably never touches document bytes, which is its exit
//  gate.
//

import UIKit
import WebKit
import QuickLook
import os

private let log = Logger(subsystem: "com.niivue.mobile.QuickLookPreview", category: "preview")

class PreviewViewController: UIViewController, QLPreviewingController, WKScriptMessageHandler, WKNavigationDelegate {

    /// Files arriving as plain gzip. See `disposition(for:)`.
    private static let gzipType = "org.gnu.gnu-zip-archive"
    /// A page that never reports back must not hang Quick Look forever.
    private static let readinessTimeout: TimeInterval = 10

    private var webView: WKWebView!
    /// The single completion gate. Nil once fired; every path checks it, so a
    /// late JavaScript message or a timeout cannot complete a request twice —
    /// Quick Look treats a double completion as a programming error.
    private var completion: ((Error?) -> Void)?
    private var request: PreviewRequest?

    private struct PreviewRequest {
        let displayName: String
        let fileSize: Int
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
        config.setURLSchemeHandler(PreviewSchemeHandler(root: root), forURLScheme: PreviewSchemeHandler.scheme)
        config.userContentController.add(self, name: "qlPreview")

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false
        // A preview is not a browser: no swipe-back, no link navigation.
        webView.allowsBackForwardNavigationGestures = false
        view = webView
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
    private func disposition(for url: URL, type: String) -> Disposition {
        guard type == Self.gzipType else { return .render }
        if let header = GzipPeek.inflatePrefix(ofFileAt: url) {
            return VolumeSniff.isNIfTI(header) ? .render : .decline
        }
        return url.lastPathComponent.lowercased().hasSuffix(".nii.gz") ? .render : .decline
    }

    // MARK: - QLPreviewingController

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? ""
        guard disposition(for: url, type: type) == .render else {
            // Declining, rather than drawing our own panel over someone else's
            // archive, is what NIfTIViewQL does and it is the better citizen:
            // a .tar.gz keeps whatever preview it would otherwise have had.
            log.notice("declining foreign archive \(url.lastPathComponent, privacy: .public)")
            handler(NSError(domain: "com.niivue.mobile.QuickLookPreview", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Not a NIfTI volume.",
            ]))
            return
        }

        completion = handler
        request = PreviewRequest(
            displayName: url.lastPathComponent,
            fileSize: (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)

        webView.load(URLRequest(url: PreviewSchemeHandler.pageURL()))

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.readinessTimeout) { [weak self] in
            guard let self, self.completion != nil else { return }
            log.error("preview page never reported ready")
            self.finish(nil)
        }
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
            dispatchRequest()
        case "loaded":
            finish(nil)
        case "failed":
            let code = payload["code"] as? String ?? "internal"
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

    /// Hand the page its one request. Milestone 2 sends no URL, so the page
    /// takes its synthetic branch and no document byte is read.
    private func dispatchRequest() {
        guard let request else { return }
        let payload: [String: Any] = [
            "displayName": request.displayName,
            "fileSize": request.fileSize,
            "family": "synthetic",
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: payload),
              let text = String(data: json, encoding: .utf8) else {
            finish(nil)
            return
        }
        // callAsyncJavaScript with an argument, never string interpolation into
        // source — the filename is attacker-influenced text.
        webView.callAsyncJavaScript(
            "await window.niivuePreview.render(JSON.parse(request));",
            arguments: ["request": text],
            in: nil,
            in: .page) { [weak self] result in
                if case .failure(let error) = result {
                    log.error("render call failed: \(error.localizedDescription, privacy: .public)")
                    self?.finish(nil)
                }
            }
    }

    // MARK: - Navigation policy

    /// Only our own bundled page may ever load. With the network entitlement
    /// present for WebKit's sake, this and the CSP are what keep the extension
    /// genuinely offline.
    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let url = navigationAction.request.url
        let allowed = url?.scheme == PreviewSchemeHandler.scheme && url?.host == PreviewSchemeHandler.host
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        log.error("preview page failed to load: \(error.localizedDescription, privacy: .public)")
        finish(nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        log.error("preview content process terminated")
        finish(nil)
    }
}
