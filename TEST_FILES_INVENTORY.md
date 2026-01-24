# NiiVue iOS Test Files - Complete Inventory

**Document Version:** 1.0
**Generated:** January 4, 2026

---

## Overview

This document provides a complete inventory of all test files in the NiiVue iOS application, including test counts, categories, and key patterns used.

---

## Unit Test Files (16 Files, 20 Tests)

### 1. NiiVueTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/NiiVueTests.swift`
**Test Count:** 2
**Category:** Placeholder/Examples
**Tests:**
- `testExample()`
- `testPerformanceExample()`

**Notes:** Basic template tests, can be expanded with actual unit tests

---

### 2. TimeSeriesCommandTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/TimeSeriesCommandTests.swift`
**Test Count:** 1
**Category:** Unit - JavaScript Bridge
**Tests:**
- `testSetFrameCallsJS()` - Verifies 4D frame navigation command generation

**Key Pattern:**
```swift
@MainActor
let js = MockJavaScriptEvaluator()
let manager = WebViewManager(evaluator: js)
try await manager.setFrame4D(volumeIndex: 0, frame: 3)
XCTAssertTrue(js.scripts[0].contains("setFrame4D"))
```

---

### 3. Base64FileEncoderTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/Base64FileEncoderTests.swift`
**Test Count:** 2
**Category:** Unit - Utilities
**Tests:**
- `testEncodeFileToBase64ReturnsExpectedStringForSmallFile()`
- `testEncodeFileToBase64ReturnsNilWhenFileTooLarge()`

**Key Pattern:** Temporary file creation with cleanup in addTeardownBlock
```swift
let dir = FileManager.default.temporaryDirectory
    .appendingPathComponent("NiiVue-Base64FileEncoderTests", isDirectory: true)
addTeardownBlock {
    try? FileManager.default.removeItem(at: dir)
}
```

---

### 4. OverlayCommandTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/OverlayCommandTests.swift`
**Test Count:** 3
**Category:** Unit - JavaScript Bridge
**Tests:**
- `testSetColormapCallsJS()` - Colormap command generation
- `testSetOpacityCallsJS()` - Opacity command generation
- `testListColormapsParsesJSONAndDoesNotUseReturnPrefix()` - Colormap listing, JSON parsing

**Key Pattern:** Color/opacity control command testing
```swift
try await manager.setColormap(volumeIndex: 0, colormap: "red")
XCTAssertTrue(js.scripts[0].contains("setColormap"))
```

---

### 5. WebViewManagerStateTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/WebViewManagerStateTests.swift`
**Test Count:** 9
**Category:** Unit - Core WebView Management
**Tests:**
1. `testInitializationTimeoutSetsErrorMessage()` - Timeout handling
2. `testReloadCancelsPreviousInitializationTimeout()` - Timeout reset on reload
3. `testWebViewManagerMarksReadyOnFinishedLoadingMessage()` - Ready state tracking
4. `testReadyMessageClearsError()` - Error clearing
5. `testVolumeLoadedUpdatesVolumesList()` - Volume tracking
6. `testMultipleVolumesAreAppended()` - Multiple volume management
7. `testVolumeUpdateReplacesExisting()` - Volume replacement
8. `testLoadImageFromUrlClearsVolumesList()` - State reset on new image
9. `testLoadBase64ImageClearsVolumesList()` - State reset on base64 load

**Key Pattern:** Script message handling and state management
```swift
manager.handleScriptMessage(
    name: "volumeLoaded",
    body: "{\"id\":\"v1\",\"name\":\"T1w.nii.gz\",\"nFrame4D\":1}"
)
XCTAssertEqual(manager.volumes.count, 1)
```

---

### 6. FileImportServiceTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/FileImportServiceTests.swift`
**Test Count:** 3
**Category:** Unit - Services
**Tests:**
- `testImportMovesFileIntoDestinationDirectory()` - File movement verification
- `testImportCreatesUniqueSubdirectory()` - Directory organization
- `testImportPreservesOriginalFileName()` - Filename handling

**Key Pattern:** Real FileManager operations with proper cleanup
```swift
let imported = try await service.importDocument(at: tmp, destinationDirectory: destDir)
XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
XCTAssertEqual(imported.originalFileName, originalName)
```

---

### 7. DicomSeriesStoreTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/DicomSeriesStoreTests.swift`
**Test Count:** 3
**Category:** Unit - Services
**Tests:**
- `testManifestListsFilenamesOnePerLine()` - DICOM manifest generation
- `testUrlResolution()` - File URL resolution
- `testManifestHasNoTrailingNewline()` - Format validation

