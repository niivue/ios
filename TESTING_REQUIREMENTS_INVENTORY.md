# NiiVueKit SDK Testing Requirements Inventory

**Document Version:** 1.0
**Date:** January 4, 2026
**Status:** Analysis Complete

---

## Executive Summary

The NiiVue iOS application currently has **20 unit tests** across **16 test files** and **11 UI tests** across **2 UI test files**. The existing test suite demonstrates a mature testing strategy focused on:

- **JavaScript bridge abstraction** with comprehensive mocking
- **Data persistence and file I/O** operations
- **WebView state management** and initialization
- **Security** (path traversal prevention, input validation)
- **UI/UX integration** with accessibility identifiers

This document provides a testing strategy and inventory for the NiiVueKit SDK, building on established patterns.

---

## Part 1: Existing Test Analysis

### 1.1 Test Files and Count Summary

| Test File | Category | Test Count | Focus |
|-----------|----------|-----------|-------|
| **NiiVueTests.swift** | Unit | 2 | Placeholder/Example tests |
| **TimeSeriesCommandTests.swift** | Unit - Bridge | 1 | 4D frame navigation |
| **Base64FileEncoderTests.swift** | Unit - Utils | 2 | File encoding, size validation |
| **OverlayCommandTests.swift** | Unit - Bridge | 3 | Colormap/opacity, colormap listing |
| **WebViewManagerStateTests.swift** | Unit - Core | 9 | Initialization, loading, error states, volume tracking |
| **FileImportServiceTests.swift** | Unit - Service | 3 | File import, directory creation, naming |
| **DicomSeriesStoreTests.swift** | Unit - Service | 3 | DICOM manifest generation, URL resolution |
| **DrawingExportServiceTests.swift** | Unit - Service | 3 | Base64 decoding, file writing, validation |
| **JavaScriptEvaluatingTests.swift** | Unit - Bridge | 4 | Mock JavaScript evaluator behavior |
| **NiivueURLRouterTests.swift** | Unit - Security | 10 | Route validation, path traversal, streaming |
| **JavaScriptQuoteTests.swift** | Unit - Utils | 4 | JSON string escaping, special characters |
| **SessionStoreTests.swift** | Unit - Service | 4 | Session save/load, ID validation, path traversal |
| **HUDMessageParsingTests.swift** | Unit - Bridge | 1 | Location message parsing |
| **SegmentationCommandTests.swift** | Unit - Bridge | 11 | Drawing commands, asset classification, import planning |
| **DicomCommandTests.swift** | Unit - Bridge | 2 | DICOM series loading, URL escaping |
| **WebViewManagerCommandTests.swift** | Unit - Bridge | 12 | Volume loading, mesh loading, session management, JSON serialization |
| **NiiVueUITests.swift** | UI | 11 | Toolbar, sheets, state visibility, multi-volume, sessions |
| **NiiVueUITestsLaunchTests.swift** | UI - Launch | 1 | Launch screenshot/performance baseline |

**Total: 20 Unit Tests | 12 UI Tests | 32 Total Tests**

### 1.2 Test Categories Breakdown

#### Unit Tests by Domain

```
JavaScript Bridge Commands:     37 tests (52%)
  - OverlayCommandTests
  - TimeSeriesCommandTests
  - SegmentationCommandTests
  - DicomCommandTests
  - WebViewManagerCommandTests
  - HUDMessageParsingTests

Core Services:                  13 tests (18%)
  - FileImportServiceTests
  - DicomSeriesStoreTests
  - SessionStoreTests
  - DrawingExportServiceTests
  - Base64FileEncoderTests

WebView Infrastructure:         9 tests (13%)
  - WebViewManagerStateTests

Security & Input Validation:    14 tests (20%)
  - NiivueURLRouterTests (10)
  - JavaScriptQuoteTests (4)

UI Tests:                       12 tests (27%)
  - NiiVueUITests (11)
  - NiiVueUITestsLaunchTests (1)
```

### 1.3 Testing Patterns and Techniques

#### Mocking Strategy

1. **MockJavaScriptEvaluator** - Records script execution for validation
   ```swift
   let js = MockJavaScriptEvaluator()
   let manager = WebViewManager(evaluator: js)
   try await manager.setColormap(volumeIndex: 0, colormap: "red")
   XCTAssertTrue(js.scripts[0].contains("setColormap"))
   ```

2. **MockURLSchemeTask** - Simulates WKURLSchemeTask for streaming tests
   ```swift
   let schemeTask = MockURLSchemeTask(url: url, finished: expectation)
   handler.webView(WKWebView(frame: .zero), start: schemeTask)
   ```

