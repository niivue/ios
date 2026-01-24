# NiiVueKit SDK - Detailed Test Strategy with Examples

This document provides concrete test case examples and patterns for implementing the testing strategy outlined in TESTING_REQUIREMENTS_INVENTORY.md.

---

## 1. JavaScript Bridge Command Testing

### 1.1 Volume Loading Commands

**Test File:** `VolumeCommandTests.swift`

```swift
@MainActor
final class VolumeCommandTests: XCTestCase {

    // MARK: - Basic Command Generation

    /// Verify loadVolumesFromUrls generates valid JavaScript with correct structure
    func testLoadVolumesFromUrlsGeneratesValidJavaScript() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        let volumes = [
            (url: "niivue://app/files/vol1", name: "T1.nii.gz"),
            (url: "niivue://app/files/vol2", name: "T2.nii.gz")
        ]

        try await manager.loadVolumesFromUrls(volumes)

        // Verify script was called
        XCTAssertEqual(js.scripts.count, 2)  // loadVolumes + getVolumeInfoList

        // Verify JavaScript structure
        let loadScript = js.scripts[0]
        XCTAssertTrue(loadScript.contains("return await window.loadVolumesFromUrls("))
        XCTAssertTrue(loadScript.contains("\"niivue://app/files/vol1\""))
        XCTAssertTrue(loadScript.contains("\"niivue://app/files/vol2\""))
        XCTAssertTrue(loadScript.contains("\"T1.nii.gz\""))
        XCTAssertTrue(loadScript.contains("\"T2.nii.gz\""))
    }

    /// Verify JSON array structure in JavaScript call
    func testLoadVolumesFromUrlsBuildsCorrectJSONArray() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadVolumesFromUrls([
            (url: "file1", name: "a.nii.gz"),
            (url: "file2", name: "b.nii.gz")
        ])

        let script = js.scripts[0]

        // Verify it's a JSON array with correct field names
        XCTAssertTrue(script.contains("\"url\":"))
        XCTAssertTrue(script.contains("\"name\":"))

        // Verify no syntax errors (basic check)
        XCTAssertTrue(script.contains("[") && script.contains("]"))
    }

    // MARK: - Special Character Handling

    /// Verify filenames with quotes are properly escaped
    func testLoadVolumesEscapesDoubleQuotesInFilenames() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadVolumesFromUrls([
            (url: "test", name: "file\"with\"quotes.nii.gz")
        ])

        let script = js.scripts[0]
        // In JSON, double quotes should be escaped
        XCTAssertTrue(script.contains("\\\"with\\\"quotes"))
    }

    /// Verify filenames with newlines and tabs are escaped
    func testLoadVolumesEscapesWhitespaceInFilenames() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadVolumesFromUrls([
            (url: "test", name: "file\nwith\nnewlines.nii.gz")
        ])

        let script = js.scripts[0]
        // Newlines should be escaped as \n in JSON
        XCTAssertTrue(script.contains("\\n"))
    }

    /// Verify backslashes are properly escaped
    func testLoadVolumesEscapesBackslashesInFilenames() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadVolumesFromUrls([
            (url: "test", name: "path\\to\\file.nii.gz")
        ])

        let script = js.scripts[0]
        // Backslashes should be escaped as \\ in JSON
        XCTAssertTrue(script.contains("\\\\"))
    }

    // MARK: - URL Handling

    /// Verify special characters in URLs are handled correctly
    func testLoadVolumesHandlesURLsWithSpecialCharacters() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadVolumesFromUrls([
            (url: "niivue://app/files/id-with-dashes", name: "test.nii.gz"),
            (url: "niivue://app/files/id_with_underscores", name: "test2.nii.gz")
        ])

        let script = js.scripts[0]
        XCTAssertTrue(script.contains("id-with-dashes"))
        XCTAssertTrue(script.contains("id_with_underscores"))
    }

    // MARK: - Error Handling

    /// Verify error propagation from JavaScript evaluator
    func testLoadVolumesThrowsErrorWhenEvaluatorFails() async throws {
        let js = MockJavaScriptEvaluator()
        let testError = NSError(domain: "JSError", code: 123)
        js.shouldThrowError = testError
        let manager = WebViewManager(evaluator: js)

        do {
            try await manager.loadVolumesFromUrls([
                (url: "test", name: "test.nii.gz")
            ])
            XCTFail("Should have thrown error")
        } catch let error as NSError {
            XCTAssertEqual(error.code, 123)
            XCTAssertEqual(error.domain, "JSError")
        }
    }

    // MARK: - Empty and Edge Cases

    /// Verify empty volume list is handled
    func testLoadVolumesWithEmptyList() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadVolumesFromUrls([])

        let script = js.scripts[0]
        XCTAssertTrue(script.contains("[]"))
    }

    /// Verify very long filenames are handled
    func testLoadVolumesWithVeryLongFilename() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        let longName = String(repeating: "a", count: 1000) + ".nii.gz"
        try await manager.loadVolumesFromUrls([
            (url: "test", name: longName)
        ])

        let script = js.scripts[0]
        XCTAssertTrue(script.contains(longName))
    }

    // MARK: - State Tracking

    /// Verify volumeSources are updated after load
    func testLoadVolumesUpdatesVolumeSources() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadVolumesFromUrls([
            (url: "niivue://app/files/v1", name: "T1.nii.gz")
        ])

        XCTAssertEqual(manager.volumeSources.count, 1)
        XCTAssertEqual(manager.volumeSources[0].url, "niivue://app/files/v1")
        XCTAssertEqual(manager.volumeSources[0].name, "T1.nii.gz")
    }
}
```

