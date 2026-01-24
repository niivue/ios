//
//  NiivueURLSchemeHandler.swift
//  NiiVue
//
//  Task 10: Custom URL scheme handler for niivue:// URLs
//  Serves bundled dist/, samples/, and imported files without base64 encoding.
//

import Foundation
import WebKit

/// Handles niivue:// URL scheme requests from the WKWebView.
/// This allows the web app to load files directly without base64 encoding.
@MainActor
final class NiivueURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let router = NiivueURLRouter()

    /// File store for resolving imported file IDs to URLs
    /// Set this before the WebView starts making requests
    var importedFileStore: ImportedFileStore?

    /// Optional debug callback for surfacing URL scheme activity to SwiftUI/UI tests.
    /// This avoids relying on device console logs.
    var onDebugUpdate: (@MainActor (String) -> Void)?

    /// DICOM series store for manifest and file serving
    /// Set this before the WebView starts making requests
    var dicomSeriesStore: DicomSeriesStore?

    /// Preprocessed volume cache for serving disk-backed preprocessing outputs
    /// Set this before the WebView starts making requests
    var preprocessedVolumeCache: PreprocessedVolumeCache?

    private struct ActiveWork {
        let token: UUID
        let task: Task<Void, Never>
    }

    // Larger chunks drastically reduce main-thread hop overhead when serving many small files (e.g. DICOM slices).
    // This improves throughput for JS `fetch()` over `WKURLSchemeHandler` without changing semantics.
    private let chunkSizeBytes = 512 * 1024
    private var activeWork: [ObjectIdentifier: ActiveWork] = [:]
    private var dicomManifestRequestCount = 0
    private var dicomBundleRequestCount = 0
    private var dicomFileRequestCount = 0

    enum HandlerError: Error {
        case invalidURL
        case routingFailed
        case fileNotFound
        case notImplemented
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        activeWork[taskID]?.task.cancel()
        activeWork[taskID] = nil

        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(HandlerError.invalidURL)
            return
        }

        guard let route = router.route(url) else {
            urlSchemeTask.didFailWithError(HandlerError.routingFailed)
            return
        }

        // Dispatch to appropriate handler
        switch route {
        case .dist(let path):
            serveDistFile(path: path, task: urlSchemeTask)

        case .sample(let path):
            serveSampleFile(path: path, task: urlSchemeTask)

        case .importedFile(let id):
            serveImportedFile(id: id, task: urlSchemeTask)

        case .dicomManifest(let seriesId):
            dicomManifestRequestCount += 1
            if dicomManifestRequestCount <= 3 {
                print("[NiivueURLSchemeHandler] DICOM manifest request \(dicomManifestRequestCount) seriesId=\(seriesId)")
            }
            serveDicomManifest(seriesId: seriesId, task: urlSchemeTask)

        case .dicomBundle(let seriesId):
            dicomBundleRequestCount += 1
            print("[NiivueURLSchemeHandler] DICOM bundle request \(dicomBundleRequestCount) seriesId=\(seriesId)")
            serveDicomBundle(seriesId: seriesId, task: urlSchemeTask)

        case .dicomFile(let seriesId, let fileName):
            dicomFileRequestCount += 1
            if dicomFileRequestCount <= 3 || dicomFileRequestCount % 50 == 0 {
                print("[NiivueURLSchemeHandler] DICOM file request \(dicomFileRequestCount) seriesId=\(seriesId) file=\(fileName)")
            }
            serveDicomFile(seriesId: seriesId, fileName: fileName, task: urlSchemeTask)

        case .preprocessedVolume(let studyID, let itemID, let parametersHash, let fileName):
            servePreprocessedVolume(
                studyID: studyID,
                itemID: itemID,
                parametersHash: parametersHash,
                fileName: fileName,
                task: urlSchemeTask
            )
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        activeWork[taskID]?.task.cancel()
        activeWork[taskID] = nil
    }

    // MARK: - File Serving

    private func serveDistFile(path: String, task: WKURLSchemeTask) {
        // Task 11 will implement: serve from Bundle.main.resourceURL/dist/
        guard let resourceURL = Bundle.main.resourceURL else {
            task.didFailWithError(HandlerError.fileNotFound)
            return
        }

        let fileURL = resourceURL.appendingPathComponent("dist").appendingPathComponent(path)
        serveFile(at: fileURL, task: task)
    }

    private func serveSampleFile(path: String, task: WKURLSchemeTask) {
        // Task 11 will implement: serve from Bundle.main.resourceURL/samples/
        guard let resourceURL = Bundle.main.resourceURL else {
            task.didFailWithError(HandlerError.fileNotFound)
            return
        }

        let fileURL = resourceURL.appendingPathComponent("samples").appendingPathComponent(path)
        serveFile(at: fileURL, task: task)
    }

    private func serveImportedFile(id: String, task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task as AnyObject)
        let token = UUID()

        let work = Task { @MainActor [weak self] in
            defer {
                if self?.activeWork[taskID]?.token == token {
                    self?.activeWork[taskID] = nil
                }
            }

            if Task.isCancelled { return }
            guard let store = self?.importedFileStore,
                  let fileURL = await store.url(for: id) else {
                task.didFailWithError(HandlerError.fileNotFound)
                return
            }
            if Task.isCancelled { return }
            self?.serveFile(at: fileURL, task: task)
        }

        activeWork[taskID] = ActiveWork(token: token, task: work)
    }

    private func serveFile(at url: URL, task: WKURLSchemeTask) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            task.didFailWithError(HandlerError.fileNotFound)
            return
        }

        let taskID = ObjectIdentifier(task as AnyObject)
        let token = UUID()
        let requestURL = task.request.url!
        let mimeType = mimeTypeForPath(url.path)

        let expectedContentLength: Int = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1

        let work = Task.detached(priority: .userInitiated) { [chunkSizeBytes] in
            do {
                if Task.isCancelled { return }
                let headerFields: [String: String] = {
                    var fields = ["Content-Type": mimeType]
                    if expectedContentLength >= 0 {
                        fields["Content-Length"] = "\(expectedContentLength)"
                    }
                    return fields
                }()

                let httpResponse =
                    HTTPURLResponse(url: requestURL, statusCode: 200, httpVersion: nil, headerFields: headerFields) ??
                    URLResponse(
                        url: requestURL,
                        mimeType: mimeType,
                        expectedContentLength: expectedContentLength,
                        textEncodingName: nil
                    )

                await MainActor.run {
                    task.didReceive(httpResponse)
                }

                if Task.isCancelled { return }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }

                while !Task.isCancelled {
                    let chunk = try handle.read(upToCount: chunkSizeBytes) ?? Data()
                    if chunk.isEmpty { break }
                    await MainActor.run {
                        task.didReceive(chunk)
                    }
                }

                if Task.isCancelled { return }

                await MainActor.run {
                    task.didFinish()
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    task.didFailWithError(error)
                }
            }

            await MainActor.run { [weak self] in
                if self?.activeWork[taskID]?.token == token {
                    self?.activeWork[taskID] = nil
                }
            }
        }

        activeWork[taskID] = ActiveWork(token: token, task: work)
    }

    // MARK: - DICOM Serving (Phase 2 Task 8)

    private func serveDicomManifest(seriesId: String, task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task as AnyObject)
        let token = UUID()

        let work = Task { @MainActor [weak self] in
            defer {
                if self?.activeWork[taskID]?.token == token {
                    self?.activeWork[taskID] = nil
                }
            }

            if Task.isCancelled { return }
            guard let store = self?.dicomSeriesStore else {
                task.didFailWithError(HandlerError.fileNotFound)
                return
            }

            let manifestText = await store.manifestText(for: seriesId)
            if Task.isCancelled { return }

            guard !manifestText.isEmpty else {
                task.didFailWithError(HandlerError.fileNotFound)
                return
            }

            let data = Data(manifestText.utf8)
            let requestURL = task.request.url!

            let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "text/plain; charset=utf-8",
                    "Content-Length": "\(data.count)"
                ]
            )!

            task.didReceive(response)
            task.didReceive(data)
            task.didFinish()
        }

        activeWork[taskID] = ActiveWork(token: token, task: work)
    }

    private func serveDicomFile(seriesId: String, fileName: String, task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task as AnyObject)
        let token = UUID()

        let work = Task { @MainActor [weak self] in
            defer {
                if self?.activeWork[taskID]?.token == token {
                    self?.activeWork[taskID] = nil
                }
            }

            if Task.isCancelled { return }
            guard let store = self?.dicomSeriesStore,
                  let fileURL = await store.url(for: seriesId, fileName: fileName) else {
                task.didFailWithError(HandlerError.fileNotFound)
                return
            }
            if Task.isCancelled { return }
            self?.serveFile(at: fileURL, task: task)
        }

        activeWork[taskID] = ActiveWork(token: token, task: work)
    }

    private func serveDicomBundle(seriesId: String, task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task as AnyObject)
        let token = UUID()
        let requestStart = Date()

        guard let store = dicomSeriesStore else {
            task.didFailWithError(HandlerError.fileNotFound)
            return
        }

        let requestURL = task.request.url!
        let chunkSize = chunkSizeBytes

        let work = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                if Task.isCancelled { return }
                var bytesSent: Int64 = 0
                var nextProgressBytes: Int64 = 10 * 1024 * 1024

                let entries = await store.fileEntries(for: seriesId)
                guard !entries.isEmpty else {
                    await MainActor.run { task.didFailWithError(HandlerError.fileNotFound) }
                    return
                }

                await MainActor.run {
                    self?.onDebugUpdate?("[Scheme] bundle start seriesId=\(seriesId) files=\(entries.count)")
                }

                let response = HTTPURLResponse(
                    url: requestURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "Content-Type": "application/octet-stream"
                    ]
                )!

                await MainActor.run { task.didReceive(response) }

                var header = Data()
                header.appendUInt32LE(UInt32(entries.count))
                await MainActor.run { task.didReceive(header) }
                bytesSent += Int64(header.count)

                for entry in entries {
                    if Task.isCancelled { return }

                    let nameData = Data(entry.fileName.utf8)
                    let fileSize = (try? entry.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
                    guard fileSize >= 0 else {
                        await MainActor.run { task.didFailWithError(HandlerError.fileNotFound) }
                        return
                    }
                    guard fileSize <= Int(UInt32.max) else {
                        await MainActor.run { task.didFailWithError(HandlerError.notImplemented) }
                        return
                    }

                    var fileHeader = Data()
                    fileHeader.appendUInt32LE(UInt32(nameData.count))
                    fileHeader.append(nameData)
                    fileHeader.appendUInt32LE(UInt32(fileSize))

                    await MainActor.run { task.didReceive(fileHeader) }
                    bytesSent += Int64(fileHeader.count)

                    let handle = try FileHandle(forReadingFrom: entry.url)
                    defer { try? handle.close() }

                    while !Task.isCancelled {
                        let chunk = try handle.read(upToCount: chunkSize) ?? Data()
                        if chunk.isEmpty { break }
                        if Task.isCancelled { return }
                        await MainActor.run { task.didReceive(chunk) }
                        bytesSent += Int64(chunk.count)

                        if bytesSent >= nextProgressBytes {
                            let snapshot = bytesSent
                            nextProgressBytes += 10 * 1024 * 1024
                            await MainActor.run {
                                self?.onDebugUpdate?("[Scheme] bundle progress seriesId=\(seriesId) bytes=\(snapshot)")
                            }
                        }
                    }
                }

                if Task.isCancelled { return }
                await MainActor.run { task.didFinish() }

                let elapsed = Date().timeIntervalSince(requestStart)
                print("[NiivueURLSchemeHandler] DICOM bundle served seriesId=\(seriesId) files=\(entries.count) bytes=\(bytesSent) elapsed=\(String(format: "%.2f", elapsed))s")
                await MainActor.run {
                    self?.onDebugUpdate?("[Scheme] bundle done seriesId=\(seriesId) bytes=\(bytesSent) elapsed=\(String(format: "%.2f", elapsed))s")
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { task.didFailWithError(error) }
            }

            await MainActor.run { [weak self] in
                if self?.activeWork[taskID]?.token == token {
                    self?.activeWork[taskID] = nil
                }
            }
        }

        activeWork[taskID] = ActiveWork(token: token, task: work)
    }

    // MARK: - Preprocessed Volume Serving (Phase 2)

    private func servePreprocessedVolume(
        studyID: String,
        itemID: String,
        parametersHash: String,
        fileName: String,
        task: WKURLSchemeTask
    ) {
        let taskID = ObjectIdentifier(task as AnyObject)
        let token = UUID()

        let work = Task { @MainActor [weak self] in
            defer {
                if self?.activeWork[taskID]?.token == token {
                    self?.activeWork[taskID] = nil
                }
            }

            if Task.isCancelled { return }

            guard fileName == "preprocessed.nii" || fileName == "preprocessed.nii.gz" else {
                task.didFailWithError(HandlerError.routingFailed)
                return
            }

            guard let cache = self?.preprocessedVolumeCache else {
                task.didFailWithError(HandlerError.fileNotFound)
                return
            }

            let fileURL = await cache.cachedFileURL(
                studyID: studyID,
                itemID: itemID,
                parametersHash: parametersHash,
                fileName: fileName
            )

            if Task.isCancelled { return }
            self?.serveFile(at: fileURL, task: task)
        }

        activeWork[taskID] = ActiveWork(token: token, task: work)
    }

    // MARK: - MIME Type Detection

    private func mimeTypeForPath(_ path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "html", "htm":
            return "text/html"
        case "js":
            return "application/javascript"
        case "css":
            return "text/css"
        case "json":
            return "application/json"
        case "gz":
            return "application/gzip"
        case "nii":
            return "application/octet-stream"
        case "dcm", "dicom":
            return "application/dicom"
        case "wasm":
            return "application/wasm"
        case "png":
            return "image/png"
        case "jpg", "jpeg":
            return "image/jpeg"
        case "svg":
            return "image/svg+xml"
        default:
            return "application/octet-stream"
        }
    }
}

private extension Data {
    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { buffer in
            append(contentsOf: buffer)
        }
    }
}