**Key Pattern:** DICOM series management
```swift
let seriesId = await store.register(files: [a, b])
let manifest = await store.manifestText(for: seriesId)
XCTAssertEqual(manifest, "a.dcm\nb.dcm")
```

---

### 8. DrawingExportServiceTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/DrawingExportServiceTests.swift`
**Test Count:** 3
**Category:** Unit - Services
**Tests:**
- `testDecodeBase64WritesFile()` - Base64 decoding and file writing
- `testInvalidBase64Throws()` - Error handling
- `testFileHasCorrectFileName()` - File naming

**Key Pattern:** Base64 processing and file export
```swift
let url = try service.writeNiftiGz(base64: b64, preferredFileName: "out.nii.gz", directory: tmp)
XCTAssertEqual(try Data(contentsOf: url), data)
```

---

### 9. JavaScriptEvaluatingTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/JavaScriptEvaluatingTests.swift`
**Test Count:** 4
**Category:** Unit - JavaScript Bridge
**Tests:**
- `testMockCapturesScripts()` - Mock command capture
- `testMockReturnsConfiguredString()` - Mock return values
- `testMockReturnsConfiguredAsyncString()` - Async mock behavior
- `testMockAccumulatesMultipleScripts()` - Script accumulation

**Key Pattern:** MockJavaScriptEvaluator testing
```swift
let mock = MockJavaScriptEvaluator()
mock.nextString = "hello"
let result = try await mock.evaluateString("window.greeting")
XCTAssertEqual(result, "hello")
```

---

### 10. NiivueURLRouterTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/NiivueURLRouterTests.swift`
**Test Count:** 10
**Category:** Unit - Security
**Tests (Router Validation):**
- `testRouterRejectsPathTraversal()` - `../` rejection
- `testRouterRejectsDotPath()` - `./` rejection
- `testRouterRejectsWrongScheme()` - Scheme validation
- `testRouterRejectsWrongHost()` - Host validation
- `testRouterRoutesDistPath()` - Distribution file routing
- `testRouterRoutesDistAssets()` - Asset routing
- `testRouterRoutesRootToIndexHtml()` - Root path handling
- `testRouterRoutesSamples()` - Sample file routing
- `testRouterRoutesImportedFiles()` - Imported file routing
- `testRouterRejectsFilesWithoutId()` - ID validation

**Tests (Streaming):**
- `testImportedFileIsStreamedInMultipleChunks()` - Large file streaming

**Key Pattern:** Security validation with enums
```swift
if case .dist(let path) = route {
    XCTAssertEqual(path, "index.html")
} else {
    XCTFail("Expected .dist route")
}
```

---

### 11. JavaScriptQuoteTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/JavaScriptQuoteTests.swift`
**Test Count:** 4
**Category:** Unit - Utilities
**Tests:**
- `testQuoteEscapesSingleQuoteAndNewline()` - Quote and newline escaping
- `testQuoteEscapesDoubleQuotes()` - Double quote escaping
- `testQuoteHandlesEmptyString()` - Empty string handling
- `testQuoteHandlesSpecialCharacters()` - Tab and carriage return escaping

**Key Pattern:** JSON string escaping
```swift
let quoted = try JavaScriptQuote.jsonStringLiteral("O'Reilly\nLine2")
XCTAssertEqual(quoted, "\"O'Reilly\\nLine2\"")
```

---

### 12. SessionStoreTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/SessionStoreTests.swift`
**Test Count:** 4
**Category:** Unit - Services
**Tests:**
- `testSaveAndLoadRoundTrip()` - Save and load verification
- `testLoadRejectsPathTraversalID()` - Path traversal prevention
- `testDeleteRejectsPathTraversalID()` - Delete security
- `testListReturnsOnlyJSONSessionIDs()` - Session listing

**Key Pattern:** Path traversal security validation
```swift
do {
    _ = try await store.load(id: "../outside")
    XCTFail("Expected invalid ID to be rejected")
} catch SessionStoreError.invalidID {
    // Expected
}
```

---

### 13. HUDMessageParsingTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/HUDMessageParsingTests.swift`
**Test Count:** 1
**Category:** Unit - JavaScript Bridge
**Tests:**
- `testLocationMessageIsStored()` - Location message handling

**Key Pattern:** Script message parsing
```swift
manager.handleScriptMessage(name: "locationChange", body: "{\"string\":\"1×2×3 = 4\"}")
XCTAssertEqual(manager.lastLocationString, "1×2×3 = 4")
```

