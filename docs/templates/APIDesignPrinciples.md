# API Design Principles

This document outlines the design principles, naming conventions, and architectural decisions behind NiivueKit's Swift API.

---

## Table of Contents

1. [Design Philosophy](#design-philosophy)
2. [Naming Conventions](#naming-conventions)
3. [Threading and Concurrency](#threading-and-concurrency)
4. [Memory Management](#memory-management)
5. [Error Handling](#error-handling)
6. [Type Safety](#type-safety)
7. [Async/Await Patterns](#asyncawait-patterns)
8. [Published State](#published-state)

---

## Design Philosophy

### Core Principles

1. **Swift-Native Feel**: API should feel like native Swift, not a thin wrapper
2. **Type Safety**: Leverage Swift's type system to prevent errors at compile time
3. **Progressive Disclosure**: Simple tasks are simple, complex tasks are possible
4. **Zero-Cost Abstraction**: Wrapper overhead should be minimal
5. **Testability**: All components designed for easy mocking and testing

### Example: Type-Safe vs String-Based APIs

**❌ String-Based (Avoid)**
```swift
// Error-prone: typos, no autocomplete
try await manager.setSliceType("axial")
try await manager.setSliceType("axiall")  // Typo! Runtime error
```

**✅ Type-Safe (Preferred)**
```swift
// Compile-time safety, autocomplete, documentation
try await manager.setSliceType(.axial)
try await manager.setSliceType(.axiall)  // Compiler error ✓
```

---

## Naming Conventions

### General Guidelines

NiivueKit follows [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) with domain-specific adaptations.

#### Clarity at the Point of Use

**Principle**: API should be self-documenting.

```swift
// ❌ Unclear
try await manager.load(url)

// ✅ Clear
try await manager.loadVolumeFromURL(url)
try await manager.loadVolumeFromFile(fileURL)
try await manager.loadVolumeFromBase64(base64String, name: "scan.nii")
```

#### Omit Needless Words

```swift
// ❌ Redundant
try await manager.setVolumeColormap(volumeId: id, colormap: "hot")

// ✅ Concise but clear
try await manager.setColormap(volumeId: id, colormap: "hot")
```

### Method Naming Patterns

#### Loading Methods: `load<What>From<Source>()`

Pattern: `load{ResourceType}From{Source}()`

```swift
func loadVolumeFromURL(_ url: String) async throws
func loadVolumeFromFile(_ fileURL: URL) async throws
func loadVolumeFromBase64(_ base64: String, name: String) async throws
func loadDicomSeriesFromManifestURL(_ manifestUrl: String) async throws
```

**Rationale:**
- Describes both **what** (Volume, DicomSeries) and **how** (URL, File, Base64)
- Consistent with Cocoa conventions (`init(contentsOf:)`)

#### State Setters: `set<Property>()`

Pattern: `set{PropertyName}({parameters})`

```swift
func setSliceType(_ type: SliceType) async throws
func setColormap(volumeId: String, colormap: String) async throws
func setOpacity(volumeId: String, opacity: Double) async throws
func setPenValue(_ value: UInt8, isFilled: Bool) async throws
```

**Rationale:**
- Clear mutation intent
- Distinguishes from property setters
- Async operations require method syntax

#### Actions: Verb Phrases

```swift
func saveDrawing() async throws -> Data
func drawUndo() async throws
func setCrosshairPosition(voxel: SIMD3<Int>) async throws
```

### Parameter Naming

#### External vs Internal Names

```swift
// Use external names for clarity
func loadVolumeFromURL(_ url: String) async throws
//                      ^ Omit label for obvious parameter

func setColormap(volumeId: String, colormap: String) async throws
//               ^^^^^^^^          ^^^^^^^^ Both labeled for clarity

func setPenValue(_ value: UInt8, isFilled: Bool) async throws
//               ^ Unlabeled    ^^^^^^^^ Labeled for boolean clarity
```

#### Boolean Parameters

Always label boolean parameters to avoid confusion:

```swift
// ❌ Ambiguous
try await manager.setPenValue(1, false)  // What does false mean?

// ✅ Clear
try await manager.setPenValue(1, isFilled: false)
```

### Type Naming

#### Structs: Nouns

```swift
struct VolumeInfo: Codable, Equatable {
    let id: String
    let name: String
    let nFrame4D: Int
}

struct SessionSnapshotV1: Codable {
    let volumeSources: [VolumeSource]
    let sliceType: SliceType
    let multiplanarLayout: MultiplanarLayout
}
```

#### Enums: Singular Nouns

```swift
enum SliceType: Int {
    case axial = 0
    case coronal = 1
    case sagittal = 2
    case multiplanar = 3
    case render = 4
}

enum MultiplanarLayout: Int {
    case auto = 0
    case column = 1
    case grid = 2
    case row = 3
}
```

#### Actors: Nouns Ending in "Store" or "Manager"

```swift
actor DicomSeriesStore {
    func register(files: [URL]) -> String
}

actor SessionStore {
    func save(snapshot: SessionSnapshotV1) async throws
}

@MainActor
final class WebViewManager: ObservableObject {
    @Published var volumes: [VolumeInfo]
}
```

---

## Threading and Concurrency

### Actor Isolation

NiivueKit uses Swift's actor model for thread safety:

#### Main Actor: UI-Related Types

```swift
@MainActor
final class WebViewManager: ObservableObject {
    @Published var isReady: Bool = false
    @Published var volumes: [VolumeInfo] = []

    // All methods run on main thread
    func setSliceType(_ type: SliceType) async throws {
        // Safe to update @Published properties
        // Safe to call evaluateJavaScript (WKWebView requires main thread)
    }
}
```

**Rationale:**
- `WKWebView` requires main thread access
- `@Published` properties must update on main thread for SwiftUI
- Simplifies UI integration

#### Isolated Actors: Data Stores

```swift
actor DicomSeriesStore {
    private var series: [String: [String: URL]] = [:]

    func register(files: [URL]) -> String {
        // Actor ensures thread-safe access
        let seriesId = UUID().uuidString
        // ... mutation is isolated
        return seriesId
    }
}
```

**Rationale:**
- Prevents data races on shared mutable state
- No manual locking required
- Type-checked by compiler

### Concurrency Guarantees

| Type | Thread Safety | Guarantee |
|------|---------------|-----------|
| `WebViewManager` | Main actor | All methods run on main thread |
| `DicomSeriesStore` | Actor-isolated | Serialized access, no data races |
| `SessionStore` | Actor-isolated | Atomic file operations |
| `VolumeInfo` (struct) | Value type | Copy-on-write, inherently thread-safe |

### Calling Conventions

#### From Main Thread

```swift
@MainActor
func viewDidAppear() async {
    // Already on main thread, WebViewManager calls are synchronous actor hops
    try? await webViewManager.setSliceType(.multiplanar)
}
```

#### From Background Thread

```swift
Task.detached {
    // Background thread
    let seriesId = await dicomStore.register(files: dicomFiles)

    // Switch to main thread for UI update
    await MainActor.run {
        try? await webViewManager.loadDicomSeriesFromManifestURL(
            "niivue://app/dicom/\(seriesId)/niivue-manifest.txt"
        )
    }
}
```

---

## Memory Management

### Ownership Model

#### Weak References in Delegates

**Problem:** WKScriptMessageHandler is strongly retained by WKWebView, creating retain cycles.

**Solution:** Weak proxy pattern.

```swift
@MainActor
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: WebViewManager?  // ✅ Weak reference

    init(owner: WebViewManager) {
        self.owner = owner
        super.init()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.handleScriptMessage(name: message.name, body: message.body)
    }
}
```

**Rationale:**
- Breaks retain cycle: `WKWebView` → `WKWebViewConfiguration` → `WKUserContentController` → `WeakHandler` ⇢ `WebViewManager`
- Manager can be deallocated properly

#### Security-Scoped Resource Cleanup

**Problem:** iOS requires manual start/stop for security-scoped file access.

**Solution:** `defer` for guaranteed cleanup.

```swift
func loadFile(_ url: URL) async throws {
    let accessing = url.startAccessingSecurityScopedResource()
    defer {
        if accessing {
            url.stopAccessingSecurityScopedResource()  // ✅ Always called
        }
    }

    // File operations...
    // Even if error thrown, defer ensures cleanup
}
```

### Memory Expectations

#### Client Responsibilities

1. **WebViewManager lifecycle**: Client must retain `WebViewManager` while in use
2. **Security-scoped access**: Handled automatically by NiivueKit's file import methods
3. **Large file management**: Client should monitor memory pressure and unload volumes

#### NiivueKit Guarantees

1. **No retain cycles**: All internal references properly managed
2. **Automatic cleanup**: Resources released when manager deallocated
3. **File cleanup**: Copied files remain in app container (client can clear via `FileImportService`)

### Memory Monitoring Example

```swift
@MainActor
class MemoryAwareViewController: UIViewController {
    var webViewManager: WebViewManager!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Monitor memory warnings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didReceiveMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    @objc func didReceiveMemoryWarning() {
        Task {
            // Unload all but base volume
            while webViewManager.volumes.count > 1 {
                try? await webViewManager.removeVolume(at: 1)
            }
        }
    }
}
```

---

## Error Handling

### Error Types

NiivueKit uses Swift's typed error system:

```swift
enum NiivueError: LocalizedError {
    case notReady
    case volumeNotFound(id: String)
    case invalidBase64
    case javascriptEvaluationFailed(underlying: Error)
    case fileAccessDenied(url: URL)

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "WebView is not ready. Wait for isReady = true before calling methods."
        case .volumeNotFound(let id):
            return "Volume with ID '\(id)' not found."
        case .invalidBase64:
            return "Invalid base64 string provided."
        case .javascriptEvaluationFailed(let error):
            return "JavaScript evaluation failed: \(error.localizedDescription)"
        case .fileAccessDenied(let url):
            return "Access denied for file: \(url.lastPathComponent)"
        }
    }
}
```

### Error Propagation

Methods use `async throws` for error propagation:

```swift
func loadVolumeFromURL(_ url: String) async throws {
    guard isReady else {
        throw NiivueError.notReady
    }

    do {
        try await evaluator.evaluateCommand(
            "window.loadVolumeFromUrl(\(escaped))"
        )
    } catch {
        throw NiivueError.javascriptEvaluationFailed(underlying: error)
    }
}
```

### Error Handling Best Practices

#### Client Code

```swift
// ✅ Good: Handle specific errors
do {
    try await webViewManager.loadVolumeFromURL(url)
} catch NiivueError.notReady {
    // Show "Please wait..." message
} catch NiivueError.javascriptEvaluationFailed(let error) {
    // Show detailed error to developer
    print("JS Error: \(error)")
} catch {
    // Generic fallback
    showAlert("Failed to load volume")
}
```

```swift
// ❌ Avoid: Silent failures
try? await webViewManager.loadVolumeFromURL(url)  // Error ignored!
```

---

## Type Safety

### Strongly-Typed Enumerations

Replace stringly-typed APIs with enums:

```swift
// ❌ JavaScript API (strings)
nv.setSliceType(3)  // Magic number
nv.setColormap(id, "hot")  // String, typo-prone

// ✅ Swift API (enums)
try await webViewManager.setSliceType(.multiplanar)  // Type-safe
try await webViewManager.setColormap(volumeId: id, colormap: "hot")  // String validated at runtime
```

### Structured Data Types

```swift
// ❌ Dictionary-based (JavaScript-like)
let volumeDict: [String: Any] = [
    "id": "abc123",
    "name": "T1.nii",
    "nFrame4D": 1
]

// ✅ Structured types
struct VolumeInfo: Codable, Equatable {
    let id: String
    let name: String
    let nFrame4D: Int
}
```

**Benefits:**
- Autocomplete
- Type checking
- Codable conformance (JSON serialization)
- Equatable conformance (testing)

### Phantom Types for IDs

Future consideration for preventing ID mix-ups:

```swift
struct VolumeID: RawRepresentable {
    let rawValue: String
}

struct MeshID: RawRepresentable {
    let rawValue: String
}

// Type-safe APIs
func setColormap(volumeId: VolumeID, colormap: String) async throws
func setMeshOpacity(meshId: MeshID, opacity: Double) async throws

// Compiler prevents mix-ups
try await manager.setColormap(volumeId: meshID, ...)  // ❌ Compiler error
```

---

## Async/Await Patterns

### All Bridge Methods Are Async

**Rationale:** JavaScript execution is inherently asynchronous (runs on WKWebView's background JavaScript thread).

```swift
func setColormap(volumeId: String, colormap: String) async throws {
    let volumeIdEscaped = try JavaScriptQuote.jsonStringLiteral(volumeId)
    let colormapEscaped = try JavaScriptQuote.jsonStringLiteral(colormap)

    // JavaScript evaluation returns asynchronously
    try await evaluator.evaluateCommand(
        "window.setColormap(\(volumeIdEscaped), \(colormapEscaped))"
    )
}
```

### Task Lifecycle Management

#### Short-Lived Tasks

```swift
Button("Load Volume") {
    Task {
        try await webViewManager.loadVolumeFromURL(url)
    }
}
```

#### Long-Lived Tasks with Cancellation

```swift
@State private var loadTask: Task<Void, Never>?

var body: some View {
    VStack { }
        .task {
            loadTask = Task {
                do {
                    try await webViewManager.loadVolumeFromURL(url)
                } catch is CancellationError {
                    print("Load cancelled")
                }
            }
        }
        .onDisappear {
            loadTask?.cancel()
        }
}
```

### Waiting for Ready State

```swift
func waitForReady(timeout: Duration = .seconds(30)) async throws {
    let deadline = ContinuousClock.now + timeout

    while !webViewManager.isReady {
        if ContinuousClock.now > deadline {
            throw NiivueError.initializationTimeout
        }
        try await Task.sleep(for: .milliseconds(100))
    }
}
```

---

## Published State

### Observable Object Protocol

`WebViewManager` conforms to `ObservableObject` for SwiftUI integration:

```swift
@MainActor
final class WebViewManager: ObservableObject {
    @Published var isReady: Bool = false
    @Published var volumes: [VolumeInfo] = []
    @Published var lastLocationString: String?
    @Published var lastErrorMessage: String?
}
```

### State Update Guarantees

1. **Main thread**: All `@Published` updates occur on main thread (enforced by `@MainActor`)
2. **Synchronous**: SwiftUI observes changes synchronously within the same run loop
3. **Deduplicated**: Multiple updates to same property in one cycle are coalesced

### State Update Patterns

#### From JavaScript Callback

```swift
func handleScriptMessage(name: String, body: Any) {
    switch name {
    case "volumeLoaded":
        guard let data = body as? [String: Any],
              let volumes = parseVolumes(data) else { return }

        // Update published state (already on main thread via @MainActor)
        self.volumes = volumes

    case "errorOccurred":
        if let message = body as? String {
            self.lastErrorMessage = message
        }

    default:
        break
    }
}
```

#### From Async Method

```swift
func loadVolumeFromURL(_ url: String) async throws {
    try await evaluator.evaluateCommand("...")

    // After successful load, volumes list will be updated via
    // JavaScript callback to handleScriptMessage
    // No manual state update needed
}
```

---

## API Stability Annotations

### Using `@available`

```swift
// Deprecated API
@available(*, deprecated, message: "Use loadVolume(from:) instead")
func loadVolumeFromURL(_ url: String) async throws {
    try await loadVolume(from: .url(url))
}

// iOS version-specific API
@available(iOS 16.0, *)
func loadVolumeWithTransferable(_ transferable: Transferable) async throws {
    // Use iOS 16+ Transferable API
}
```

### Experimental APIs

Mark experimental features explicitly:

```swift
/// - Warning: This API is experimental and may change in future versions.
func experimentalFeature() async throws {
    // ...
}
```

---

## Documentation Standards

### DocC-Compatible Comments

All public APIs include:

1. **Summary**: One-line description
2. **Discussion**: Detailed explanation (if needed)
3. **Parameters**: Description of each parameter
4. **Returns**: What the method returns
5. **Throws**: What errors can be thrown
6. **Example**: Code example for complex APIs

```swift
/// Loads a NIfTI volume from a remote URL.
///
/// The volume is fetched asynchronously and rendered in the current view mode.
/// Use ``setSliceType(_:)`` to change the view mode before or after loading.
///
/// - Parameter url: The URL of the NIfTI file (.nii or .nii.gz)
/// - Throws: ``NiivueError/notReady`` if WebView is not initialized
/// - Throws: ``NiivueError/javascriptEvaluationFailed(underlying:)`` if loading fails
///
/// Example:
/// ```swift
/// try await webViewManager.loadVolumeFromURL(
///     "https://example.com/brain.nii.gz"
/// )
/// ```
func loadVolumeFromURL(_ url: String) async throws {
    // Implementation
}
```

---

## Design Decision Rationale

### Why Async/Await Instead of Closures?

```swift
// ❌ Old (callback-based)
func loadVolume(url: String, completion: @escaping (Result<Void, Error>) -> Void) {
    // Callback hell, manual error handling
}

// ✅ Modern (async/await)
func loadVolume(url: String) async throws {
    // Linear code flow, automatic error propagation
}
```

**Benefits:**
- Linear code flow (no callback nesting)
- Automatic error propagation (no manual Result handling)
- Structured concurrency (automatic cancellation)
- Better debugging (call stack preserved)

### Why Actor Isolation?

**Alternative:** Manual locking with `NSLock` or `DispatchQueue`.

```swift
// ❌ Manual locking (error-prone)
class Store {
    private let lock = NSLock()
    private var data: [String: URL] = [:]

    func register(files: [URL]) -> String {
        lock.lock()
        defer { lock.unlock() }
        // Easy to forget lock/unlock, deadlock risk
    }
}

// ✅ Actor (compiler-enforced)
actor Store {
    private var data: [String: URL] = [:]

    func register(files: [URL]) -> String {
        // Compiler ensures serialized access
    }
}
```

**Benefits:**
- Compiler-enforced thread safety
- No manual locking (prevents deadlocks)
- Auditable in code review (actor keyword signals isolation)

### Why @MainActor for WebViewManager?

**Alternative:** Background actor with manual main thread dispatching.

```swift
// ❌ Manual dispatching (verbose)
actor WebViewManager {
    func setSliceType(_ type: SliceType) async throws {
        await MainActor.run {
            // Call WKWebView
        }
        // Update @Published properties
        await MainActor.run {
            // ...
        }
    }
}

// ✅ @MainActor (automatic)
@MainActor
final class WebViewManager {
    func setSliceType(_ type: SliceType) async throws {
        // Already on main thread
        // WKWebView calls are safe
        // @Published updates are safe
    }
}
```

**Benefits:**
- Simpler code (no manual dispatching)
- Matches WKWebView's threading requirements
- Natural SwiftUI integration (@Published + @MainActor)

---

**Last Updated:** January 4, 2026
**NiivueKit Version:** 1.0.0