### 1.2 Overlay (Colormap/Opacity) Commands

```swift
@MainActor
final class OverlayCommandTests: XCTestCase {

    func testSetColormapGeneratesCorrectJavaScript() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.setColormap(volumeIndex: 0, colormap: "hot")

        XCTAssertEqual(js.scripts.count, 1)
        XCTAssertTrue(js.scripts[0].contains("window.setColormap(0, \"hot\")"))
    }

    func testSetOpacityWithDecimalValue() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.setOpacity(volumeIndex: 1, opacity: 0.75)

        let script = js.scripts[0]
        XCTAssertTrue(script.contains("window.setOpacity(1, 0.75)"))
    }

    func testColormapListingDoesNotUseReturnPrefix() async throws {
        let js = MockJavaScriptEvaluator()
        js.nextString = "[\"gray\",\"hot\",\"red\"]"
        let manager = WebViewManager(evaluator: js)

        let colormaps = try await manager.listColormaps()

        XCTAssertEqual(colormaps, ["gray", "hot", "red"])

        // Critical: listColormaps must not have 'return' prefix
        // (should use evaluateString, not callAsyncString)
        XCTAssertFalse(
            js.scripts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                .hasPrefix("return "),
            "listColormaps must not use return prefix"
        )
    }

    func testSetOpacityBoundaryValues() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        // Test minimum opacity
        try await manager.setOpacity(volumeIndex: 0, opacity: 0.0)
        XCTAssertTrue(js.scripts[0].contains("0.0"))

        // Test maximum opacity
        try await manager.setOpacity(volumeIndex: 0, opacity: 1.0)
        XCTAssertTrue(js.scripts[1].contains("1.0"))
    }
}
```

---

## 2. Type System Testing

### 2.1 Codable Types

**Test File:** `TypeSystemTests.swift`