#### Async Testing Patterns

- **@MainActor** isolation for UI-thread-dependent code
- **async/await** syntax for async operations
- **Task.sleep()** for timing-sensitive tests
- **XCTestExpectation** for WebKit delegate callbacks

Example:
```swift
@MainActor
final class TimeSeriesCommandTests: XCTestCase {
    func testSetFrameCallsJS() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)
        try await manager.setFrame4D(volumeIndex: 0, frame: 3)
        XCTAssertTrue(js.scripts[0].contains("setFrame4D"))
    }
}
```

#### File System Testing

- **Temporary directories** with UUID for isolation
- **TeardownBlock** cleanup pattern
- **Path validation** to prevent traversal attacks

Example:
```swift
func testImportMovesFileIntoDestinationDirectory() async throws {
    let tmp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try Data([0xAA, 0xBB]).write(to: tmp)

    let service = FileImportService()
    let destDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    let imported = try await service.importDocument(at: tmp, destinationDirectory: destDir)

    XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path))
    XCTAssertEqual(imported.originalFileName, tmp.lastPathComponent)
}
```

#### UI Testing with Accessibility

- **Accessibility Identifiers** for reliable element location
- **waitForExistence(timeout:)** for async UI updates
- **XCTAssertTrue/False** for visibility checks
- **Launch arguments** for test-specific app configuration

Example:
```swift
func testLaunchShowsPrimaryToolbarButtons() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.buttons["niivue.addImage"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["niivue.settings"].exists)
}
```

#### Security Testing

- **Path traversal validation**: `../`, `%2e%2e`, `/./` rejection
- **Scheme validation**: Only `niivue://` accepted
- **Host validation**: Only `niivue://app` accepted
- **ID validation**: UUID format enforcement, invalid IDs rejected

Example:
```swift
func testRouterRejectsPathTraversal() {
    let router = NiivueURLRouter()
    XCTAssertNil(router.route(URL(string: "niivue://app/samples/../secrets.txt")!))
    XCTAssertNil(router.route(URL(string: "niivue://app/samples/%2e%2e/secrets.txt")!))
}
```

---

## Part 2: Test Categories Needed for NiiVueKit SDK

### 2.1 Testing Matrix by Component

| Category | Priority | Est. Tests | Framework | Key Focus |
|----------|----------|-----------|-----------|-----------|
| **Unit - Swift Bridge** | P0 | 35 | XCTest | JavaScript command generation, type safety |
| **Unit - Type System** | P0 | 20 | XCTest | Codable, enums, value semantics |
| **Unit - View Models** | P1 | 25 | XCTest | State management, observation, reactivity |
| **Unit - Services** | P1 | 15 | XCTest | File I/O, caching, async operations |
| **Integration - WebView** | P1 | 15 | XCTest + Playwright | Real WKWebView interaction |
| **Integration - File System** | P1 | 10 | XCTest | Directory creation, permissions |
| **Integration - JSON Serialization** | P2 | 8 | XCTest | Round-trip encoding/decoding |
| **UI - Components** | P2 | 20 | XCUITest | SwiftUI components, states, accessibility |
| **UI - User Workflows** | P1 | 15 | XCUITest | Multi-step interactions, state persistence |
| **Performance** | P2 | 5 | XCTest | Initialization, rendering, memory |
| **Snapshot/Visual** | P3 | 10 | Custom | UI regression testing (optional) |

**Total Estimated: ~178 tests for comprehensive SDK coverage**

### 2.2 Detailed Test Categories

#### 2.2.1 Unit Tests - JavaScript Bridge (P0 Priority)

**Purpose:** Ensure correct JavaScript code generation and type-safe command sending

**Test Categories:**

| Test Group | Test Count | Examples |
|-----------|-----------|----------|
| Volume Operations | 8 | Load single/multiple volumes, replace, clear |
| Mesh Operations | 6 | Load meshes, update properties, visibility |
| Drawing/Segmentation | 8 | Undo, opacity, colormap, click-to-segment, brush size |
| Visualization | 7 | Colormap, opacity, frame navigation, slice type, layout |
| Camera/View | 4 | Camera positioning, zoom, rotation, reset |
| Data Export | 2 | Export viewer state, export drawing |

**Example Test Case:**