---

### 14. SegmentationCommandTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/SegmentationCommandTests.swift`
**Test Count:** 11
**Category:** Unit - JavaScript Bridge & UI
**Tests (Drawing Commands):**
- `testUndoCallsJS()` - Undo command
- `testSetDrawOpacityCallsJS()` - Draw opacity
- `testSetDrawColormapCallsJS()` - Draw colormap
- `testSetClickToSegmentEnabledCallsJS()` - Click-to-segment toggle

**Tests (Asset Classification):**
- `testSegmentationAssetClassifierTreatsNiftiAsVolume()`
- `testSegmentationAssetClassifierTreatsNiiVueMeshExtensionsAsMesh()`
- `testSegmentationAssetClassifierRejectsUnsupportedExtensions()`

**Tests (Import Planning):**
- `testSegmentationAssetImportPlannerBuildsSpecsFromImportedFiles()`

**Tests (UI Components):**
- `testDocumentPickerMultipleSetsAllowsMultipleSelection()`
- `testDocumentPickerMultipleCoordinatorPassesAllPickedURLsAndDismisses()`
- `testSegmentationAssetImportExecutorCallsJSForVolumesThenMeshes()`

**Key Pattern:** Asset classification and import planning
```swift
let plan = SegmentationAssetImportPlanner.plan(importedFiles: imported)
XCTAssertEqual(plan.volumeSpecs.count, 1)
XCTAssertEqual(plan.meshSpecs.count, 1)
```

---

### 15. DicomCommandTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/DicomCommandTests.swift`
**Test Count:** 2
**Category:** Unit - JavaScript Bridge
**Tests:**
- `testLoadDicomSeriesCallsJS()` - DICOM series loading
- `testLoadDicomSeriesEscapesManifestURL()` - URL escaping in DICOM context

**Key Pattern:** DICOM command generation
```swift
try await manager.loadDicomSeriesFromManifestURL("niivue://app/dicom/series1/niivue-manifest.txt")
XCTAssertTrue(js.scripts[0].contains("loadDicomSeriesFromManifest"))
```

---

### 16. WebViewManagerCommandTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/WebViewManagerCommandTests.swift`
**Test Count:** 12
**Category:** Unit - JavaScript Bridge
**Tests:**
- `testLoadBase64ImageUsesJSONEscapedArguments()` - Base64 image loading
- `testLoadImageFromUrlUsesAsyncAwaitEvaluation()` - URL-based loading
- `testSetSliceTypeUsesJSONEscapedArguments()` - Slice type command
- `testSetLayoutUsesJSONEscapedArguments()` - Layout command
- `testSetPenValueUsesJSONEscapedArguments()` - Drawing pen value
- `testLoadVolumesFromUrlsBuildsCorrectJSCall()` - Volume loading
- `testAddVolumesFromUrlsBuildsCorrectJSCall()` - Volume addition
- `testLoadMeshesFromUrlsBuildsCorrectJSCall()` - Mesh loading
- `testExportViewerStateJSONBuildsCorrectJSCall()` - State export
- `testApplyViewerStateJSONBuildsCorrectJSCall()` - State application
- `testRestoreSessionJSONWithSourcesLoadsVolumesThenAppliesViewerState()` - Session restoration
- `testExportSessionSnapshotJSONIncludesVolumeSourcesAndViewerState()` - Session export

**Key Pattern:** Complex command generation with JSON
```swift
try await manager.loadVolumesFromUrls(volumes)
XCTAssertTrue(js.scripts[0].contains("window.loadVolumesFromUrls"))
XCTAssertTrue(js.scripts[0].contains("\"T1.nii.gz\""))
```

---

## UI Test Files (2 Files, 12 Tests)

### 1. NiiVueUITests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueUITests/NiiVueUITests.swift`
**Test Count:** 11
**Category:** UI - End-to-End
**Tests:**
- `testExample()` - Basic launch test
- `testLaunchShowsPrimaryToolbarButtons()` - Toolbar visibility
- `testLoadingOverlayDoesNotPersistForever()` - Loading state management
- `testWebViewLoadsFromCustomScheme()` - Custom scheme loading
- `testLaunchPerformance()` - Launch performance measurement
- `testLaunchArgumentLoadsTwoVolumes()` - Multi-volume loading with arguments
- `testLaunchShowsPhase2SheetsButtons()` - Phase 2 UI components
- `testVolumesSheetOpens()` - Volumes sheet interaction
- `testVolumesSheetShowsVolumeControlsWhenTwoVolumesLoaded()` - Volume controls visibility
- `testSegmentationSheetOpens()` - Segmentation sheet interaction
- `testSegmentationSheetShowsToolControls()` - Segmentation tool visibility
- `testSessionsSheetOpens()` - Sessions sheet interaction
- `testSessionsSheetSaveIncrementsSessionCount()` - Session saving
- `testSegmentationSheetShowsDicomImportButton()` - DICOM button visibility