```swift
final class VolumeInfoCodableTests: XCTestCase {

    // MARK: - Decoding from JavaScript

    func testVolumeInfoDecodesFromMinimalJSON() throws {
        let json = """
        {
            "id": "vol-123",
            "name": "T1w.nii.gz",
            "nFrame4D": 1
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let volume = try JSONDecoder().decode(VolumeInfo.self, from: data)

        XCTAssertEqual(volume.id, "vol-123")
        XCTAssertEqual(volume.name, "T1w.nii.gz")
        XCTAssertEqual(volume.nFrame4D, 1)
    }

    func testVolumeInfoDecodesWithOptionalProperties() throws {
        let json = """
        {
            "id": "vol-456",
            "name": "T2w.nii.gz",
            "nFrame4D": 45,
            "colormap": "hot",
            "opacity": 0.8,
            "frame4D": 10,
            "visible": true
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let volume = try JSONDecoder().decode(VolumeInfo.self, from: data)

        XCTAssertEqual(volume.id, "vol-456")
        XCTAssertEqual(volume.colormap, "hot")
        XCTAssertEqual(volume.opacity, 0.8)
        XCTAssertEqual(volume.frame4D, 10)
        XCTAssertTrue(volume.visible)
    }

    // MARK: - Encoding to JavaScript

    func testVolumeInfoEncodesToValidJSON() throws {
        let volume = VolumeInfo(
            id: "vol-789",
            name: "FLAIR.nii.gz",
            nFrame4D: 30,
            colormap: "red",
            opacity: 0.5
        )

        let encoded = try JSONEncoder().encode(volume)
        let decoded = try JSONDecoder().decode(VolumeInfo.self, from: encoded)

        XCTAssertEqual(decoded.id, volume.id)
        XCTAssertEqual(decoded.name, volume.name)
        XCTAssertEqual(decoded.nFrame4D, volume.nFrame4D)
        XCTAssertEqual(decoded.colormap, volume.colormap)
        XCTAssertEqual(decoded.opacity, volume.opacity)
    }

    // MARK: - Round-Trip Testing

    func testVolumeInfoRoundTripPreservesAllFields() throws {
        let original = VolumeInfo(
            id: "test-id",
            name: "test.nii.gz",
            nFrame4D: 50,
            colormap: "hot",
            opacity: 0.7,
            frame4D: 25,
            visible: true
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VolumeInfo.self, from: encoded)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.nFrame4D, original.nFrame4D)
        XCTAssertEqual(decoded.colormap, original.colormap)
        XCTAssertEqual(decoded.opacity, original.opacity)
        XCTAssertEqual(decoded.frame4D, original.frame4D)
        XCTAssertEqual(decoded.visible, original.visible)
    }

    // MARK: - Error Handling

    func testVolumeInfoDecodingThrowsOnMissingRequiredField() throws {
        let json = """
        {
            "id": "vol-123",
            "name": "test.nii.gz"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))

        XCTAssertThrowsError(
            try JSONDecoder().decode(VolumeInfo.self, from: data)
        ) { error in
            // Verify it's a DecodingError
            guard let decodingError = error as? DecodingError else {
                XCTFail("Expected DecodingError, got \(type(of: error))")
                return
            }

            // Should be missing key error
            if case .keyNotFound = decodingError {
                // Expected
            } else {
                XCTFail("Expected keyNotFound error, got \(decodingError)")
            }
        }
    }

    func testVolumeInfoDecodingThrowsOnInvalidType() throws {
        let json = """
        {
            "id": 123,
            "name": "test.nii.gz",
            "nFrame4D": "not-a-number"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))

        XCTAssertThrowsError(
            try JSONDecoder().decode(VolumeInfo.self, from: data)
        )
    }
}

final class ColormapEnumTests: XCTestCase {

    func testColormapEnumMapsCommonValues() {
        XCTAssertEqual(Colormap(rawValue: "gray"), .gray)
        XCTAssertEqual(Colormap(rawValue: "hot"), .hot)
        XCTAssertEqual(Colormap(rawValue: "red"), .red)
        XCTAssertEqual(Colormap(rawValue: "blue"), .blue)
        XCTAssertEqual(Colormap(rawValue: "viridis"), .viridis)
    }

    func testColormapEnumRejectsUnknownValues() {
        XCTAssertNil(Colormap(rawValue: "unknown"))
        XCTAssertNil(Colormap(rawValue: ""))
        XCTAssertNil(Colormap(rawValue: "GRAY"))  // Case sensitive
    }

    func testColormapEnumRawValuesAreCorrect() {
        XCTAssertEqual(Colormap.gray.rawValue, "gray")
        XCTAssertEqual(Colormap.hot.rawValue, "hot")
    }
}
```

---

## 3. Service Layer Testing

### 3.1 File Import Service