```swift
@MainActor
final class VolumeCommandGenerationTests: XCTestCase {
    func testLoadVolumesGeneratesCorrectJavaScript() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        let volumes = [
            (url: "niivue://app/files/vol1", name: "T1.nii.gz"),
            (url: "niivue://app/files/vol2", name: "T2.nii.gz")
        ]
        try await manager.loadVolumesFromUrls(volumes)

        let script = js.scripts[0]
        XCTAssertTrue(script.contains("window.loadVolumesFromUrls"))
        XCTAssertTrue(script.contains("\"T1.nii.gz\""))
        XCTAssertTrue(script.contains("\"T2.nii.gz\""))
        XCTAssertTrue(script.contains("return await"))
    }

    func testLoadVolumesEscapesSpecialCharactersInNames() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        let volumes = [(url: "test", name: "file\"with'quotes.nii.gz")]
        try await manager.loadVolumesFromUrls(volumes)

        let script = js.scripts[0]
        // Should be JSON-escaped
        XCTAssertTrue(script.contains("\\\"with'quotes"))
    }
}
```

#### 2.2.2 Unit Tests - Type System (P0 Priority)

**Purpose:** Validate Swift types match JavaScript expectations

**Test Categories:**

| Test Group | Test Count | Focus |
|-----------|-----------|-------|
| Codable Types | 6 | Encoding, decoding, round-trip |
| Enums | 5 | Case mapping, raw values |
| Value Types | 5 | Equality, hashability, mutability |
| Error Types | 4 | Error conformance, descriptive messages |

**Example Test Case:**

```swift
final class VolumeInfoCodableTests: XCTestCase {
    func testVolumeInfoDecodeFromJavaScript() throws {
        let json = """
        {
            "id": "v1",
            "name": "T1w.nii.gz",
            "nFrame4D": 50,
            "colormap": "gray",
            "opacity": 0.8
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let volume = try JSONDecoder().decode(VolumeInfo.self, from: data)

        XCTAssertEqual(volume.id, "v1")
        XCTAssertEqual(volume.name, "T1w.nii.gz")
        XCTAssertEqual(volume.nFrame4D, 50)
        XCTAssertEqual(volume.opacity, 0.8)
    }

    func testColormapEnumMapsJavaScriptValues() throws {
        XCTAssertEqual(Colormap(rawValue: "gray"), .gray)
        XCTAssertEqual(Colormap(rawValue: "hot"), .hot)
        XCTAssertEqual(Colormap(rawValue: "unknown"), nil)
    }
}
```

#### 2.2.3 Unit Tests - View Models (P1 Priority)

**Purpose:** Test state management, observation, and reactivity

**Example Test Case:**

```swift
@MainActor
final class NiiVueViewModelTests: XCTestCase {
    func testLoadingStateUpdatesOnWebViewInitialization() async throws {
        let js = MockJavaScriptEvaluator()
        let viewModel = NiiVueViewModel(webViewManager: WebViewManager(evaluator: js))

        XCTAssertTrue(viewModel.isLoading)

        // Simulate webView becoming ready
        viewModel.webViewManager.handleScriptMessage(name: "finishedLoading", body: "ready")

        XCTAssertFalse(viewModel.isLoading)
    }

    func testVolumeAdditionUpdatesModel() async throws {
        let js = MockJavaScriptEvaluator()
        let viewModel = NiiVueViewModel(webViewManager: WebViewManager(evaluator: js))

        XCTAssertEqual(viewModel.volumes.count, 0)

        viewModel.webViewManager.handleScriptMessage(
            name: "volumeLoaded",
            body: "{\"id\":\"v1\",\"name\":\"T1.nii.gz\",\"nFrame4D\":1}"
        )

        XCTAssertEqual(viewModel.volumes.count, 1)
        XCTAssertEqual(viewModel.volumes[0].name, "T1.nii.gz")
    }
}
```

#### 2.2.4 Unit Tests - Services (P1 Priority)

**Purpose:** Validate file operations, caching, async behavior

**Example Test Case:**

```swift
final class NiiVueImageCacheTests: XCTestCase {
    func testCacheStoresLoadedImage() async throws {
        let cache = NiiVueImageCache(maxSize: 100 * 1024 * 1024)
        let imageData = Data([0x01, 0x02, 0x03])

        cache.store(imageData, for: "test.nii.gz")
        let retrieved = cache.retrieve(for: "test.nii.gz")

        XCTAssertEqual(retrieved, imageData)
    }

    func testCacheEvictsOldestWhenFull() async throws {
        let cache = NiiVueImageCache(maxSize: 10)

        cache.store(Data(repeating: 0x01, count: 6), for: "first")
        cache.store(Data(repeating: 0x02, count: 6), for: "second")

        XCTAssertNil(cache.retrieve(for: "first"))
        XCTAssertNotNil(cache.retrieve(for: "second"))
    }
}
```

