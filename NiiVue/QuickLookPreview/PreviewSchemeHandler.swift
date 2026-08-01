//
//  PreviewSchemeHandler.swift
//  Serves the extension's bundled web assets over a private scheme.
//
//  Milestone 2 scope: bundle assets only. The scoped *document* route is
//  Milestone 3 and is deliberately absent here, so this milestone cannot
//  accidentally read document bytes.
//
//  A custom scheme rather than `file://` for the same reason as the host app:
//  Vite emits `<script type="module" crossorigin>`, and a `file://` page is an
//  opaque origin, so module loading is CORS-blocked.
//

import Foundation
import WebKit

final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "niivue-preview"
    static let host = "preview"

    private let root: URL
    private let readsLock = NSLock()
    private var reads: [ObjectIdentifier: ReadState] = [:]

    /// Main-queue confined — the same rule the host app learned the hard way.
    /// `WKURLSchemeTask` raises an uncatchable Objective-C exception if it is
    /// messaged after WebKit has stopped it, and WebKit marks a task stopped
    /// *before* calling `stop`, so no background flag check can be atomic
    /// against it. Sharing the main queue is what makes it safe.
    private final class ReadState {
        var cancelled = false
    }

    init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        super.init()
    }

    static func pageURL() -> URL {
        URL(string: "\(scheme)://\(host)/dist/quicklook.html")!
    }

    private static let mimeTypes = [
        "html": "text/html", "js": "text/javascript", "css": "text/css",
        "json": "application/json", "svg": "image/svg+xml", "png": "image/png",
        "woff2": "font/woff2", "wasm": "application/wasm",
    ]

    /// Containment is checked on **path components**, never `hasPrefix`:
    /// `/root` is a string prefix of `/rootlike/secret`.
    private func fileURL(for url: URL) -> URL? {
        let relative = url.path.split(separator: "/").joined(separator: "/")
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

    /// The extension carries `com.apple.security.network.client` because WebKit
    /// will not start without it. This CSP is what makes "offline" true in
    /// practice rather than merely intended: no origin but our own is reachable,
    /// so the capability is never exercisable by page script.
    private func response(for requestURL: URL, mime: String, length: Int) -> URLResponse? {
        HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mime,
                "Content-Length": String(length),
                "Content-Security-Policy":
                    "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; "
                    + "connect-src 'self'; img-src 'self' data: blob:; font-src 'self'; "
                    + "worker-src 'self' blob:; object-src 'none'; base-uri 'none'; "
                    + "frame-ancestors 'none'",
                "X-Content-Type-Options": "nosniff",
            ])
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, url.host == Self.host else {
            task.didFailWithError(URLError(.unsupportedURL))
            return
        }
        guard let file = fileURL(for: url) else {
            task.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        let mime = Self.mimeTypes[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let id = ObjectIdentifier(task as AnyObject)
        let state = ReadState()
        readsLock.lock()
        reads[id] = state
        readsLock.unlock()

        // Bundle assets are small and finite; read them off the main thread but
        // deliver on it.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            defer {
                self.readsLock.lock()
                self.reads.removeValue(forKey: id)
                self.readsLock.unlock()
            }
            let data = try? Data(contentsOf: file)
            DispatchQueue.main.async {
                guard !state.cancelled else { return }
                guard let data, let response = self.response(for: url, mime: mime, length: data.count) else {
                    task.didFailWithError(URLError(.cannotParseResponse))
                    return
                }
                task.didReceive(response)
                task.didReceive(data)
                task.didFinish()
            }
        }
    }

    /// Delivered on the main queue, which is what makes the confinement work.
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task as AnyObject)
        readsLock.lock()
        let state = reads[id]
        readsLock.unlock()
        state?.cancelled = true
    }
}