```swift
final class FileImportServiceTests: XCTestCase {

    private func makeTempFile(data: Data = Data([0xFF]),
                             filename: String = UUID().uuidString) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent(filename)
        try data.write(to: fileURL)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: fileURL)
        }

        return fileURL
    }

    // MARK: - Basic Import

    func testImportMovesFileToDestinationDirectory() async throws {
        let sourceFile = try makeTempFile(data: Data([0xAA, 0xBB]))

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: destDir)
        }

        let service = FileImportService()
        let imported = try await service.importDocument(at: sourceFile,
                                                       destinationDirectory: destDir)

        // Verify source file is moved, not copied
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceFile.path),
                      "Source file should be moved, not copied")

        // Verify imported file exists and contains correct data
        XCTAssertTrue(FileManager.default.fileExists(atPath: imported.localURL.path))
        XCTAssertEqual(try Data(contentsOf: imported.localURL), Data([0xAA, 0xBB]))
    }

    // MARK: - ID Generation

    func testImportGeneratesUniqueID() async throws {
        let file1 = try makeTempFile(filename: "test1.nii")
        let file2 = try makeTempFile(filename: "test2.nii")

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: destDir) }

        let service = FileImportService()
        let imported1 = try await service.importDocument(at: file1, destinationDirectory: destDir)
        let imported2 = try await service.importDocument(at: file2, destinationDirectory: destDir)

        XCTAssertNotEqual(imported1.id, imported2.id, "IDs should be unique")
        XCTAssertFalse(imported1.id.isEmpty)
        XCTAssertFalse(imported2.id.isEmpty)
    }

    // MARK: - File Organization

    func testImportCreatesSubdirectoryNamedAfterID() async throws {
        let sourceFile = try makeTempFile(data: Data([0x01]))

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: destDir) }

        let service = FileImportService()
        let imported = try await service.importDocument(at: sourceFile, destinationDirectory: destDir)

        // Verify file is in subdirectory named after the ID
        XCTAssertTrue(imported.localURL.path.contains(imported.id),
                     "File should be in subdirectory named after ID")

        let expectedDir = destDir.appendingPathComponent(imported.id, isDirectory: true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedDir.path))
    }

    // MARK: - Filename Preservation

    func testImportPreservesOriginalFilename() async throws {
        let originalName = "my_brain_scan_T1w.nii.gz"
        let sourceFile = try makeTempFile(data: Data([0x02]), filename: originalName)

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: destDir) }

        let service = FileImportService()
        let imported = try await service.importDocument(at: sourceFile, destinationDirectory: destDir)

        XCTAssertEqual(imported.originalFileName, originalName)
        XCTAssertEqual(imported.localURL.lastPathComponent, originalName)
    }

    // MARK: - Error Handling

    func testImportThrowsOnNonexistentSource() async throws {
        let nonexistentFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID()).nii")

        let destDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: destDir) }

        let service = FileImportService()

        do {
            _ = try await service.importDocument(at: nonexistentFile, destinationDirectory: destDir)
            XCTFail("Should throw error for nonexistent file")
        } catch {
            // Expected
            XCTAssertNotNil(error)
        }
    }

    func testImportThrowsOnInvalidDestinationDirectory() async throws {
        let sourceFile = try makeTempFile(data: Data([0x03]))

        let invalidDestDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        // Don't create destination directory

        let service = FileImportService()

        do {
            _ = try await service.importDocument(at: sourceFile, destinationDirectory: invalidDestDir)
            XCTFail("Should throw error for invalid destination")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
```

### 3.2 Session Store