#### 2.2.5 Integration Tests - WebView (P1 Priority)

**Purpose:** Test real WKWebView interaction (requires simulator/device)

**Example Test Case:**

```swift
@MainActor
final class WebViewIntegrationTests: XCTestCase {
    var webView: WKWebView?
    var manager: WebViewManager?

    override func setUp() async throws {
        try await super.setUp()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let evaluator = WKWebView_JavaScriptEvaluating(webView: webView!)
        manager = WebViewManager(evaluator: evaluator)
    }

    func testWebViewExecutesJavaScriptCommand() async throws {
        let manager = try XCTUnwrap(manager)
        let webView = try XCTUnwrap(webView)

        // Load HTML with test page
        let html = """
        <html>
        <body>
        <script>
            window.testValue = null;
            window.setTestValue = (v) => { window.testValue = v; };
            window.getTestValue = () => window.testValue;
        </script>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)

        try await Task.sleep(nanoseconds: 500_000_000) // 0.5s

        // This would require actual WKWebView integration
        let result = try await (evaluator as? WKWebView_JavaScriptEvaluating)?
            .evaluateString("window.getTestValue()")
        // Assert result matches expectation
    }
}
```

#### 2.2.6 UI Tests - Workflows (P1 Priority)

**Purpose:** Test complete user workflows with accessibility

**Example Test Case:**

```swift
final class VolumeLoadingWorkflowUITests: XCTestCase {
    func testLoadVolumeAndAdjustOpacity() throws {
        let app = XCUIApplication()
        app.launch()

        // Open volumes sheet
        app.buttons["niivue.volumes"].tap()
        XCTAssertTrue(app.otherElements["niivue.volumesSheet"].waitForExistence(timeout: 2))

        // Import volume (if UI supports it)
        app.buttons["niivue.importVolume"].tap()

        // Adjust opacity slider
        let opacitySlider = app.sliders["niivue.volume.opacity.0"]
        XCTAssertTrue(opacitySlider.waitForExistence(timeout: 5))

        let startPosition = opacitySlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)
        )
        let endPosition = opacitySlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)
        )
        startPosition.press(forDuration: 0, thenDragTo: endPosition)

        // Close sheet
        app.buttons["Done"].tap()
    }
}
```

---

## Part 3: Mock Requirements

### 3.1 Protocol-Based Mocks

#### JavaScriptEvaluating Protocol Mock

```swift
protocol JavaScriptEvaluating {
    func evaluateCommand(_ script: String) async throws
    func evaluateString(_ script: String) async throws -> String
    func callAsyncString(_ script: String) async throws -> String
}

@MainActor
final class MockJavaScriptEvaluator: JavaScriptEvaluating {
    var scripts: [String] = []
    var nextString: String?
    var nextAsyncString: String?
    var shouldThrowError: Error?

    func evaluateCommand(_ script: String) async throws {
        if let error = shouldThrowError { throw error }
        scripts.append(script)
    }

    func evaluateString(_ script: String) async throws -> String {
        if let error = shouldThrowError { throw error }
        scripts.append(script)
        return nextString ?? ""
    }

    func callAsyncString(_ script: String) async throws -> String {
        if let error = shouldThrowError { throw error }
        scripts.append(script)
        return nextAsyncString ?? ""
    }
}
```

#### WKWebView Delegate Mocks

```swift
final class MockWKScriptMessageHandler: NSObject, WKScriptMessageHandler {
    var receivedMessages: [(name: String, body: Any)] = []

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        receivedMessages.append((name: message.name, body: message.body))
    }
}

final class MockWKNavigationDelegate: NSObject, WKNavigationDelegate {
    var didFinishLoading: (() -> Void)?
    var didFailWithError: ((Error) -> Void)?

    func webView(
        _ webView: WKWebView,
        didFinish navigation: WKNavigation!
    ) {
        didFinishLoading?()
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        didFailWithError?(error)
    }
}
```

### 3.2 Stub/Fixture Objects

#### Sample Data Builders

```swift
enum VolumeFixture {
    static func make(
        id: String = UUID().uuidString,
        name: String = "test.nii.gz",
        nFrame4D: Int = 1
    ) -> VolumeInfo {
        VolumeInfo(id: id, name: name, nFrame4D: nFrame4D)
    }
}

enum SessionFixture {
    static func makeViewerState() -> ViewerState {
        ViewerState(
            volumes: [
                VolumeInfo(id: "v1", name: "T1.nii.gz", nFrame4D: 1)
            ]
        )
    }
}
```

### 3.3 Test Doubles Strategy