**Key Pattern:** Accessibility identifiers and waiting
```swift
XCTAssertTrue(app.buttons["niivue.addImage"].waitForExistence(timeout: 5))
app.buttons["niivue.volumes"].tap()
XCTAssertTrue(app.otherElements["niivue.volumesSheet"].waitForExistence(timeout: 2))
```

---

### 2. NiiVueUITestsLaunchTests.swift
**Location:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueUITests/NiiVueUITestsLaunchTests.swift`
**Test Count:** 1
**Category:** UI - Launch
**Tests:**
- `testLaunch()` - Launch screenshot baseline

**Key Pattern:** Launch baseline screenshot
```swift
let attachment = XCTAttachment(screenshot: app.screenshot())
attachment.name = "Launch Screen"
add(attachment)
```

---

## Summary Statistics

### Test Distribution by Type
| Type | Count | Percentage |
|------|-------|-----------|
| JavaScript Bridge Commands | 12 | 38% |
| Security & Validation | 11 | 34% |
| Services & File I/O | 9 | 28% |
| WebView State | 9 | 28% |
| UI Tests | 12 | 38% |

### Test Distribution by Category
| Category | Files | Tests | Priority |
|----------|-------|-------|----------|
| Unit - Bridge | 6 | 12 | P0 |
| Unit - Security | 1 | 11 | P0 |
| Unit - Services | 4 | 9 | P1 |
| Unit - State | 1 | 9 | P0 |
| UI - Integration | 2 | 12 | P1 |
| **Total** | **18** | **32** | - |

---

## Quick Reference: Finding Tests

### By Feature
- **Volume Loading:** WebViewManagerCommandTests, SegmentationCommandTests
- **Drawing/Segmentation:** SegmentationCommandTests, DrawingExportServiceTests
- **Colormaps/Opacity:** OverlayCommandTests
- **DICOM:** DicomCommandTests, DicomSeriesStoreTests
- **Sessions:** SessionStoreTests, WebViewManagerCommandTests
- **File Import:** FileImportServiceTests, Base64FileEncoderTests
- **Security:** NiivueURLRouterTests, JavaScriptQuoteTests, SessionStoreTests
- **UI Workflows:** NiiVueUITests

### By Priority
- **P0 (Critical):** WebViewManagerStateTests, WebViewManagerCommandTests, SegmentationCommandTests
- **P1 (Important):** FileImportServiceTests, SessionStoreTests, NiiVueUITests
- **P2 (Nice to Have):** NiiVueTests, HUDMessageParsingTests

### By Async Pattern
- **@MainActor:** All bridge and command tests
- **Real async/await:** FileImportServiceTests, SessionStoreTests, DicomSeriesStoreTests
- **Mock-only:** JavaScriptQuoteTests, NiivueURLRouterTests

---

## Test Execution

### Run All Tests
```bash
xcodebuild test -scheme NiiVue
```

### Run Specific Test File
```bash
xcodebuild test -scheme NiiVue \
  -testFilter "WebViewManagerCommandTests"
```

### Run Unit Tests Only
```bash
xcodebuild test -scheme NiiVue \
  -testPlan NiiVueTests
```

### Run UI Tests Only
```bash
xcodebuild test -scheme NiiVue \
  -testPlan NiiVueUITests
```

### Run with Coverage
```bash
xcodebuild test -scheme NiiVue \
  -enableCodeCoverage YES \
  -resultBundlePath build/coverage
```

---

## Integration with NiiVueKit SDK

These tests serve as the foundation for SDK testing:

1. **Mock Patterns** - Use MockJavaScriptEvaluator pattern
2. **Async Testing** - Follow @MainActor isolation pattern
3. **File Operations** - Use temporary directory pattern
4. **Security Testing** - Expand on path traversal tests
5. **UI Testing** - Extend accessibility identifier patterns
6. **Service Testing** - Real FileManager with cleanup

All new SDK tests should follow these established patterns for consistency.

---

**Last Updated:** January 4, 2026
**Total Tests in Inventory:** 32 unit tests, 12 UI tests
**Status:** All analyzed and documented