```swift
final class SessionStoreTests: XCTestCase {

    private func makeTempSessionsDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        let sessionsDir = root.appendingPathComponent("Sessions", isDirectory: true)

        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        return sessionsDir
    }

    // MARK: - Save and Load

    func testSaveAndLoadRoundTrip() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        let originalJSON = """
        {"version": 1, "volumes": [{"name": "T1.nii.gz"}]}
        """

        let id = try await store.save(json: originalJSON)
        let loaded = try await store.load(id: id)

        XCTAssertEqual(loaded, originalJSON)
    }

    func testSaveGeneratesValidUUID() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        let id = try await store.save(json: "{}")

        // ID should be a valid UUID
        XCTAssertNotNil(UUID(uuidString: id), "ID should be a valid UUID")
    }

    // MARK: - List Sessions

    func testListReturnsOnlyValidSessionIDs() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        let validID = UUID().uuidString
        let invalidID = "not-a-uuid"

        try "{\"test\": true}".write(
            to: sessionsDir.appendingPathComponent("\(validID).json"),
            atomically: true,
            encoding: .utf8
        )

        try "{\"test\": true}".write(
            to: sessionsDir.appendingPathComponent("\(invalidID).json"),
            atomically: true,
            encoding: .utf8
        )

        try "ignore".write(
            to: sessionsDir.appendingPathComponent("not-json.txt"),
            atomically: true,
            encoding: .utf8
        )

        let ids = try await store.list()

        XCTAssertEqual(ids, [validID])
    }

    // MARK: - Security: Path Traversal Prevention

    func testLoadRejectsPathTraversalID() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        // Create file outside sessions directory
        let outsideFile = sessionsDir.deletingLastPathComponent()
            .appendingPathComponent("outside.json")
        try "{\"secret\": true}".write(to: outsideFile, atomically: true, encoding: .utf8)

        // Attempt to load with path traversal
        do {
            _ = try await store.load(id: "../outside")
            XCTFail("Should reject path traversal")
        } catch SessionStoreError.invalidID {
            // Expected
        }
    }

    func testLoadRejectsDoubleDotPath() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        do {
            _ = try await store.load(id: "../../etc/passwd")
            XCTFail("Should reject path traversal")
        } catch SessionStoreError.invalidID {
            // Expected
        }
    }

    func testDeleteRejectsPathTraversalID() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        let outsideFile = sessionsDir.deletingLastPathComponent()
            .appendingPathComponent("protect.json")
        try "{\"protected\": true}".write(to: outsideFile, atomically: true, encoding: .utf8)

        // Attempt to delete with path traversal
        try await store.delete(id: "../protect")

        // Verify file still exists (wasn't deleted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideFile.path),
                     "Path traversal deletion should be prevented")
    }

    // MARK: - Delete

    func testDeleteRemovesSessionFile() async throws {
        let sessionsDir = try makeTempSessionsDirectory()
        let store = SessionStore(sessionsDirectory: sessionsDir)

        let id = try await store.save(json: "{}")

        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionsDir.appendingPathComponent("\(id).json").path
        ))

        try await store.delete(id: id)

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sessionsDir.appendingPathComponent("\(id).json").path
        ))
    }
}
```

---

## 4. Security Testing

### 4.1 JavaScript Quote Escaping

```swift
final class JavaScriptQuoteTests: XCTestCase {

    // MARK: - Basic Escaping

    func testQuoteEscapesSingleQuote() throws {
        let input = "O'Reilly"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"O'Reilly\"")
    }

    func testQuoteEscapesDoubleQuotes() throws {
        let input = "He said \"hello\""
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"He said \\\"hello\\\"\"")
    }

    func testQuoteEscapesBackslash() throws {
        let input = "path\\to\\file"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"path\\\\to\\\\file\"")
    }

    // MARK: - Whitespace Escaping

    func testQuoteEscapesNewline() throws {
        let input = "line1\nline2"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"line1\\nline2\"")
    }

    func testQuoteEscapesTab() throws {
        let input = "col1\tcol2"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"col1\\tcol2\"")
    }

    func testQuoteEscapesCarriageReturn() throws {
        let input = "line1\rline2"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertEqual(quoted, "\"line1\\rline2\"")
    }

    // MARK: - Edge Cases

    func testQuoteHandlesEmptyString() throws {
        let quoted = try JavaScriptQuote.jsonStringLiteral("")
        XCTAssertEqual(quoted, "\"\"")
    }

    func testQuoteHandlesMultipleConsecutiveQuotes() throws {
        let input = "\"\"\"multiple quotes\"\"\""
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertTrue(quoted.contains("\\\""))
        XCTAssertEqual(quoted.filter { $0 == "\\" }.count, 6)  // 6 backslashes
    }

    func testQuoteHandlesUnicodeCharacters() throws {
        let input = "Über data 你好"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)
        XCTAssertTrue(quoted.contains("Über"))
        XCTAssertTrue(quoted.contains("你好"))
    }

    // MARK: - Complex Real-World Cases

    func testQuoteHandlesFilenameWithSpecialCharacters() throws {
        let input = "patient_001_\"T1w MPRAGE\".nii.gz"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)

        // Should be valid JSON
        let data = try XCTUnwrap(quoted.data(using: .utf8))
        let decoded = try JSONDecoder().decode(String.self, from: data)
        XCTAssertEqual(decoded, input)
    }

    func testQuoteHandlesWindowsPath() throws {
        let input = "C:\\Users\\Data\\brain.nii"
        let quoted = try JavaScriptQuote.jsonStringLiteral(input)

        // Verify it's valid JSON
        let data = try XCTUnwrap(quoted.data(using: .utf8))
        let decoded = try JSONDecoder().decode(String.self, from: data)
        XCTAssertEqual(decoded, input)
    }
}
```