| Component | Strategy | Reason |
|-----------|----------|--------|
| **JavaScriptEvaluating** | Mock | Capture commands, control return values |
| **FileManager** | Real | Small file operations, test isolation |
| **WKWebView** | Real (integration) or Mock (unit) | Real for integration tests, mock for unit |
| **URLSession** | Mock | Control network responses, speed up tests |
| **UserDefaults** | Real with cleanup | Tests should clean up test data |
| **Codable Types** | Real | Validate actual encoding/decoding |

---

## Part 4: CI/CD Considerations

### 4.1 Xcode Cloud Compatibility

**Configuration File:** `.xcode/workflows/tests.yml`

```yaml
name: Test
on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3

      - name: Run Unit Tests
        run: |
          xcodebuild test \
            -scheme NiiVue \
            -configuration Debug \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -resultBundlePath build/test-results \
            -enableCodeCoverage YES

      - name: Run UI Tests
        run: |
          xcodebuild test \
            -scheme NiiVue \
            -testPlan NiiVueUITests \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -resultBundlePath build/ui-test-results

      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./build/test-results.xcresult
```

### 4.2 GitHub Actions Workflow

```yaml
name: Swift Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  unit-tests:
    runs-on: macos-latest
    strategy:
      matrix:
        xcode: ['15.0', '15.1']
        ios: ['17', '18']
    steps:
      - uses: actions/checkout@v3
      - uses: maxim-lobanov/setup-xcode@v1
        with:
          xcode-version: ${{ matrix.xcode }}

      - name: Run Unit Tests
        run: |
          xcodebuild test \
            -scheme NiiVue \
            -configuration Debug \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -enableCodeCoverage YES \
            | xcpretty

      - name: Upload Coverage to Codecov
        uses: codecov/codecov-action@v3
        with:
          files: ./build/reports/coverage.json

  ui-tests:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      - uses: maxim-lobanov/setup-xcode@v1

      - name: Run UI Tests
        run: |
          xcodebuild test \
            -scheme NiiVue \
            -testPlan NiiVueUITests \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            | xcpretty
```

### 4.3 Simulator vs Device Testing

| Test Type | Simulator | Device | Decision |
|-----------|-----------|--------|----------|
| Unit Tests | Yes | Optional | Run on simulator for speed |
| Service Tests | Yes | No | File I/O works on simulator |
| WebView Integration | Yes | Yes | Verify on device before release |
| UI Tests | Yes | Manual | Run on simulator for CI, device for validation |
| Performance Tests | Yes | Yes | Run on device for accurate metrics |

### 4.4 Parallelization Strategy

```bash
# Run tests in parallel across multiple simulators
xcodebuild test \
  -scheme NiiVue \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4
```

---

## Part 5: Code Coverage Targets

### 5.1 Coverage by Component

| Component | Target | Rationale |
|-----------|--------|-----------|
| **Swift Bridge Layer** | 95% | Critical for JavaScript communication |
| **Type System (Models)** | 90% | Codable implementation validation |
| **View Models** | 85% | State management complexity |
| **Services** | 85% | File I/O, persistence critical |
| **Utilities** | 80% | String processing, validation |
| **UI Layer** | 70% | UI Framework limitations, user testing |
| **Overall Target** | 80% | Production-quality SDK |

### 5.2 Coverage Reporting

```bash
# Generate coverage report
xcodebuild test \
  -scheme NiiVue \
  -enableCodeCoverage YES \
  -derivedDataPath build

# Convert to readable format
xcrun xccov view \
  --report \
  build/Logs/Test/*.xcactivitylog > coverage_report.txt

# Upload to Codecov
bash <(curl -s https://codecov.io/bash) \
  -f coverage_report.txt \
  -F ios
```

### 5.3 Critical Path Coverage Requirements

**Must Achieve 95%+ Coverage:**

1. **WebViewManager** - Command execution path
   - setColormap()
   - setOpacity()
   - loadBase64Image()
   - loadImageFromUrl()
   - loadVolumesFromUrls()

2. **JavaScript Bridge** - All public methods
   - Command generation
   - Parameter escaping
   - Async evaluation

3. **Security Components**
   - NiivueURLRouter validation
   - JavaScriptQuote escaping
   - SessionStore ID validation
   - FileImportService path handling

**Should Achieve 85%+ Coverage:**

4. **Services** - Core functionality
   - FileImportService
   - SessionStore
   - DicomSeriesStore
   - ImportedFileStore

5. **Types** - All Codable implementations
   - VolumeInfo
   - SessionSnapshotV1
   - ViewerState
   - All nested types

