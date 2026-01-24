# NiivueKit Internal SDK Architecture

**Version:** 1.0
**Date:** January 4, 2026
**Status:** Design Document

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Layer Architecture](#2-layer-architecture)
3. [Protocol Abstractions](#3-protocol-abstractions)
4. [Actor Model Usage](#4-actor-model-usage)
5. [State Management](#5-state-management)
6. [Resource Bundling](#6-resource-bundling)
7. [Error Propagation](#7-error-propagation)
8. [Memory Management](#8-memory-management)
9. [Component Diagrams](#9-component-diagrams)
10. [Data Flow Diagrams](#10-data-flow-diagrams)
11. [Implementation Recommendations](#11-implementation-recommendations)

---

## 1. Executive Summary

NiivueKit is a Swift SDK that wraps the Niivue neuroimaging visualization library running in WKWebView. The architecture follows a layered approach that separates concerns, enables testability through protocol abstractions, and ensures thread safety through Swift's actor model.

### Design Principles

1. **Protocol-Oriented Design** - All external dependencies abstracted behind protocols
2. **Actor Isolation** - Thread safety without explicit locking
3. **MainActor by Default** - UI components and WebKit callbacks on main thread
4. **Dependency Injection** - Enable testing and flexibility
5. **Thin State Synchronization** - Avoid duplicating large data structures
6. **Graceful Degradation** - Fallback strategies for error conditions

### Current Implementation Analysis

The existing codebase demonstrates solid foundations:
- `JavaScriptEvaluating` protocol for testable JS bridge
- `DicomSeriesStore` and `ImportedFileStore` as actors
- `WebViewManager` as `@MainActor` with dependency injection
- Custom URL scheme (`niivue://`) for file serving

---

## 2. Layer Architecture

### 2.1 Four-Layer Model

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         LAYER 1: PUBLIC API                                  │
│  NiivueKit (facade) + NiivueView (SwiftUI) + NiivueViewController (UIKit)   │
├─────────────────────────────────────────────────────────────────────────────┤
│                         LAYER 2: BRIDGE                                      │
│  WebViewManager + JavaScriptEvaluating + NiivueCommands + EventDispatcher   │
├─────────────────────────────────────────────────────────────────────────────┤
│                         LAYER 3: WEBVIEW MANAGEMENT                          │
│  NiivueURLSchemeHandler + NiivueURLRouter + WKWebView Configuration         │
├─────────────────────────────────────────────────────────────────────────────┤
│                         LAYER 4: RESOURCE/ASSET                              │
│  ReactBundleProvider + WASMModules + SampleAssets + ImportedFileStore       │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Layer Responsibilities

#### Layer 1: Public API Layer

**Purpose:** What developers see and interact with

```swift
// Primary entry point - Facade pattern
public final class NiivueKit: ObservableObject {
    // Published state for SwiftUI bindings
    @Published public private(set) var isReady: Bool = false
    @Published public private(set) var volumes: [VolumeInfo] = []
    @Published public private(set) var lastError: NiivueError?

    // Configuration
    public var configuration: NiivueConfiguration

    // Core operations
    public func loadVolume(from url: URL) async throws
    public func loadDICOM(files: [URL]) async throws
    public func setColormap(_ colormap: String, for volumeIndex: Int) async throws

    // Delegate for advanced events
    public weak var delegate: NiivueKitDelegate?
}

// SwiftUI integration
public struct NiivueView: UIViewRepresentable {
    @ObservedObject var kit: NiivueKit

    public init(kit: NiivueKit = NiivueKit())
    public init(configuration: NiivueConfiguration)
}

// UIKit integration
public class NiivueViewController: UIViewController {
    public let kit: NiivueKit

    public init(configuration: NiivueConfiguration = .default)
}
```

**Design Notes:**
- `NiivueKit` is the single facade that hides complexity
- Published properties enable reactive SwiftUI UIs
- Both SwiftUI and UIKit entry points share the same `NiivueKit` instance
- Configuration object for customization

#### Layer 2: Bridge Layer

**Purpose:** Swift-to-JavaScript communication

```swift
// Command builder for type-safe JS calls
@MainActor
internal struct NiivueCommands {
    private let evaluator: JavaScriptEvaluating

    // Volume operations
    func loadFromUrl(_ url: String, name: String) async throws
    func removeVolume(at index: Int) async throws
    func setCalMinMax(volumeIndex: Int, min: Double, max: Double) async throws

    // View operations
    func setSliceType(_ type: SliceType) async throws
    func setRenderAzimuthElevation(azimuth: Double, elevation: Double) async throws

    // Drawing operations
    func setPenValue(_ value: Int, filled: Bool, enabled: Bool) async throws
    func saveDrawing() async throws -> Data?
}

// Event dispatcher for JS-to-Swift callbacks
@MainActor
internal final class EventDispatcher {
    weak var delegate: NiivueEventDelegate?

    func handleScriptMessage(name: String, body: Any) {
        switch name {
        case "volumeLoaded":
            delegate?.niivue(didLoadVolume: parseVolumeInfo(body))
        case "locationChange":
            delegate?.niivue(crosshairMovedTo: parseLocation(body))
        case "intensityChange":
            delegate?.niivue(intensityChangedTo: parseIntensity(body))
        // ... other events
        }
    }
}
```

**Design Notes:**
- `NiivueCommands` provides type-safe method calls
- `EventDispatcher` centralizes callback handling
- Both use the `JavaScriptEvaluating` protocol for testability

#### Layer 3: WebView Management Layer

**Purpose:** WKWebView lifecycle and URL routing

```swift
// URL routing with security checks
internal struct NiivueURLRouter {
    enum Route {
        case dist(path: String)           // React bundle
        case sample(path: String)         // Sample assets
        case importedFile(id: String)     // User imports
        case dicomManifest(seriesId: String)
        case dicomFile(seriesId: String, fileName: String)
        case wasm(module: String)         // WASM modules
    }

    func route(_ url: URL) -> Route?
}

// URL scheme handler with chunked streaming
@MainActor
internal final class NiivueURLSchemeHandler: NSObject, WKURLSchemeHandler {
    var importedFileStore: ImportedFileStore?
    var dicomSeriesStore: DicomSeriesStore?

    private let chunkSize = 64 * 1024  // 64KB chunks
    private var activeTasks: [ObjectIdentifier: Task<Void, Never>] = [:]

    // Cancellation-safe streaming
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask)
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask)
}
```

**Design Notes:**
- Router validates paths and prevents directory traversal
- Handler streams large files in chunks
- Proper cancellation handling for interrupted requests

#### Layer 4: Resource/Asset Layer

**Purpose:** Bundle resources and file management

```swift
// React bundle provider
internal struct ReactBundleProvider {
    static func bundleURL() -> URL {
        Bundle.module.url(forResource: "dist", withExtension: nil)!
    }

    static func wasmModulesURL() -> URL {
        bundleURL().appendingPathComponent("wasm")
    }
}

// File stores as actors
actor ImportedFileStore {
    private var map: [String: URL] = [:]

    func register(id: String, url: URL)
    func url(for id: String) -> URL?
    func remove(id: String)
}

actor DicomSeriesStore {
    private var series: [String: [String: URL]] = [:]

    func register(files: [URL]) -> String
    func manifestText(for seriesId: String) -> String
    func url(for seriesId: String, fileName: String) -> URL?
}
```

---

## 3. Protocol Abstractions

### 3.1 Existing Protocol: JavaScriptEvaluating

The current implementation provides an excellent foundation:

```swift
@MainActor
protocol JavaScriptEvaluating: AnyObject {
    /// Fire-and-forget command
    func evaluateCommand(_ javaScript: String) async throws

    /// Expression that returns a string
    func evaluateString(_ javaScript: String) async throws -> String?

    /// Async function body (for Promise-returning APIs)
    func callAsyncString(_ functionBody: String) async throws -> String?
}
```

**Current Conformers:**
- `WKWebView` (production) via extension
- `MockJavaScriptEvaluator` (testing)

### 3.2 Proposed Additional Protocols

#### NiivueEventDelegate

```swift
@MainActor
public protocol NiivueEventDelegate: AnyObject {
    // Volume events
    func niivue(_ kit: NiivueKit, didLoadVolume info: VolumeInfo)
    func niivue(_ kit: NiivueKit, didRemoveVolumeAt index: Int)
    func niivue(_ kit: NiivueKit, volumeAt index: Int, intensityChangedTo range: ClosedRange<Double>)

    // Navigation events
    func niivue(_ kit: NiivueKit, crosshairMovedTo location: CrosshairLocation)
    func niivue(_ kit: NiivueKit, viewRotatedTo azimuth: Double, elevation: Double)

    // Rendering events
    func niivue(_ kit: NiivueKit, didChangeSliceTypeTo type: SliceType)
    func niivue(_ kit: NiivueKit, clipPlaneChangedTo plane: ClipPlane)

    // Error events
    func niivue(_ kit: NiivueKit, didEncounterError error: NiivueError)
}

// Default implementations for optional conformance
public extension NiivueEventDelegate {
    func niivue(_ kit: NiivueKit, didLoadVolume info: VolumeInfo) {}
    func niivue(_ kit: NiivueKit, didRemoveVolumeAt index: Int) {}
    // ... defaults for all methods
}
```

#### FileStoring (Generalized Store Protocol)

```swift
protocol FileStoring: Actor {
    associatedtype Key: Hashable

    func register(id: Key, url: URL) async
    func url(for id: Key) async -> URL?
    func remove(id: Key) async
    func allKeys() async -> [Key]
}

// Conformance
extension ImportedFileStore: FileStoring {
    typealias Key = String
}

extension DicomSeriesStore {
    // DicomSeriesStore has more complex API but could partially conform
}
```

#### ResourceProviding

```swift
protocol ResourceProviding {
    func url(forResource name: String, withExtension ext: String?) -> URL?
    func contentsOfDirectory(at url: URL) throws -> [URL]
}

// Production implementation
struct BundleResourceProvider: ResourceProviding {
    let bundle: Bundle

    func url(forResource name: String, withExtension ext: String?) -> URL? {
        bundle.url(forResource: name, withExtension: ext)
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
    }
}

// Test implementation
struct MockResourceProvider: ResourceProviding {
    var resources: [String: URL] = [:]

    func url(forResource name: String, withExtension ext: String?) -> URL? {
        let key = ext.map { "\(name).\($0)" } ?? name
        return resources[key]
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        []
    }
}
```

### 3.3 Dependency Injection Pattern

```swift
// Configuration struct with protocol-typed dependencies
public struct NiivueConfiguration {
    // User-facing options
    public var crosshairColor: [Double] = [1, 0, 0, 1]
    public var showColorbar: Bool = true
    public var radiologicalConvention: Bool = false

    // Internal dependencies (for testing)
    internal var evaluatorFactory: (() -> JavaScriptEvaluating)?
    internal var resourceProvider: ResourceProviding?

    public static var `default`: NiivueConfiguration { .init() }
}

// Usage in NiivueKit
@MainActor
public final class NiivueKit: ObservableObject {
    private let evaluator: JavaScriptEvaluating
    private let resourceProvider: ResourceProviding

    public init(configuration: NiivueConfiguration = .default) {
        // Use injected dependencies or defaults
        self.resourceProvider = configuration.resourceProvider ?? BundleResourceProvider(bundle: .module)

        // WebView must be created before evaluator
        let webView = Self.createWebView()
        self.evaluator = configuration.evaluatorFactory?() ?? webView
    }
}
```

---

## 4. Actor Model Usage

### 4.1 Current Actor Usage Analysis

The existing codebase correctly uses actors for:

| Actor | Purpose | State Protected |
|-------|---------|-----------------|
| `DicomSeriesStore` | DICOM file mapping | `series: [String: [String: URL]]` |
| `ImportedFileStore` | Imported file registry | `map: [String: URL]` |
| `SessionStore` | Session persistence | File system operations |

### 4.2 Recommended Additional Actors

#### VolumeStateActor

```swift
/// Maintains authoritative state for loaded volumes
actor VolumeStateActor {
    struct VolumeState: Sendable {
        let id: String
        let name: String
        var colormap: String
        var opacity: Double
        var calMin: Double?
        var calMax: Double?
        var frame4D: Int
        let nFrames4D: Int
    }

    private var volumes: [VolumeState] = []
    private var pendingUpdates: [String: VolumeState] = [:]

    // Bulk operations
    func setVolumes(_ volumes: [VolumeState])
    func addVolume(_ volume: VolumeState)
    func removeVolume(at index: Int) -> VolumeState?

    // Per-volume updates (received from JS callbacks)
    func updateVolume(id: String, colormap: String?, opacity: Double?, frame4D: Int?)

    // Query
    func allVolumes() -> [VolumeState]
    func volume(at index: Int) -> VolumeState?
}
```

**Why Actor:**
- Multiple sources update volume state (user actions, JS callbacks)
- Prevents race conditions between Swift updates and JS notifications

#### RenderStateActor

```swift
/// Maintains 3D rendering state
actor RenderStateActor {
    struct RenderState: Sendable {
        var azimuth: Double = 110
        var elevation: Double = 10
        var zoom: Double = 1.0
        var clipPlane: ClipPlane?
    }

    private var state = RenderState()
    private var lastKnownJSState: RenderState?

    func update(azimuth: Double?, elevation: Double?, zoom: Double?)
    func setClipPlane(_ plane: ClipPlane?)

    // Conflict detection
    func checkForConflict(with jsState: RenderState) -> ConflictResolution
}
```

### 4.3 MainActor Isolation Strategy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              @MainActor                                      │
│  ┌───────────────────┐  ┌───────────────────┐  ┌───────────────────────┐   │
│  │    NiivueKit      │  │  WebViewManager   │  │  NiivueURLScheme      │   │
│  │    (facade)       │  │  (bridge owner)   │  │  Handler              │   │
│  └─────────┬─────────┘  └─────────┬─────────┘  └───────────┬───────────┘   │
│            │                      │                        │                │
│            │   ┌──────────────────┴──────────────────┐    │                │
│            │   │         WKWebView                    │    │                │
│            │   │  (all WebKit callbacks on main)      │    │                │
│            │   └──────────────────────────────────────┘    │                │
│            │                                               │                │
└────────────┼───────────────────────────────────────────────┼────────────────┘
             │                                               │
             ▼                                               ▼
    ┌────────────────────┐                     ┌────────────────────────┐
    │  VolumeStateActor  │                     │  ImportedFileStore     │
    │  (isolated)        │                     │  (actor)               │
    └────────────────────┘                     └────────────────────────┘
             │                                               │
             ▼                                               ▼
    ┌────────────────────┐                     ┌────────────────────────┐
    │  RenderStateActor  │                     │  DicomSeriesStore      │
    │  (isolated)        │                     │  (actor)               │
    └────────────────────┘                     └────────────────────────┘
```

**Rules:**
1. All WKWebView interactions: `@MainActor`
2. All UI state (`@Published`): `@MainActor`
3. File/data stores: `actor` (background-safe)
4. CPU-intensive work: `Task.detached` with appropriate priority

### 4.4 Thread Safety for WebKit Callbacks

```swift
@MainActor
final class WebViewManager: NSObject {
    // Weak proxy to break retain cycle
    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
        weak var owner: WebViewManager?

        func userContentController(
            _ controller: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // Already on main thread (WKScriptMessageHandler guarantee)
            owner?.handleScriptMessage(name: message.name, body: message.body)
        }
    }

    func handleScriptMessage(name: String, body: Any) {
        // Safe to access @Published properties here
        switch name {
        case "volumeLoaded":
            // Parse and update volumes array
            Task { @MainActor in
                self.volumes.append(parseVolume(body))
            }
        case "locationChange":
            lastLocationString = parseLocation(body)
        }
    }
}
```

---

## 5. State Management

### 5.1 State Synchronization Strategy

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SWIFT SIDE (Source of Commands)                      │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    NiivueKit.volumes: [VolumeInfo]                  │    │
│  │                         (Published, reactive)                        │    │
│  └──────────────────────────────────┬──────────────────────────────────┘    │
│                                      │                                       │
│            ┌─────────────────────────┴─────────────────────────┐            │
│            │                    Commands                        │            │
│            │  setColormap(idx, "hot") ───────────────────────▶ │            │
│            │  loadVolume(url) ───────────────────────────────▶ │            │
│            │                                                    │            │
│            │                    Events                          │            │
│            │  ◀─────────────────────── onVolumeLoaded(info)    │            │
│            │  ◀─────────────────────── onIntensityChange(...)   │            │
│            └────────────────────────────────────────────────────┘            │
│                                      │                                       │
└──────────────────────────────────────┼───────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                        JAVASCRIPT SIDE (Source of Truth)                     │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                       nv.volumes: NVImage[]                         │    │
│  │                         (Authoritative state)                        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 5.2 Shadow Copy Strategy

**Recommendation: Thin Shadow Copies**

```swift
// Swift-side shadow copy (metadata only, NOT image data)
public struct VolumeInfo: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var colormap: String
    public var opacity: Double
    public var calMin: Double?
    public var calMax: Double?
    public var currentFrame: Int
    public let totalFrames: Int
}

// DO NOT store:
// - Raw voxel data (stays in JS/WebGL textures)
// - Base64-encoded images
// - Large computed results
```

**Synchronization Rules:**

1. **Commands (Swift -> JS):** Optimistic update + rollback on failure
2. **Events (JS -> Swift):** Replace shadow copy with authoritative data
3. **Queries:** Always prefer JS-side query for current state

```swift
@MainActor
func setColormap(_ colormap: String, volumeIndex: Int) async throws {
    let previousColormap = volumes[volumeIndex].colormap

    // Optimistic update for responsive UI
    volumes[volumeIndex].colormap = colormap

    do {
        try await commands.setColormap(volumeIndex: volumeIndex, colormap: colormap)
    } catch {
        // Rollback on failure
        volumes[volumeIndex].colormap = previousColormap
        throw error
    }
}
```

### 5.3 Conflict Resolution

```swift
enum ConflictResolution {
    case swiftWins   // Use Swift-side value (user just changed it)
    case jsWins      // Use JS-side value (more recent from callback)
    case merge       // Attempt to merge (complex scenarios)
}

actor StateConflictResolver {
    private var lastSwiftUpdate: [String: Date] = [:]
    private let conflictWindow: TimeInterval = 0.5  // 500ms

    func resolveConflict(
        property: String,
        swiftValue: Any,
        jsValue: Any
    ) -> ConflictResolution {
        guard let lastUpdate = lastSwiftUpdate[property] else {
            return .jsWins
        }

        if Date().timeIntervalSince(lastUpdate) < conflictWindow {
            return .swiftWins  // Recent user action takes precedence
        }

        return .jsWins
    }

    func recordSwiftUpdate(property: String) {
        lastSwiftUpdate[property] = Date()
    }
}
```

---

## 6. Resource Bundling

### 6.1 SPM Bundle Structure

```
NiivueKit/
├── Package.swift
├── Sources/
│   └── NiivueKit/
│       ├── NiivueKit.swift
│       ├── Web/
│       ├── Services/
│       └── Resources/
│           ├── dist/                    # React build output
│           │   ├── index.html
│           │   └── assets/
│           │       ├── index-xxx.js
│           │       └── index-xxx.css
│           ├── wasm/                    # WebAssembly modules
│           │   ├── dcm2niix.wasm
│           │   ├── dcm2niix-worker.js
│           │   └── codecs/
│           │       ├── blosc.wasm
│           │       └── zstd.wasm
│           └── samples/                 # Demo assets
│               └── T1w_DEMO.nii.gz
└── Tests/
```

### 6.2 Package.swift Configuration

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NiivueKit",
    platforms: [
        .iOS(.v16),      // WKWebView async JS requires iOS 16.4+
        .macOS(.v13)
    ],
    products: [
        .library(name: "NiivueKit", targets: ["NiivueKit"])
    ],
    targets: [
        .target(
            name: "NiivueKit",
            resources: [
                .copy("Resources/dist"),
                .copy("Resources/wasm"),
                .copy("Resources/samples")
            ]
        ),
        .testTarget(
            name: "NiivueKitTests",
            dependencies: ["NiivueKit"]
        )
    ]
)
```

### 6.3 Resource Loading Strategy

```swift
internal enum ResourceBundle {
    static var module: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        // Fallback for non-SPM (e.g., Xcode project)
        return Bundle(for: NiivueKit.self)
        #endif
    }

    static func distURL() -> URL {
        guard let url = module.url(forResource: "dist", withExtension: nil) else {
            fatalError("NiivueKit: dist/ folder not found in bundle")
        }
        return url
    }

    static func wasmURL(module name: String) -> URL? {
        module.url(forResource: name, withExtension: "wasm", subdirectory: "wasm")
    }

    static func sampleURL(named name: String) -> URL? {
        module.url(forResource: name, withExtension: nil, subdirectory: "samples")
    }
}
```

### 6.4 Version Compatibility

```swift
public struct NiivueVersion: Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let buildDate: Date

    public static let current = NiivueVersion(major: 0, minor: 1, patch: 0, buildDate: .now)
}

// Version check at initialization
@MainActor
public final class NiivueKit {
    public static func checkVersionCompatibility() async throws {
        // Query JS-side version
        let jsVersionString = try await evaluator.evaluateString("window.__NIIVUE_VERSION__")

        guard let jsVersion = parseVersion(jsVersionString) else {
            throw NiivueError.versionMismatch(expected: NiivueVersion.current, found: nil)
        }

        // Check compatibility
        if jsVersion.major != NiivueVersion.current.major {
            throw NiivueError.versionMismatch(expected: NiivueVersion.current, found: jsVersion)
        }
    }
}
```

---

## 7. Error Propagation

### 7.1 Error Taxonomy

```swift
public enum NiivueError: LocalizedError, Sendable {
    // Initialization errors
    case webViewInitializationFailed(underlying: Error?)
    case bundleResourceMissing(resource: String)
    case versionMismatch(expected: NiivueVersion, found: NiivueVersion?)

    // JavaScript errors
    case javaScriptEvaluationFailed(script: String, message: String)
    case javaScriptTimeout(operation: String, timeoutSeconds: Double)
    case javaScriptException(name: String, message: String, stack: String?)

    // Volume errors
    case volumeLoadFailed(url: String, reason: String)
    case volumeNotFound(index: Int)
    case unsupportedFormat(extension: String)
    case fileTooLarge(sizeBytes: Int64, maxBytes: Int64)

    // DICOM errors
    case dicomConversionFailed(dcm2niixMessage: String)
    case noValidDicomFiles(attempted: Int)
    case mixedDicomSeries(seriesCount: Int)

    // State errors
    case notReady
    case operationCancelled

    public var errorDescription: String? {
        switch self {
        case .webViewInitializationFailed(let underlying):
            return "WebView initialization failed: \(underlying?.localizedDescription ?? "unknown")"
        case .javaScriptTimeout(let op, let timeout):
            return "Operation '\(op)' timed out after \(timeout) seconds"
        // ... other cases
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .notReady:
            return "Wait for the viewer to finish loading before performing operations"
        case .fileTooLarge:
            return "Try loading a smaller file or enable streaming mode"
        // ... other cases
        }
    }
}
```

### 7.2 JavaScript Error Surface

```swift
@MainActor
internal struct JavaScriptErrorParser {
    /// Parse error from JS exception
    static func parse(from jsError: Error) -> NiivueError {
        let message = String(describing: jsError)

        // Extract error name and message from WebKit error format
        if let match = message.firstMatch(of: /Error: (.+)/) {
            return .javaScriptEvaluationFailed(
                script: "unknown",
                message: String(match.1)
            )
        }

        return .javaScriptEvaluationFailed(script: "unknown", message: message)
    }
}

// Enhanced evaluator with error parsing
extension WKWebView {
    func evaluateCommandWithParsedError(_ js: String) async throws {
        do {
            try await evaluateJavaScript(js)
        } catch {
            throw JavaScriptErrorParser.parse(from: error)
        }
    }
}
```

### 7.3 Timeout Handling

```swift
@MainActor
internal struct TimeoutWrapper {
    static func withTimeout<T: Sendable>(
        seconds: Double,
        operation: String,
        task: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await task()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NiivueError.javaScriptTimeout(operation: operation, timeoutSeconds: seconds)
            }

            // Return first completed, cancel remaining
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}

// Usage
func loadVolume(from url: URL) async throws {
    try await TimeoutWrapper.withTimeout(seconds: 30, operation: "loadVolume") {
        try await self.commands.loadFromUrl(url.absoluteString, name: url.lastPathComponent)
    }
}
```

### 7.4 Recovery Strategies

```swift
@MainActor
internal final class RecoveryManager {
    private var failureCount: [String: Int] = [:]
    private let maxRetries = 3

    func withRetry<T>(
        operation: String,
        task: () async throws -> T,
        shouldRetry: (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?

        for attempt in 1...maxRetries {
            do {
                let result = try await task()
                failureCount[operation] = 0
                return result
            } catch {
                lastError = error
                failureCount[operation, default: 0] += 1

                if !shouldRetry(error) || attempt == maxRetries {
                    break
                }

                // Exponential backoff
                let delay = Double(attempt) * 0.5
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }

        throw lastError!
    }

    func shouldReloadWebView(after error: Error) -> Bool {
        switch error {
        case NiivueError.webViewInitializationFailed:
            return true
        case NiivueError.javaScriptException:
            return failureCount["jsException", default: 0] >= 3
        default:
            return false
        }
    }
}
```

---

## 8. Memory Management

### 8.1 WKWebView Lifecycle

```swift
@MainActor
public final class NiivueKit: ObservableObject {
    private var webView: WKWebView?
    private var isWebViewPrepared = false

    // Lazy initialization
    private func prepareWebViewIfNeeded() {
        guard !isWebViewPrepared else { return }

        let config = WKWebViewConfiguration()

        // Register custom URL scheme BEFORE creating webView
        let handler = NiivueURLSchemeHandler()
        config.setURLSchemeHandler(handler, forURLScheme: "niivue")

        // Process pool for isolation
        config.processPool = WKProcessPool()

        // Memory limits
        config.preferences.javaScriptCanOpenWindowsAutomatically = false

        webView = WKWebView(frame: .zero, configuration: config)
        isWebViewPrepared = true
    }

    // Cleanup
    public func dispose() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()
        webView?.removeFromSuperview()
        webView = nil
        isWebViewPrepared = false
    }

    deinit {
        // Note: deinit not on MainActor, so we dispatch
        Task { @MainActor [weak self] in
            self?.dispose()
        }
    }
}
```

### 8.2 Large Volume Data Handling

```swift
// Streaming file serving to avoid memory spikes
@MainActor
internal final class NiivueURLSchemeHandler {
    private let chunkSize = 64 * 1024  // 64KB chunks

    private func serveFile(at url: URL, task: WKURLSchemeTask) {
        Task.detached(priority: .userInitiated) {
            do {
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }

                // Send response headers
                await MainActor.run {
                    let response = HTTPURLResponse(
                        url: task.request.url!,
                        statusCode: 200,
                        httpVersion: nil,
                        headerFields: ["Content-Length": "\(fileSize)"]
                    )
                    task.didReceive(response!)
                }

                // Stream chunks
                while !Task.isCancelled {
                    let chunk = try handle.read(upToCount: self.chunkSize) ?? Data()
                    if chunk.isEmpty { break }

                    await MainActor.run {
                        task.didReceive(chunk)
                    }
                }

                await MainActor.run {
                    task.didFinish()
                }
            } catch {
                await MainActor.run {
                    task.didFailWithError(error)
                }
            }
        }
    }
}
```

### 8.3 Memory Pressure Monitoring

```swift
@MainActor
internal final class MemoryPressureMonitor {
    private var memoryWarningObserver: NSObjectProtocol?

    weak var delegate: MemoryPressureDelegate?

    func startMonitoring() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
    }

    func stopMonitoring() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handleMemoryWarning() {
        // Clear caches
        URLCache.shared.removeAllCachedResponses()

        // Notify delegate
        delegate?.memoryPressureDetected()

        // Consider unloading non-visible volumes
        // delegate?.unloadNonEssentialResources()
    }
}

protocol MemoryPressureDelegate: AnyObject {
    func memoryPressureDetected()
}
```

### 8.4 Cleanup on Deinit

```swift
@MainActor
public final class NiivueKit {
    private var cleanupTasks: [() -> Void] = []

    private func registerCleanup(_ task: @escaping () -> Void) {
        cleanupTasks.append(task)
    }

    public func dispose() {
        // Run all cleanup tasks
        for task in cleanupTasks.reversed() {
            task()
        }
        cleanupTasks.removeAll()

        // Remove script message handlers (breaks retain cycle)
        webView?.configuration.userContentController.removeAllScriptMessageHandlers()

        // Stop any pending loads
        webView?.stopLoading()

        // Clear web caches for this instance
        let dataStore = webView?.configuration.websiteDataStore
        Task {
            await dataStore?.removeData(
                ofTypes: [.memoryCache, .diskCache],
                modifiedSince: .distantPast
            ) {}
        }

        webView = nil
    }
}
```

---

## 9. Component Diagrams

### 9.1 Full System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                                    iOS Application                                   │
│  ┌─────────────────────────────────────────────────────────────────────────────┐   │
│  │                              SwiftUI / UIKit Layer                            │   │
│  │   ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────────────┐  │   │
│  │   │   ContentView   │    │  SettingsView   │    │   VolumesListView       │  │   │
│  │   └────────┬────────┘    └────────┬────────┘    └───────────┬─────────────┘  │   │
│  │            │                      │                          │                │   │
│  │            └──────────────────────┼──────────────────────────┘                │   │
│  │                                   │                                           │   │
│  │                                   ▼                                           │   │
│  │   ┌───────────────────────────────────────────────────────────────────────┐  │   │
│  │   │                          NiivueKit                                     │  │   │
│  │   │                    (Public API Facade)                                 │  │   │
│  │   │  @Published isReady, volumes, lastError                                │  │   │
│  │   │  loadVolume(), setColormap(), saveDrawing()                            │  │   │
│  │   └───────────────────────────────┬───────────────────────────────────────┘  │   │
│  │                                   │                                           │   │
│  └───────────────────────────────────┼───────────────────────────────────────────┘   │
│                                      │                                               │
│  ┌───────────────────────────────────┼───────────────────────────────────────────┐   │
│  │                          Bridge Layer                                          │   │
│  │                                   │                                            │   │
│  │   ┌───────────────────────────────┴───────────────────────────────────────┐   │   │
│  │   │                       WebViewManager                                   │   │   │
│  │   │            @MainActor, owns WKWebView instance                         │   │   │
│  │   └─────────┬─────────────────────┬─────────────────────────┬─────────────┘   │   │
│  │             │                     │                         │                  │   │
│  │             ▼                     ▼                         ▼                  │   │
│  │   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────────────┐     │   │
│  │   │ NiivueCommands  │   │ EventDispatcher │   │ JavaScriptEvaluating    │     │   │
│  │   │ (JS Caller)     │   │ (Callback Rx)   │   │ (Protocol)              │     │   │
│  │   └─────────────────┘   └─────────────────┘   └─────────────────────────┘     │   │
│  │                                                                                │   │
│  └────────────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                               │
│  ┌───────────────────────────────────┼───────────────────────────────────────────┐   │
│  │                       WebView Management Layer                                 │   │
│  │                                   │                                            │   │
│  │   ┌───────────────────────────────┴───────────────────────────────────────┐   │   │
│  │   │                        WKWebView                                       │   │   │
│  │   │  - WKWebViewConfiguration (URL scheme registered)                      │   │   │
│  │   │  - WKUserContentController (message handlers)                          │   │   │
│  │   └───────────────────────────────┬───────────────────────────────────────┘   │   │
│  │                                   │                                            │   │
│  │             ┌─────────────────────┴─────────────────────┐                     │   │
│  │             ▼                                           ▼                      │   │
│  │   ┌─────────────────────┐                   ┌─────────────────────────────┐   │   │
│  │   │ NiivueURLRouter     │                   │ NiivueURLSchemeHandler      │   │   │
│  │   │ (Path -> Route)     │                   │ (Route -> Response)         │   │   │
│  │   └─────────────────────┘                   └─────────────────────────────┘   │   │
│  │                                                                                │   │
│  └────────────────────────────────────────────────────────────────────────────────┘   │
│                                      │                                               │
│  ┌───────────────────────────────────┼───────────────────────────────────────────┐   │
│  │                          Resource/Asset Layer                                  │   │
│  │                                   │                                            │   │
│  │       ┌───────────────────────────┴───────────────────────────┐               │   │
│  │       │                                                        │               │   │
│  │       ▼                                                        ▼               │   │
│  │   ┌─────────────────┐   ┌─────────────────┐   ┌─────────────────────────┐     │   │
│  │   │ ImportedFile    │   │ DicomSeries     │   │ Bundle.module           │     │   │
│  │   │ Store (actor)   │   │ Store (actor)   │   │ (dist/, wasm/, samples/)│     │   │
│  │   └─────────────────┘   └─────────────────┘   └─────────────────────────┘     │   │
│  │                                                                                │   │
│  └────────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

### 9.2 Testing Architecture

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                               Test Target                                            │
│                                                                                       │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                            Unit Tests                                        │   │
│   │                                                                              │   │
│   │   ┌─────────────────────┐       ┌─────────────────────────────────────────┐ │   │
│   │   │  NiivueKitTests     │       │  WebViewManagerTests                    │ │   │
│   │   │                     │       │                                         │ │   │
│   │   │  Uses:              │       │  Uses:                                  │ │   │
│   │   │  - MockEvaluator    │       │  - MockEvaluator                        │ │   │
│   │   │  - MockDelegate     │       │  - MockMessageHandler                   │ │   │
│   │   └─────────────────────┘       └─────────────────────────────────────────┘ │   │
│   │                                                                              │   │
│   │   ┌─────────────────────┐       ┌─────────────────────────────────────────┐ │   │
│   │   │  URLRouterTests     │       │  DicomSeriesStoreTests                  │ │   │
│   │   │                     │       │                                         │ │   │
│   │   │  Pure unit tests    │       │  Actor isolation tests                  │ │   │
│   │   │  No mocks needed    │       │  Concurrent access tests                │ │   │
│   │   └─────────────────────┘       └─────────────────────────────────────────┘ │   │
│   │                                                                              │   │
│   └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                       │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                         Integration Tests                                    │   │
│   │                                                                              │   │
│   │   ┌─────────────────────────────────────────────────────────────────────┐   │   │
│   │   │  End-to-End WebView Tests (actual WKWebView)                        │   │   │
│   │   │                                                                      │   │   │
│   │   │  - Tests real JS evaluation                                          │   │   │
│   │   │  - Tests URL scheme handler                                          │   │   │
│   │   │  - Tests message passing                                             │   │   │
│   │   └─────────────────────────────────────────────────────────────────────┘   │   │
│   │                                                                              │   │
│   └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                       │
│   ┌─────────────────────────────────────────────────────────────────────────────┐   │
│   │                              Mocks                                           │   │
│   │                                                                              │   │
│   │   ┌─────────────────────┐       ┌─────────────────────────────────────────┐ │   │
│   │   │ MockJavaScript      │       │ MockResourceProvider                    │ │   │
│   │   │ Evaluator           │       │                                         │ │   │
│   │   │                     │       │ - Returns configured URLs               │ │   │
│   │   │ - Captures scripts  │       │ - No file system access                 │ │   │
│   │   │ - Returns preset    │       └─────────────────────────────────────────┘ │   │
│   │   │   responses         │                                                   │   │
│   │   └─────────────────────┘                                                   │   │
│   │                                                                              │   │
│   └──────────────────────────────────────────────────────────────────────────────┘   │
│                                                                                       │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 10. Data Flow Diagrams

### 10.1 Volume Loading Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                              Volume Loading Sequence                                 │
└─────────────────────────────────────────────────────────────────────────────────────┘

 User            ContentView         NiivueKit         WebViewManager       WKWebView
  │                   │                  │                   │                  │
  │  Pick File        │                  │                   │                  │
  │──────────────────▶│                  │                   │                  │
  │                   │                  │                   │                  │
  │                   │  loadVolume(url) │                   │                  │
  │                   │─────────────────▶│                   │                  │
  │                   │                  │                   │                  │
  │                   │                  │  register(file)   │                  │
  │                   │                  │──────────────────▶│                  │
  │                   │                  │      ◀────────────│                  │
  │                   │                  │      fileId       │                  │
  │                   │                  │                   │                  │
  │                   │                  │  loadImageFromUrl │                  │
  │                   │                  │  (niivue://...)   │                  │
  │                   │                  │──────────────────▶│                  │
  │                   │                  │                   │                  │
  │                   │                  │                   │  evaluateJS      │
  │                   │                  │                   │  window.load...  │
  │                   │                  │                   │─────────────────▶│
  │                   │                  │                   │                  │
  │                   │                  │                   │      ◀───────────│
  │                   │                  │                   │    fetch         │
  │                   │                  │                   │    niivue://...  │
  │                   │                  │                   │                  │
  │                   │                  │                   │  serve file      │
  │                   │                  │                   │  (chunked)       │
  │                   │                  │                   │─────────────────▶│
  │                   │                  │                   │                  │
  │                   │                  │                   │      ◀───────────│
  │                   │                  │                   │  onVolumeLoaded  │
  │                   │                  │                   │  (postMessage)   │
  │                   │                  │                   │                  │
  │                   │                  │      ◀────────────│                  │
  │                   │                  │   handleMessage   │                  │
  │                   │                  │   (VolumeInfo)    │                  │
  │                   │                  │                   │                  │
  │                   │  @Published      │                   │                  │
  │                   │  volumes updated │                   │                  │
  │                   │◀─────────────────│                   │                  │
  │                   │                  │                   │                  │
  │  UI Updates       │                  │                   │                  │
  │◀──────────────────│                  │                   │                  │
  │                   │                  │                   │                  │
```

### 10.2 State Synchronization Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                           State Synchronization Pattern                              │
└─────────────────────────────────────────────────────────────────────────────────────┘

 Swift State              Bridge                   JavaScript State
 (NiivueKit)             (WebViewManager)          (nv.volumes, etc.)
      │                       │                          │
      │                       │                          │
  ┌───┴───┐                   │                      ┌───┴───┐
  │volumes│                   │                      │volumes│
  │opacity│                   │                      │opacity│
  │cmap   │                   │                      │cmap   │
  └───┬───┘                   │                      └───┬───┘
      │                       │                          │
      │                       │                          │
      │  User: setOpacity(0.5)│                          │
      │──────────────────────▶│                          │
      │                       │                          │
      │  1. Optimistic Update │                          │
      │  volumes[i].opacity=.5│                          │
      │◀──────────────────────│                          │
      │                       │                          │
      │                       │  2. Send Command         │
      │                       │  window.setOpacity(i,.5) │
      │                       │─────────────────────────▶│
      │                       │                          │
      │                       │                          │  3. Apply
      │                       │                          │  nv.volumes[i]
      │                       │                          │  .opacity=.5
      │                       │                          │
      │                       │      ◀───────────────────│
      │                       │  4. Callback (optional)  │
      │                       │  onIntensityChange       │
      │                       │                          │
      │  5. Confirm/Rollback  │                          │
      │◀──────────────────────│                          │
      │                       │                          │
      │                       │                          │
  ════╪═══════════════════════╪══════════════════════════╪════
      │                       │                          │
      │  Error Case:          │                          │
      │  JS returns error     │                          │
      │                       │      ◀───────────────────│
      │                       │  Error: "Volume not found"│
      │                       │                          │
      │  6. Rollback          │                          │
      │  volumes[i].opacity=  │                          │
      │    previousValue      │                          │
      │◀──────────────────────│                          │
      │                       │                          │
      │  7. Report Error      │                          │
      │  lastError = ...      │                          │
      │◀──────────────────────│                          │
      │                       │                          │
```

### 10.3 DICOM Import Flow

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│                               DICOM Import Sequence                                  │
└─────────────────────────────────────────────────────────────────────────────────────┘

 User           FilePicker      NiivueKit      DicomStore        URLHandler      Niivue
  │                 │               │               │                 │             │
  │  Select Files   │               │               │                 │             │
  │────────────────▶│               │               │                 │             │
  │                 │               │               │                 │             │
  │                 │  [url1, url2] │               │                 │             │
  │                 │──────────────▶│               │                 │             │
  │                 │               │               │                 │             │
  │                 │               │  register(    │                 │             │
  │                 │               │    files)     │                 │             │
  │                 │               │──────────────▶│                 │             │
  │                 │               │               │                 │             │
  │                 │               │      ◀────────│                 │             │
  │                 │               │   seriesId    │                 │             │
  │                 │               │               │                 │             │
  │                 │               │  manifestURL = niivue://app/dicom/{id}/manifest.txt
  │                 │               │               │                 │             │
  │                 │               │  loadDicom(   │                 │             │
  │                 │               │   manifestURL)│                 │             │
  │                 │               │──────────────────────────────────────────────▶│
  │                 │               │               │                 │             │
  │                 │               │               │                 │      ◀──────│
  │                 │               │               │                 │  fetch      │
  │                 │               │               │                 │  manifest   │
  │                 │               │               │                 │             │
  │                 │               │               │    ◀────────────│             │
  │                 │               │               │  manifestText() │             │
  │                 │               │               │                 │             │
  │                 │               │               │────────────────▶│             │
  │                 │               │               │  "file1.dcm\n   │             │
  │                 │               │               │   file2.dcm"    │             │
  │                 │               │               │                 │────────────▶│
  │                 │               │               │                 │             │
  │                 │               │               │                 │      ◀──────│
  │                 │               │               │                 │  fetch each │
  │                 │               │               │                 │  .dcm file  │
  │                 │               │               │                 │             │
  │                 │               │               │    ◀────────────│             │
  │                 │               │               │  url(for: file) │             │
  │                 │               │               │────────────────▶│             │
  │                 │               │               │   local URL     │────────────▶│
  │                 │               │               │                 │             │
  │                 │               │               │                 │             │
  │                 │               │               │                 │      dcm2niix
  │                 │               │               │                 │      (WASM)
  │                 │               │               │                 │             │
  │                 │               │      ◀──────────────────────────────────────────
  │                 │               │  onVolumeLoaded                 │             │
  │                 │               │  (NIfTI result)                 │             │
  │                 │               │               │                 │             │
  │  @Published     │               │               │                 │             │
  │  volumes updated│               │               │                 │             │
  │◀────────────────────────────────│               │                 │             │
  │                 │               │               │                 │             │
```

---

## 11. Implementation Recommendations

### 11.1 Phased Rollout

#### Phase 1: SDK Restructuring (2-3 days)
1. Create `NiivueKit` facade class
2. Move `WebViewManager` internals behind protocols
3. Add `NiivueConfiguration` for dependency injection
4. Create `NiivueView` SwiftUI wrapper

#### Phase 2: State Management (2-3 days)
1. Implement `VolumeStateActor` for volume tracking
2. Add optimistic update + rollback pattern
3. Wire up all JS callbacks to `EventDispatcher`
4. Implement conflict resolution

#### Phase 3: Error Handling (1-2 days)
1. Create `NiivueError` enum with all cases
2. Add `TimeoutWrapper` for async operations
3. Implement `RecoveryManager` with retry logic
4. Add error surfacing to `NiivueKitDelegate`

#### Phase 4: SPM Packaging (1-2 days)
1. Create `Package.swift` with resource bundling
2. Implement `ResourceBundle` accessor
3. Add version compatibility checking
4. Create test bundle with mock resources

### 11.2 Key Design Decisions

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| State ownership | JS is source of truth | Avoids synchronization complexity |
| Shadow copies | Metadata only | Memory efficiency |
| Error handling | Typed enum + recovery | User-friendly diagnostics |
| Actor usage | Stores only | WebKit requires MainActor |
| Testing strategy | Protocol injection | Mock WKWebView impossible |
| Resource bundling | SPM `Bundle.module` | Standard Swift package pattern |

### 11.3 Testing Strategy

```swift
// Example test with dependency injection
@MainActor
final class NiivueKitTests: XCTestCase {
    func testLoadVolumeCallsJSBridge() async throws {
        // Arrange
        let mockEvaluator = MockJavaScriptEvaluator()
        mockEvaluator.nextAsyncString = """
            {"id":"vol1","name":"test.nii.gz","nFrame4D":1}
        """

        let config = NiivueConfiguration()
        config.evaluatorFactory = { mockEvaluator }

        let kit = NiivueKit(configuration: config)

        // Act
        try await kit.loadVolume(from: URL(string: "file:///test.nii.gz")!)

        // Assert
        XCTAssertEqual(mockEvaluator.scripts.count, 1)
        XCTAssertTrue(mockEvaluator.scripts[0].contains("loadImageFromUrl"))
    }

    func testSetColormapOptimisticallyUpdatesState() async throws {
        let mockEvaluator = MockJavaScriptEvaluator()
        let kit = NiivueKit(configuration: .init(evaluatorFactory: { mockEvaluator }))

        // Simulate loaded volume
        kit.handleScriptMessage(name: "volumeLoaded", body: """
            {"id":"vol1","name":"test.nii.gz","nFrame4D":1}
        """)

        // Act
        try await kit.setColormap("hot", volumeIndex: 0)

        // Assert - state updated immediately
        XCTAssertEqual(kit.volumes[0].colormap, "hot")
    }
}
```

### 11.4 Migration Path for Existing Code

The current codebase can be incrementally migrated:

1. **Keep `WebViewManager`** - Rename to `NiivueWebViewManager`, make internal
2. **Keep `JavaScriptEvaluating`** - Already well-designed
3. **Keep actors** - `DicomSeriesStore`, `ImportedFileStore` are correct
4. **Extract `NiivueKit`** - Facade over existing managers
5. **Add protocols** - `NiivueEventDelegate`, `ResourceProviding`

No breaking changes to JS bridge required - all changes are Swift-side architecture.

---

## Appendix A: File Structure

```
NiivueKit/
├── Sources/
│   └── NiivueKit/
│       ├── NiivueKit.swift                 # Public facade
│       ├── NiivueView.swift                # SwiftUI wrapper
│       ├── NiivueViewController.swift      # UIKit wrapper
│       ├── NiivueConfiguration.swift       # Configuration + DI
│       ├── NiivueError.swift               # Error types
│       ├── NiivueVersion.swift             # Version info
│       │
│       ├── Protocols/
│       │   ├── JavaScriptEvaluating.swift
│       │   ├── NiivueEventDelegate.swift
│       │   ├── FileStoring.swift
│       │   └── ResourceProviding.swift
│       │
│       ├── Bridge/
│       │   ├── NiivueCommands.swift        # Type-safe JS calls
│       │   ├── EventDispatcher.swift       # Callback handling
│       │   └── JavaScriptQuote.swift       # String escaping
│       │
│       ├── Web/
│       │   ├── NiivueWebViewManager.swift  # WebView lifecycle
│       │   ├── NiivueURLRouter.swift       # URL routing
│       │   ├── NiivueURLSchemeHandler.swift
│       │   └── WKWebView+Extensions.swift
│       │
│       ├── State/
│       │   ├── VolumeStateActor.swift
│       │   ├── RenderStateActor.swift
│       │   └── ConflictResolver.swift
│       │
│       ├── Services/
│       │   ├── ImportedFileStore.swift
│       │   ├── DicomSeriesStore.swift
│       │   ├── SessionStore.swift
│       │   └── FileImportService.swift
│       │
│       ├── Models/
│       │   ├── VolumeInfo.swift
│       │   ├── CrosshairLocation.swift
│       │   ├── SliceType.swift
│       │   └── ClipPlane.swift
│       │
│       └── Resources/
│           ├── dist/
│           ├── wasm/
│           └── samples/
│
└── Tests/
    └── NiivueKitTests/
        ├── Mocks/
        │   ├── MockJavaScriptEvaluator.swift
        │   └── MockResourceProvider.swift
        ├── NiivueKitTests.swift
        ├── WebViewManagerTests.swift
        ├── URLRouterTests.swift
        └── DicomSeriesStoreTests.swift
```

---

## Appendix B: Type Definitions

```swift
// Public types exposed by NiivueKit

public struct VolumeInfo: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public var colormap: String
    public var opacity: Double
    public var calMin: Double?
    public var calMax: Double?
    public var currentFrame: Int
    public let totalFrames: Int
}

public struct CrosshairLocation: Sendable {
    public let mm: SIMD3<Double>
    public let voxel: SIMD3<Int>
    public let values: [VolumeValue]

    public struct VolumeValue: Sendable {
        public let volumeIndex: Int
        public let value: Double
    }
}

public enum SliceType: Int, Sendable {
    case axial = 0
    case coronal = 1
    case sagittal = 2
    case multiplanar = 3
    case render = 4
}

public enum DragMode: Int, Sendable {
    case none = 0
    case contrast = 1
    case measurement = 2
    case pan = 3
    case slicer3D = 4
}

public struct ClipPlane: Sendable {
    public var depth: Double
    public var azimuth: Double
    public var elevation: Double
    public var isEnabled: Bool
}
```

---

**Document End**