### 4.2 URL Router Security

```swift
final class URLRouterSecurityTests: XCTestCase {

    // MARK: - Path Traversal Prevention

    func testRouterRejectsSimplePathTraversal() {
        let router = NiivueURLRouter()

        XCTAssertNil(router.route(URL(string: "niivue://app/files/../secret.txt")!))
        XCTAssertNil(router.route(URL(string: "niivue://app/samples/../../../etc/passwd")!))
    }

    func testRouterRejectsURLEncodedPathTraversal() {
        let router = NiivueURLRouter()

        // %2e%2e = ..
        XCTAssertNil(router.route(URL(string: "niivue://app/files/%2e%2e/secret.txt")!))

        // Double encoded %252e%252e
        XCTAssertNil(router.route(URL(string: "niivue://app/files/%252e%252e/secret.txt")!))
    }

    func testRouterRejectsDotPath() {
        let router = NiivueURLRouter()

        XCTAssertNil(router.route(URL(string: "niivue://app/./hidden")!))
        XCTAssertNil(router.route(URL(string: "niivue://app/files/./secret.txt")!))
    }

    // MARK: - Scheme Validation

    func testRouterRejectsWrongScheme() {
        let router = NiivueURLRouter()

        XCTAssertNil(router.route(URL(string: "http://app/files/test.txt")!))
        XCTAssertNil(router.route(URL(string: "https://app/files/test.txt")!))
        XCTAssertNil(router.route(URL(string: "file://app/files/test.txt")!))
    }

    // MARK: - Host Validation

    func testRouterRejectsWrongHost() {
        let router = NiivueURLRouter()

        XCTAssertNil(router.route(URL(string: "niivue://files/test.txt")!))
        XCTAssertNil(router.route(URL(string: "niivue://localhost/test.txt")!))
        XCTAssertNil(router.route(URL(string: "niivue://evil.com/test.txt")!))
    }

    // MARK: - Valid Routes

    func testRouterAcceptsValidDistPath() {
        let router = NiivueURLRouter()

        let route = router.route(URL(string: "niivue://app/index.html")!)
        if case .dist(let path) = route {
            XCTAssertEqual(path, "index.html")
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

    func testRouterRoutesValidImportedFileID() {
        let router = NiivueURLRouter()

        let route = router.route(URL(string: "niivue://app/files/550e8400-e29b-41d4-a716-446655440000")!)
        if case .importedFile(let id) = route {
            XCTAssertEqual(id, "550e8400-e29b-41d4-a716-446655440000")
        } else {
            XCTFail("Expected .importedFile route")
        }
    }

    func testRouterRejectsEmptyFileID() {
        let router = NiivueURLRouter()

        XCTAssertNil(router.route(URL(string: "niivue://app/files/")!))
    }
}
```

---

## 5. UI Testing Workflows

### 5.1 Multi-Step Volume Loading