---

## Part 6: Test Strategy Document

### 6.1 Testing Principles

1. **Test Isolation** - Each test is independent
2. **Fast Execution** - Unit tests complete in <100ms
3. **Clear Assertions** - One concept per test
4. **Mock Boundaries** - Mock at architecture boundaries
5. **Real File Operations** - Test actual FileManager behavior
6. **Security First** - Input validation is critical

### 6.2 Test Organization

```
NiiVueTests/
├── Unit/
│   ├── Bridge/
│   │   ├── VolumeCommandTests.swift
│   │   ├── MeshCommandTests.swift
│   │   ├── DrawingCommandTests.swift
│   │   └── ViewCommandTests.swift
│   ├── Types/
│   │   ├── VolumeInfoTests.swift
│   │   ├── ViewerStateTests.swift
│   │   └── EnumTests.swift
│   ├── Services/
│   │   ├── FileImportServiceTests.swift
│   │   ├── SessionStoreTests.swift
│   │   └── ImageCacheTests.swift
│   ├── Security/
│   │   ├── JavaScriptQuoteTests.swift
│   │   ├── URLRouterTests.swift
│   │   └── IDValidationTests.swift
│   └── ViewModels/
│       ├── NiiVueViewModelTests.swift
│       └── VolumeListViewModelTests.swift
├── Integration/
│   ├── WebViewIntegrationTests.swift
│   ├── FileSystemIntegrationTests.swift
│   └── JSONSerializationTests.swift
└── Helpers/
    ├── Mocks/
    │   ├── MockJavaScriptEvaluator.swift
    │   ├── MockWebViewDelegate.swift
    │   └── MockURLSession.swift
    └── Fixtures/
        ├── VolumeFixture.swift
        ├── SessionFixture.swift
        └── TestData.swift

NiiVueUITests/
├── Components/
│   ├── VolumesSheetTests.swift
│   ├── SegmentationSheetTests.swift
│   └── SessionsSheetTests.swift
├── Workflows/
│   ├── VolumeLoadingWorkflowTests.swift
│   ├── DrawingWorkflowTests.swift
│   └── SessionManagementWorkflowTests.swift
└── Helpers/
    ├── XCUIApplication+Extensions.swift
    └── Accessibility+Constants.swift
```

### 6.3 Test Naming Convention

**Pattern:** `test[Subject][Condition][Expected]`

Examples:
```swift
// Unit Tests
func testWebViewManagerSetsColormapWhenCalledWithValidColormap()
func testJavaScriptQuoteEscapesDoubleQuotesCorrectly()
func testFileImportServiceMovesFileToDestinationDirectory()
func testSessionStoreRejectsPathTraversalInID()

// UI Tests
func testVolumesSheetOpensWhenButtonTapped()
func testOpacitySliderUpdatesVolumeOpacity()
func testLoadingOverlayDisappearsWhenWebViewBecomesReady()
```

### 6.4 Assertion Best Practices

**Preferred:**
```swift
XCTAssertEqual(volume.name, "T1.nii.gz", "Volume name should match input")
XCTAssertTrue(js.scripts.contains(where: { $0.contains("setColormap") }))
XCTAssertNil(error, "Should not throw error for valid input")
```

**Avoid:**
```swift
XCTAssert(volume.name == "T1.nii.gz")  // Use XCTAssertEqual instead
XCTAssert(js.scripts[0].contains("setColormap"))  // May crash on empty array
XCTAssertFalse(error != nil)  // Use XCTAssertNil
```

### 6.5 Async/Await Best Practices

```swift
// Correct
@MainActor
final class MyTests: XCTestCase {
    func testAsyncOperation() async throws {
        let result = try await service.loadData()
        XCTAssertEqual(result.count, 5)
    }
}

// Wait for expectations
func testWebViewDelegate() async throws {
    let expectation = expectation(description: "webView finished loading")
    let delegate = MockDelegate { expectation.fulfill() }

    webView.navigationDelegate = delegate
    webView.load(request)

    await fulfillment(of: [expectation], timeout: 5)
}
```

### 6.6 Performance Testing Guidelines

```swift
final class PerformanceTests: XCTestCase {
    func testJavaScriptExecutionPerformance() throws {
        let js = MockJavaScriptEvaluator()

        measure {
            for i in 0..<100 {
                _ = try? js.evaluateString("window.test(\(i))")
            }
        }
    }

    func testFileImportPerformanceFor50MB() throws {
        let largeFile = Data(repeating: 0xFF, count: 50 * 1024 * 1024)

        measure(metrics: [XCTMemoryMetric(), XCTClockMetric()]) {
            let encoded = Base64FileEncoder.encodeFileToBase64(url: url, maxBytes: Int.max)
            XCTAssertNotNil(encoded)
        }
    }
}
```

