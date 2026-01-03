//
//  NiivueURLRouterTests.swift
//  NiiVueTests
//
//  Task 10: Tests for NiivueURLRouter custom scheme routing
//

import XCTest
import WebKit
@testable import NiiVue

final class NiivueURLRouterTests: XCTestCase {
    func testRouterRejectsPathTraversal() {
        let router = NiivueURLRouter()
        XCTAssertNil(router.route(URL(string: "niivue://app/samples/../secrets.txt")!))
        XCTAssertNil(router.route(URL(string: "niivue://app/samples/%2e%2e/secrets.txt")!))
    }

    func testRouterRejectsDotPath() {
        let router = NiivueURLRouter()
        XCTAssertNil(router.route(URL(string: "niivue://app/./hidden")!))
    }

    func testRouterRejectsWrongScheme() {
        let router = NiivueURLRouter()
        XCTAssertNil(router.route(URL(string: "http://app/samples/test.nii.gz")!))
        XCTAssertNil(router.route(URL(string: "file://app/samples/test.nii.gz")!))
    }

    func testRouterRejectsWrongHost() {
        let router = NiivueURLRouter()
        XCTAssertNil(router.route(URL(string: "niivue://other/samples/test.nii.gz")!))
    }

    func testRouterRoutesDistPath() {
        let router = NiivueURLRouter()
        let route = router.route(URL(string: "niivue://app/index.html")!)
        if case .dist(let path) = route {
            XCTAssertEqual(path, "index.html")
        } else {
            XCTFail("Expected .dist route")
        }
    }

    func testRouterRoutesDistAssets() {
        let router = NiivueURLRouter()
        let route = router.route(URL(string: "niivue://app/assets/index-abc123.js")!)
        if case .dist(let path) = route {
            XCTAssertEqual(path, "assets/index-abc123.js")
        } else {
            XCTFail("Expected .dist route")
        }
    }

    func testRouterRoutesRootToIndexHtml() {
        let router = NiivueURLRouter()
        let route = router.route(URL(string: "niivue://app/")!)
        if case .dist(let path) = route {
            XCTAssertEqual(path, "index.html")
        } else {
            XCTFail("Expected .dist route with index.html")
        }
    }

    func testRouterRoutesSamples() {
        let router = NiivueURLRouter()
        let route = router.route(URL(string: "niivue://app/samples/T1w_DEMO.nii.gz")!)
        if case .sample(let path) = route {
            XCTAssertEqual(path, "T1w_DEMO.nii.gz")
        } else {
            XCTFail("Expected .sample route")
        }
    }

    func testRouterRoutesImportedFiles() {
        let router = NiivueURLRouter()
        let route = router.route(URL(string: "niivue://app/files/abc123-def456")!)
        if case .importedFile(let id) = route {
            XCTAssertEqual(id, "abc123-def456")
        } else {
            XCTFail("Expected .importedFile route")
        }
    }

    func testRouterRejectsFilesWithoutId() {
        let router = NiivueURLRouter()
        XCTAssertNil(router.route(URL(string: "niivue://app/files/")!))
    }
}

final class NiivueURLSchemeHandlerStreamingTests: XCTestCase {
    func testImportedFileIsStreamedInMultipleChunks() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let expectedData = Data((0..<(256 * 1024 + 7)).map { UInt8(truncatingIfNeeded: $0) })
        let fileURL = tempDir.appendingPathComponent("big.bin")
        try expectedData.write(to: fileURL)

        let id = UUID().uuidString
        let store = ImportedFileStore(libraryDirectory: tempDir)
        await store.register(
            importedFile: FileImportService.ImportedFile(
                id: id,
                originalFileName: "big.bin",
                localURL: fileURL
            )
        )

        let finished = expectation(description: "scheme task finished")
        let schemeTask = MockURLSchemeTask(
            url: URL(string: "niivue://app/files/\(id)")!,
            finished: finished
        )

        let handler = await MainActor.run { () -> NiivueURLSchemeHandler in
            let handler = NiivueURLSchemeHandler()
            handler.importedFileStore = store
            return handler
        }

        await MainActor.run {
            handler.webView(WKWebView(frame: .zero), start: schemeTask)
        }

        await fulfillment(of: [finished], timeout: 2.0)

        XCTAssertNil(schemeTask.failedError)
        XCTAssertTrue(schemeTask.didFinishCalled)
        XCTAssertEqual(schemeTask.nonMainThreadCallbackCount, 0)
        XCTAssertEqual(schemeTask.receivedResponses.count, 1)
        XCTAssertGreaterThan(schemeTask.receivedDataChunks.count, 1)

        var combined = Data()
        for chunk in schemeTask.receivedDataChunks {
            combined.append(chunk)
        }
        XCTAssertEqual(combined, expectedData)
    }
}

private final class MockURLSchemeTask: NSObject, WKURLSchemeTask {
    let request: URLRequest
    private let finished: XCTestExpectation

    private(set) var receivedResponses: [URLResponse] = []
    private(set) var receivedDataChunks: [Data] = []
    private(set) var didFinishCalled = false
    private(set) var failedError: Error?
    private(set) var nonMainThreadCallbackCount = 0

    init(url: URL, finished: XCTestExpectation) {
        self.request = URLRequest(url: url)
        self.finished = finished
        super.init()
    }

    func didReceive(_ response: URLResponse) {
        if !Thread.isMainThread { nonMainThreadCallbackCount += 1 }
        receivedResponses.append(response)
    }

    func didReceive(_ data: Data) {
        if !Thread.isMainThread { nonMainThreadCallbackCount += 1 }
        receivedDataChunks.append(data)
    }

    func didFinish() {
        if !Thread.isMainThread { nonMainThreadCallbackCount += 1 }
        didFinishCalled = true
        finished.fulfill()
    }

    func didFailWithError(_ error: Error) {
        if !Thread.isMainThread { nonMainThreadCallbackCount += 1 }
        failedError = error
        finished.fulfill()
    }
}