```swift
final class VolumeLoadingWorkflowUITests: XCTestCase {

    func testLoadMultipleVolumesAndAdjustOpacity() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        // STEP 1: Wait for WebView to load
        let readyLabel = app.staticTexts["niivue.isReady"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15),
                     "WebView should load within 15 seconds")

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready",
                      "WebView should indicate it's ready")

        // STEP 2: Verify volume count
        let countLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(countLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(countLabel.label, "2",
                      "Should have loaded 2 volumes")

        // STEP 3: Open volumes sheet
        app.buttons["niivue.volumes"].tap()
        let volumesSheet = app.otherElements["niivue.volumesSheet"]
        XCTAssertTrue(volumesSheet.waitForExistence(timeout: 2),
                     "Volumes sheet should open")

        // STEP 4: Find and interact with opacity slider
        let opacitySlider = app.sliders["niivue.volume.opacity.0"]
        XCTAssertTrue(opacitySlider.waitForExistence(timeout: 5),
                     "Opacity slider should be visible for first volume")

        // Adjust slider from 30% to 80%
        let startPoint = opacitySlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)
        )
        let endPoint = opacitySlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        )
        startPoint.press(forDuration: 0, thenDragTo: endPoint)

        // STEP 5: Verify colormap button exists
        let colormapButton = app.buttons["niivue.volume.colormap.0"]
        XCTAssertTrue(colormapButton.exists,
                     "Colormap button should be available for first volume")

        // STEP 6: Close sheet
        app.buttons["Done"].tap()
        XCTAssertFalse(volumesSheet.exists(timeout: 1),
                      "Sheet should close")
    }
}

final class VolumeUITests: XCTestCase {

    func testVolumesSheetShowsControlsForSecondVolume() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        // Wait for setup
        let readyLabel = app.staticTexts["niivue.isReady"]
        _ = readyLabel.waitForExistence(timeout: 15)

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }

        // Open sheet and verify second volume controls
        app.buttons["niivue.volumes"].tap()
        app.otherElements["niivue.volumesSheet"].waitForExistence(timeout: 2)

        // Check second volume controls
        let secondOpacity = app.sliders["niivue.volume.opacity.1"]
        XCTAssertTrue(secondOpacity.waitForExistence(timeout: 5),
                     "Second volume should have opacity slider")

        let secondColormap = app.buttons["niivue.volume.colormap.1"]
        XCTAssertTrue(secondColormap.exists,
                     "Second volume should have colormap button")

        app.buttons["Done"].tap()
    }
}
```

### 5.2 Session Management

```swift
final class SessionManagementUITests: XCTestCase {

    func testSaveSessionIncrementsSessionCount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple", "--ui-test-sessions-temp"]
        app.launch()

        // Wait for WebView ready
        let readyLabel = app.staticTexts["niivue.isReady"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }

        // Open sessions sheet
        app.buttons["niivue.sessions"].tap()
        let sessionsSheet = app.otherElements["niivue.sessionsSheet"]
        XCTAssertTrue(sessionsSheet.waitForExistence(timeout: 2))

        // Check initial count
        let countLabel = app.staticTexts["niivue.sessionCount"]
        XCTAssertTrue(countLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(countLabel.label, "0",
                      "Should have 0 saved sessions initially")

        // Save session
        app.buttons["niivue.saveSession"].tap()

        // Wait for count to update
        let updateDeadline = Date().addingTimeInterval(10)
        while Date() < updateDeadline {
            if countLabel.label == "1" { break }
            sleep(0.5)
        }
        XCTAssertEqual(countLabel.label, "1",
                      "Should have 1 session after save")

        app.buttons["Done"].tap()
    }
}
```

---

## Summary

This document provides concrete, executable test examples that follow the patterns established in the existing NiiVue test suite:

1. **Consistency** - Uses same mocking patterns (MockJavaScriptEvaluator)
2. **Coverage** - Tests happy path, edge cases, and error conditions
3. **Clarity** - Clear test names and descriptive assertions
4. **Isolation** - Each test is independent with proper cleanup
5. **Security** - Validates path traversal and injection prevention
6. **Automation** - All tests can run in CI/CD pipelines

All tests follow Swift 6 async/await patterns and maintain the @MainActor isolation requirements for UI-related code.