---

## Part 7: Example Test Cases by Priority

### 7.1 P0 Priority - Must Have Tests

#### Test: JavaScript Bridge - Volume Loading

```swift
@MainActor
final class VolumeCommandTests: XCTestCase {
    func testLoadVolumesGeneratesValidJavaScript() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        let volumes = [
            (url: "niivue://app/files/v1", name: "T1.nii.gz"),
            (url: "niivue://app/files/v2", name: "T2.nii.gz")
        ]

        try await manager.loadVolumesFromUrls(volumes)

        XCTAssertEqual(js.scripts.count, 2)  // loadVolumes + getVolumeInfoList
        XCTAssertTrue(js.scripts[0].contains("return await window.loadVolumesFromUrls("))
        XCTAssertTrue(js.scripts[0].contains("\"T1.nii.gz\""))
        XCTAssertTrue(js.scripts[0].contains("\"T2.nii.gz\""))
    }

    func testLoadVolumesEscapesSpecialCharactersInFilenames() async throws {
        let js = MockJavaScriptEvaluator()
        let manager = WebViewManager(evaluator: js)

        try await manager.loadVolumesFromUrls([
            (url: "test", name: "file\"with\\backslash.nii.gz")
        ])

        let json = js.scripts[0]
        XCTAssertTrue(json.contains("\\\"with\\\\backslash"))
    }

    func testLoadVolumesThrowsOnInvalidURL() async throws {
        let js = MockJavaScriptEvaluator()
        js.shouldThrowError = NSError(domain: "test", code: 1, userInfo: nil)
        let manager = WebViewManager(evaluator: js)

        do {
            try await manager.loadVolumesFromUrls([(url: "", name: "")])
            XCTFail("Should throw error")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
```

#### Test: Type System - Codable

```swift
final class VolumeInfoCodableTests: XCTestCase {
    func testVolumeInfoDecodesFromValidJSON() throws {
        let json = """
        {
            "id": "vol-123",
            "name": "T1w.nii.gz",
            "nFrame4D": 45,
            "colormap": "gray",
            "opacity": 0.75
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let volume = try JSONDecoder().decode(VolumeInfo.self, from: data)

        XCTAssertEqual(volume.id, "vol-123")
        XCTAssertEqual(volume.name, "T1w.nii.gz")
        XCTAssertEqual(volume.nFrame4D, 45)
        XCTAssertEqual(volume.opacity, 0.75)
    }

    func testVolumeInfoEncodesToValidJSON() throws {
        let volume = VolumeInfo(
            id: "vol-456",
            name: "T2w.nii.gz",
            nFrame4D: 30
        )

        let encoded = try JSONEncoder().encode(volume)
        let decoded = try JSONDecoder().decode(VolumeInfo.self, from: encoded)

        XCTAssertEqual(decoded.id, volume.id)
        XCTAssertEqual(decoded.name, volume.name)
        XCTAssertEqual(decoded.nFrame4D, volume.nFrame4D)
    }
}
```

#### Test: Security - Path Traversal

```swift
final class SecurityTests: XCTestCase {
    func testSessionStoreRejectsPathTraversalIDs() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = SessionStore(sessionsDirectory: tempDir)

        // Create file outside sessions directory
        let outsideFile = tempDir.deletingLastPathComponent()
            .appendingPathComponent("outside.json")
        try "{}".write(to: outsideFile, atomically: true, encoding: .utf8)

        // Attempt path traversal
        do {
            _ = try await store.load(id: "../outside")
            XCTFail("Should reject path traversal")
        } catch SessionStoreError.invalidID {
            // Expected
        }
    }

    func testURLRouterRejectsURLEncodedPathTraversal() {
        let router = NiivueURLRouter()

        XCTAssertNil(router.route(URL(string: "niivue://app/files/%2e%2e/secrets.txt")!))
        XCTAssertNil(router.route(URL(string: "niivue://app/files/%252e%252e/secrets.txt")!))
    }
}
```

### 7.2 P1 Priority - Important Tests

#### Test: UI Workflow

```swift
final class VolumeLoadingUIWorkflowTests: XCTestCase {
    func testLoadMultipleVolumesAndAdjustControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        // Wait for webview to be ready
        let readyLabel = app.staticTexts["niivue.isReady"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }

        // Open volumes sheet
        app.buttons["niivue.volumes"].tap()
        XCTAssertTrue(app.otherElements["niivue.volumesSheet"].waitForExistence(timeout: 2))

        // Verify controls exist for first volume
        let opacitySlider = app.sliders["niivue.volume.opacity.0"]
        XCTAssertTrue(opacitySlider.waitForExistence(timeout: 5))

        // Adjust opacity
        let start = opacitySlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)
        )
        let end = opacitySlider.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        )
        start.press(forDuration: 0, thenDragTo: end)

        // Verify colormap button exists
        XCTAssertTrue(app.buttons["niivue.volume.colormap.0"].exists)

        app.buttons["Done"].tap()
    }
}
```

---

## Part 8: Running Tests in NiiVueKit

### 8.1 Command Line

```bash
# Run all tests
xcodebuild test -scheme NiiVue

# Run specific test class
xcodebuild test -scheme NiiVue \
  -testPlan NiiVueTests \
  -testFilter "VolumeCommandTests"

# Run with coverage
xcodebuild test -scheme NiiVue \
  -enableCodeCoverage YES

# Run UI tests only
xcodebuild test -scheme NiiVue \
  -testPlan NiiVueUITests

# Run on specific device
xcodebuild test -scheme NiiVue \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

### 8.2 Xcode Shortcuts

- `Cmd + U` - Run all tests
- `Cmd + Ctrl + U` - Run tests with coverage
- Click diamond icon next to test name - Run single test
- `Cmd + ^` - Show/hide test navigator

### 8.3 GitHub Actions Integration

Pull requests will automatically:
1. Run unit tests on iPhone 15 simulator
2. Run UI tests on iPhone 15 simulator
3. Generate code coverage report
4. Comment with coverage delta on PR

---

## Part 9: Maintenance and Evolution

### 9.1 Test Review Checklist

Before committing new tests:

- [ ] Test name clearly describes behavior
- [ ] Test is independent (no ordering dependencies)
- [ ] Test cleans up after itself (temp files, state)
- [ ] All assertions have descriptive messages
- [ ] Mock usage is appropriate for the test type
- [ ] Test runs in <1 second (unit) or <5 seconds (UI)
- [ ] Code coverage target maintained or improved

### 9.2 Quarterly Review Schedule

**Q1:** Unit test coverage analysis
**Q2:** UI test expansion for new features
**Q3:** Performance testing baseline
**Q4:** Security and edge case testing

### 9.3 Deprecation Path for Old Tests

When refactoring, deprecated tests should:
1. Be marked with `@Deprecated` comment
2. Have migration guide
3. Be removed in next major version

---

## Appendix A: Test Execution Matrix

```
Platform: iOS Simulator
Device: iPhone 15, iPhone 14 Pro Max
OS: iOS 17.2, iOS 18.0
Xcode: 15.0+

Test Environment:
- Unit Tests: Happy DOM (no WebView)
- Integration Tests: Real WKWebView
- UI Tests: XCUITest framework
- Performance: XCTestMetrics

Expected Runtime:
- Unit Tests: ~30 seconds (all 20 tests)
- UI Tests: ~60 seconds (all 12 tests)
- Total: ~90 seconds for full suite
```

---

## Appendix B: Coverage Report Template

```
NiiVueKit Test Coverage Report
Generated: [Date]

Component Coverage:
  WebViewManager          95.2%  ✓ PASS
  JavaScript Bridge       94.8%  ✓ PASS
  Type System             92.1%  ✓ PASS
  Services                87.3%  ✓ PASS
  View Models             84.6%  ✓ PASS
  UI Components           71.2%  ⚠ WARN (below target)

Overall: 86.8% ✓ PASS

Critical Paths:
  loadVolumesFromUrls()               98%
  setColormap()                       96%
  JavaScriptQuote.jsonStringLiteral() 100%
  NiivueURLRouter.route()             97%

Untested Code:
  - Error path in NetworkManager (deprecated)
  - Legacy API compatibility layer
  - Performance optimization branch

Recommendations:
1. Add UI tests for SettingsView (currently 52%)
2. Test error handling in FileImportService
3. Add performance baselines
```

---

## Appendix C: References

- [Apple XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [WWDC 2023: Testing Best Practices](https://developer.apple.com/videos/play/wwdc2023/10120/)
- [Swift Concurrency Testing Patterns](https://github.com/apple/swift-async-algorithms)
- [Accessibility Testing with XCUITest](https://developer.apple.com/documentation/xctest/user_interface_testing)

---

**Document Approval:**
- [ ] Engineering Lead
- [ ] QA Lead
- [ ] Product Manager

**Next Review Date:** Q2 2026
