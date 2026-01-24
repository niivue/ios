# NiiVue iOS Swift - Complete Types Catalog

## Overview
This document lists every public type, protocol, and actor in the NiiVue iOS codebase for SDK extraction and API documentation purposes.

---

## Enumerations

### ContentView.swift

#### `SegmentationAssetKind`
```swift
enum SegmentationAssetKind: Equatable {
    case mesh
    case volume
    case unsupported
}
```
**Purpose:** File type classification
**SDK Extractable:** Yes
**Usage:** `SegmentationAssetClassifier.classify(url:)`

#### `SliceTypes`
```swift
enum SliceTypes: Int, CaseIterable, Identifiable {
    case Axial = 0
    case Coronal = 1
    case Sagittal = 2
    case Multiplanar = 3
    case Render = 4
    var id: Self { self }
}
```
**Purpose:** Viewer slice type selection
**SDK Extractable:** No (app-specific)
**Used in:** ContentView settings

#### `LayoutTypes`
```swift
enum LayoutTypes: Int, CaseIterable, Identifiable {
    case Auto = 0
    case Column = 1
    case Grid = 2
    case Row = 3
    var id: Self { self }
}
```
**Purpose:** Multiplanar layout selection
**SDK Extractable:** No (app-specific)
**Used in:** ContentView settings

#### `DragTypes`
```swift
enum DragTypes: Int, CaseIterable, Identifiable {
    case None = 0
    case Contrast = 1
    case Measure = 2
    case Pan = 3
    case Slicer3D = 4
    var id: Self { self }
}
```
**Purpose:** Drag interaction mode
**SDK Extractable:** No (app-specific)
**Used in:** ContentView settings

#### `PenTypes`
```swift
enum PenTypes: Int, CaseIterable, Identifiable {
    case Erase = 0
    case Red = 1
    case Green = 2
    case Blue = 3
    case Yellow = 4
    case Cyan = 5
    case Purple = 6
    var id: Self { self }
}
```
**Purpose:** Drawing pen color/type
**SDK Extractable:** No (app-specific)
**Used in:** Segmentation tools

### Services/SessionSnapshotV1.swift

#### `SessionSnapshotError`
```swift
enum SessionSnapshotError: Error, Equatable {
    case invalidJSON
    case invalidViewerState
}
```
**Purpose:** Session snapshot errors
**SDK Extractable:** Yes
**Thrown by:** `SessionSnapshotV1.make()`, `viewerStateJSONString()`

### Services/SessionStore.swift

#### `SessionStoreError`
```swift
enum SessionStoreError: Error, Equatable {
    case invalidID
}
```
**Purpose:** Session store operation errors
**SDK Extractable:** Yes
**Thrown by:** `SessionStore.sessionFileURL(for:)`

### Services/DrawingExportService.swift

#### `DrawingExportService.ExportError`
```swift
enum ExportError: Error, Equatable {
    case invalidBase64
    case writeFailed(String)
}
```
**Purpose:** Drawing export errors
**SDK Extractable:** Yes
**Thrown by:** `DrawingExportService.writeNiftiGz()`

### Web/NiivueURLRouter.swift

#### `NiivueURLRouter.Route`
```swift
enum Route {
    case dist(path: String)           // Bundle dist/ (Vite output)
    case sample(path: String)         // Bundle samples/
    case importedFile(id: String)     // files/<id> (app sandbox)
    case dicomManifest(seriesId: String)
    case dicomFile(seriesId: String, fileName: String)
}
```
**Purpose:** URL routing for niivue:// scheme
**SDK Extractable:** Yes
**Used by:** `NiivueURLSchemeHandler`

### Web/NiivueURLSchemeHandler.swift

#### `NiivueURLSchemeHandler.HandlerError`
```swift
enum HandlerError: Error {
    case invalidURL
    case routingFailed
    case fileNotFound
    case notImplemented
}
```
**Purpose:** URL scheme handler errors
**SDK Extractable:** Yes
**Usage:** Internal error reporting

---

## Structures

### ContentView.swift

#### `SegmentationAssetClassifier`
```swift
struct SegmentationAssetClassifier {
    private static let meshExtensions: Set<String>
    private static let volumeExtensions: Set<String>
    private static let imageExtensions: Set<String>

    static func classify(url: URL) -> SegmentationAssetKind
}
```
**Purpose:** Classify files by extension
**SDK Extractable:** Yes (refactor to Services)
**Methods:**
- `classify(url:) -> SegmentationAssetKind` - Classify a file URL

#### `SegmentationAssetImportPlan`
```swift
struct SegmentationAssetImportPlan {
    let volumeSpecs: [(url: String, name: String)]
    let meshSpecs: [(url: String, name: String)]
    let unsupportedFileNames: [String]
}
```
**Purpose:** Structured import specification
**SDK Extractable:** Yes (refactor to Services)
**Used by:** `SegmentationAssetImportPlanner`, `SegmentationAssetImportExecutor`

#### `SegmentationAssetImportPlanner`
```swift
struct SegmentationAssetImportPlanner {
    static func plan(importedFiles: [FileImportService.ImportedFile])
        -> SegmentationAssetImportPlan
}
```
**Purpose:** Plan multi-file import
**SDK Extractable:** Yes (refactor to Services)
**Methods:**
- `plan(importedFiles:) -> SegmentationAssetImportPlan` - Create import plan

#### `SegmentationAssetImportExecutor`
```swift
struct SegmentationAssetImportExecutor {
    static func execute(plan: SegmentationAssetImportPlan,
                       webViewManager: WebViewManager) async throws
}
```
**Purpose:** Execute import plan
**SDK Extractable:** Yes (refactor to Services)
**Methods:**
- `execute(plan:webViewManager:) async throws` - Execute plan

#### `AccessibilityMarkerView`
```swift
struct AccessibilityMarkerView: UIViewRepresentable {
    let identifier: String

    func makeUIView(context: Context) -> UIView
    func updateUIView(_ uiView: UIView, context: Context)
}
```
**Purpose:** Test accessibility marker
**SDK Extractable:** No (test-specific)

#### `DocumentPicker`
```swift
struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var presented: Bool
    var onPick: (URL) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context)
    func makeCoordinator() -> Coordinator

    class Coordinator: NSObject, UIDocumentPickerDelegate
}
```
**Purpose:** Single file picker bridge
**SDK Extractable:** No (but can be refactored to SDK)
**Methods:**
- `makeUIViewController()` - Create picker
- `updateUIViewController()` - Update picker
- `makeCoordinator()` - Create coordinator

#### `DocumentPickerMultiple`
```swift
struct DocumentPickerMultiple: UIViewControllerRepresentable {
    @Binding var presented: Bool
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context)
    func makeCoordinator() -> Coordinator
    static func makePicker(delegate: UIDocumentPickerDelegate) -> UIDocumentPickerViewController

    class Coordinator: NSObject, UIDocumentPickerDelegate
}
```
**Purpose:** Multi-file picker bridge
**SDK Extractable:** No (but can be refactored to SDK)
**Methods:**
- `makeUIViewController()` - Create picker
- `updateUIViewController()` - Update picker
- `makeCoordinator()` - Create coordinator
- `makePicker(delegate:)` - Factory method

#### `WebView`
```swift
struct WebView: UIViewRepresentable {
    @ObservedObject var manager: WebViewManager

    func makeUIView(context: Context) -> WKWebView
    func updateUIView(_ uiView: WKWebView, context: Context)
}
```
**Purpose:** SwiftUI WKWebView bridge
**SDK Extractable:** Yes
**Methods:**
- `makeUIView()` - Create web view
- `updateUIView()` - Update web view

### Services/Base64FileEncoder.swift

#### `Base64FileEncoder`
```swift
enum Base64FileEncoder {
    static func encodeFileToBase64(url: URL, maxBytes: Int) -> String?
}
```
**Purpose:** File-to-base64 encoding with size limit
**SDK Extractable:** Yes
**Methods:**
- `encodeFileToBase64(url:maxBytes:) -> String?` - Encode file to base64

**Example:**
```swift
let base64 = Base64FileEncoder.encodeFileToBase64(url: fileURL, maxBytes: 25 * 1024 * 1024)
```

### Services/FileImportService.swift

#### `FileImportService`
```swift
struct FileImportService {
    struct ImportedFile: Sendable {
        let id: String
        let originalFileName: String
        let localURL: URL
    }

    func importDocument(at tempURL: URL,
                       destinationDirectory: URL) async throws -> ImportedFile

    static func defaultLibraryDirectory() -> URL
    static func ensureLibraryDirectoryExists() throws
}
```
**Purpose:** Document import from picker
**SDK Extractable:** Yes
**Methods:**
- `importDocument(at:destinationDirectory:) async throws` - Import document
- `defaultLibraryDirectory()` - Get default library path
- `ensureLibraryDirectoryExists()` - Create library directory

**Example:**
```swift
let service = FileImportService()
let imported = try await service.importDocument(at: pickedURL,
                                                destinationDirectory: libraryDir)
print(imported.id)        // UUID
print(imported.localURL)  // App sandbox URL
```

### Services/SessionSnapshotV1.swift

#### `SessionSnapshotV1` (Codable)
```swift
struct SessionSnapshotV1: Codable, Equatable {
    struct VolumeSource: Codable, Equatable {
        let url: String
        let name: String
    }

    struct ViewerStateVolume: Codable, Equatable {
        var colormap: String?
        var opacity: Double?
        var frame4D: Int?
    }

    struct ViewerStateSnapshot: Codable, Equatable {
        var volumes: [ViewerStateVolume]
    }

    let version: Int
    let volumeSources: [VolumeSource]
    let viewerState: ViewerStateSnapshot

    static func make(volumeSources: [VolumeSource],
                     viewerStateJSON: String) throws -> SessionSnapshotV1

    func viewerStateJSONString() throws -> String
}
```
**Purpose:** Session persistence model
**SDK Extractable:** Yes
**Methods:**
- `make(volumeSources:viewerStateJSON:) throws` - Create snapshot
- `viewerStateJSONString() throws` - Export viewer state

**Example:**
```swift
let snapshot = SessionSnapshotV1(
    version: 1,
    volumeSources: [...],
    viewerState: SessionSnapshotV1.ViewerStateSnapshot(volumes: [...])
)
let json = try JSONEncoder().encode(snapshot)
```

### Web/NiivueURLRouter.swift

#### `NiivueURLRouter`
```swift
struct NiivueURLRouter {
    enum Route { ... }

    func route(_ url: URL) -> Route?
}
```
**Purpose:** Parse niivue:// URLs
**SDK Extractable:** Yes
**Methods:**
- `route(_:) -> Route?` - Route a URL

**Example:**
```swift
let router = NiivueURLRouter()
if let route = router.route(url) {
    switch route {
    case .dist(let path):
        print("Serve dist/\(path)")
    case .importedFile(let id):
        print("Serve imported file: \(id)")
    // ...
    }
}
```

---

## Classes

### ContentView.swift (nested)

#### `DocumentPicker.Coordinator`
```swift
class Coordinator: NSObject, UIDocumentPickerDelegate {
    var parent: DocumentPicker

    init(_ documentPicker: DocumentPicker)
    func documentPicker(_ controller: UIDocumentPickerViewController,
                      didPickDocumentsAt urls: [URL])
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController)
    private func isValidFileType(url: URL) -> Bool
}
```
**Purpose:** Coordinator for DocumentPicker
**SDK Extractable:** No

#### `DocumentPickerMultiple.Coordinator`
```swift
class Coordinator: NSObject, UIDocumentPickerDelegate {
    var parent: DocumentPickerMultiple

    init(_ documentPicker: DocumentPickerMultiple)
    func documentPicker(_ controller: UIDocumentPickerViewController,
                      didPickDocumentsAt urls: [URL])
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController)
}
```
**Purpose:** Coordinator for DocumentPickerMultiple
**SDK Extractable:** No

### Web/NiivueURLSchemeHandler.swift

#### `NiivueURLSchemeHandler`
```swift
@MainActor
final class NiivueURLSchemeHandler: NSObject, WKURLSchemeHandler {
    private let router = NiivueURLRouter()
    var importedFileStore: ImportedFileStore?
    var dicomSeriesStore: DicomSeriesStore?

    private struct ActiveWork {
        let token: UUID
        let task: Task<Void, Never>
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask)
    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask)

    // Private methods for serving files
    private func serveDistFile(path: String, task: WKURLSchemeTask)
    private func serveSampleFile(path: String, task: WKURLSchemeTask)
    private func serveImportedFile(id: String, task: WKURLSchemeTask)
    private func serveFile(at url: URL, task: WKURLSchemeTask)
    private func serveDicomManifest(seriesId: String, task: WKURLSchemeTask)
    private func serveDicomFile(seriesId: String, fileName: String, task: WKURLSchemeTask)
    private func mimeTypeForPath(_ path: String) -> String
}
```
**Purpose:** Handle niivue:// URL scheme requests
**SDK Extractable:** Yes
**Inheritance:** `NSObject, WKURLSchemeHandler`
**@MainActor:** Required by WKURLSchemeHandler protocol

### Web/WebViewManager.swift

#### `WebViewManager`
```swift
@MainActor
final class WebViewManager: NSObject, ObservableObject {
    // MARK: Published Properties
    @Published var isReady: Bool = false
    @Published var lastErrorMessage: String?
    @Published var volumes: [VolumeInfo] = []
    @Published var volumeSources: [SessionSnapshotV1.VolumeSource] = []
    @Published var lastLocationString: String?

    // MARK: Nested Types
    struct VolumeInfo: Codable, Equatable {
        let id: String
        let name: String
        let nFrame4D: Int
    }

    @MainActor
    private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler

    // MARK: Initialization
    init(evaluator: JavaScriptEvaluating? = nil,
         initializationTimeoutNanoseconds: UInt64 = 30_000_000_000)

    // MARK: Loading
    func load()
    func reload()

    // MARK: Volume Loading
    func loadBase64Image(base64: String, fileName: String) async throws
    func loadImageFromUrl(url: String, fileName: String) async throws
    func loadVolumesFromUrls(_ volumeSpecs: [(url: String, name: String)]) async throws
    func addVolumesFromUrls(_ volumeSpecs: [(url: String, name: String)]) async throws
    func loadMeshesFromUrls(_ meshSpecs: [(url: String, name: String)]) async throws

    // MARK: Session Management
    func exportViewerStateJSON() async throws -> String
    func exportSessionSnapshotJSON() async throws -> String
    func applyViewerStateJSON(_ json: String) async throws
    func restoreSessionJSON(_ json: String) async throws

    // MARK: Volume Controls
    func setColormap(volumeIndex: Int, colormap: String) async throws
    func setOpacity(volumeIndex: Int, opacity: Double) async throws
    func listColormaps() async throws -> [String]
    func setFrame4D(volumeIndex: Int, frame: Int) async throws

    // MARK: Segmentation/Drawing
    func drawUndo() async throws
    func setDrawOpacity(opacity: Double) async throws
    func setDrawColormap(colormap: String) async throws
    func setClickToSegmentEnabled(enabled: Bool) async throws

    // MARK: DICOM
    func loadDicomSeriesFromManifestURL(_ manifestUrl: String) async throws

    // MARK: View Controls
    func setSliceType(sliceType: Int) async throws
    func setLayout(layout: Int) async throws
    func set3dCrosshairVisible(visible: Bool) async throws
    func set2dCrosshairVisible(visible: Bool) async throws
    func setDragMode(dragMode: Int) async throws

    // MARK: Drawing Controls
    func setPenValue(penValue: Int, isFilled: Bool, drawingEnabled: Bool) async throws
    func setCrosshairColor() async throws
    func setCornerText(isCorners: Bool) async throws
    func setOrientationCube(isOrientationCube: Bool) async throws
    func setRadiological(isRadiological: Bool) async throws
    func moveCrosshairInVox(_ x: Int, _ y: Int, _ z: Int) async throws

    // MARK: Drawing Export
    func saveDrawing() async throws -> String?

    // MARK: Message Handling
    func handleScriptMessage(name: String, body: Any)
}
```
**Purpose:** Orchestrate WebView and Niivue JS app
**SDK Extractable:** Yes (refactor to separate concerns)
**Inheritance:** `NSObject, ObservableObject`
**@MainActor:** Required by WKWebView and ObservableObject

---

## Actors

### Services/ImportedFileStore.swift

#### `ImportedFileStore` (Actor)
```swift
actor ImportedFileStore {
    private let libraryDirectory: URL
    private var map: [String: URL]

    init(libraryDirectory: URL = ImportedFileStore.defaultLibraryDirectory())

    static func defaultLibraryDirectory() -> URL
    private static func loadMap(libraryDirectory: URL) -> [String: URL]

    func register(importedFile: FileImportService.ImportedFile)
    func url(for id: String) -> URL?
    func allIDs() -> [String]
}
```
**Purpose:** Thread-safe file ID → URL registry
**SDK Extractable:** Yes
**Methods:**
- `register(importedFile:)` - Register imported file
- `url(for:) -> URL?` - Lookup file by ID
- `allIDs() -> [String]` - List all registered IDs

**Example:**
```swift
let store = ImportedFileStore()
await store.register(importedFile: imported)
let url = await store.url(for: imported.id)
```

### Services/DicomSeriesStore.swift

#### `DicomSeriesStore` (Actor)
```swift
actor DicomSeriesStore {
    private var series: [String: [String: URL]] = [:]

    func register(files: [URL]) -> String
    func manifestText(for seriesId: String) -> String
    func url(for seriesId: String, fileName: String) -> URL?
    func contains(seriesId: String) -> Bool
    func remove(seriesId: String)
}
```
**Purpose:** Thread-safe DICOM series management
**SDK Extractable:** Yes
**Methods:**
- `register(files:) -> String` - Register series, returns ID
- `manifestText(for:) -> String` - Generate manifest file
- `url(for:fileName:) -> URL?` - Get file URL
- `contains(seriesId:) -> Bool` - Check if series exists
- `remove(seriesId:)` - Remove series

**Example:**
```swift
let store = DicomSeriesStore()
let seriesId = await store.register(files: [file1, file2, ...])
let manifest = await store.manifestText(for: seriesId)
let fileURL = await store.url(for: seriesId, fileName: "001.dcm")
```

### Services/SessionStore.swift

#### `SessionStore` (Actor)
```swift
actor SessionStore {
    private let sessionsDirectory: URL

    init(sessionsDirectory: URL = SessionStore.defaultSessionsDirectory())

    private func sessionFileURL(for id: String) throws -> URL
    static func defaultSessionsDirectory() -> URL

    func save(json: String) throws -> String
    func load(id: String) throws -> String
    func list() throws -> [String]
    func delete(id: String) throws
}
```
**Purpose:** Thread-safe session persistence
**SDK Extractable:** Yes
**Methods:**
- `save(json:) throws -> String` - Save session, returns ID
- `load(id:) throws -> String` - Load session JSON
- `list() throws -> [String]` - List all session IDs
- `delete(id:) throws` - Delete session

**Example:**
```swift
let store = SessionStore()
let sessionId = try await store.save(json: jsonString)
let loaded = try await store.load(id: sessionId)
let ids = try await store.list()
try await store.delete(id: sessionId)
```

---

## Protocols

### Web/JavaScriptEvaluating.swift

#### `JavaScriptEvaluating` (Protocol)
```swift
@MainActor
protocol JavaScriptEvaluating: AnyObject {
    func evaluateCommand(_ javaScript: String) async throws
    func evaluateString(_ javaScript: String) async throws -> String?
    func callAsyncString(_ functionBody: String) async throws -> String?
}
```
**Purpose:** Abstraction for async JavaScript evaluation
**SDK Extractable:** Yes
**@MainActor:** Required (WKWebView is main-thread-only)
**Conformers:**
- `WKWebView` (production)
- `MockJavaScriptEvaluator` (testing)

**Methods:**
- `evaluateCommand(_:) async throws` - Execute JS for side effects
- `evaluateString(_:) async throws -> String?` - Execute JS, return string
- `callAsyncString(_:) async throws -> String?` - Call async JS function

**Example:**
```swift
try await evaluator.evaluateCommand("window.doSomething()")
let result = try await evaluator.evaluateString("1 + 1")
let async = try await evaluator.callAsyncString("return await fetch(...)")
```

---

## Type Hierarchy

```
Root Classes:
├── NSObject
│   ├── WebViewManager [@MainActor]
│   ├── NiivueURLSchemeHandler [@MainActor]
│   ├── WKScriptMessageHandler (via WeakScriptMessageHandler)
│   └── UIDocumentPickerDelegate (via Coordinators)
│
├── App (via @main NiiVueApp)
│   └── SwiftUI View
│
└── ObservableObject (via WebViewManager)

Actors:
├── ImportedFileStore
├── DicomSeriesStore
└── SessionStore

Protocols:
├── JavaScriptEvaluating [@MainActor]
├── WKURLSchemeHandler (via NiivueURLSchemeHandler)
├── UIViewRepresentable (via various)
├── UIViewControllerRepresentable (via DocumentPicker*)
├── Identifiable (via SliceTypes, LayoutTypes, etc.)
├── CaseIterable (via SliceTypes, LayoutTypes, etc.)
├── Codable (via SessionSnapshotV1, VolumeInfo, etc.)
└── Equatable (via many structs/enums)

Enums:
├── SegmentationAssetKind
├── SliceTypes
├── LayoutTypes
├── DragTypes
├── PenTypes
├── SessionSnapshotError
├── SessionStoreError
├── DrawingExportService.ExportError
├── NiivueURLRouter.Route
└── NiivueURLSchemeHandler.HandlerError

Structs:
├── SegmentationAssetClassifier
├── SegmentationAssetImportPlan
├── SegmentationAssetImportPlanner
├── SegmentationAssetImportExecutor
├── AccessibilityMarkerView
├── DocumentPicker
├── DocumentPickerMultiple
├── WebView
├── Base64FileEncoder
├── FileImportService
├── SessionSnapshotV1 (with nested types)
└── NiivueURLRouter
```

---

## Type Dependencies

```
Import Chain for SDK:
1. Base64FileEncoder (no deps)
2. FileImportService → (1)
3. ImportedFileStore (actor)
4. DicomSeriesStore (actor)
5. DrawingExportService (error type)
6. SessionSnapshotV1 (error type)
7. SessionStore (actor)
8. JavaScriptEvaluating (protocol)
9. JavaScriptQuote → (8)
10. WKWebView extension → (8)
11. NiivueURLRouter → (routing enum)
12. NiivueURLSchemeHandler → (3, 4, 11)
13. WebViewManager → (8, 9, 6, 7, 12, 3)

For ContentView Integration:
14. SegmentationAssetClassifier
15. SegmentationAssetImportPlan → (14)
16. SegmentationAssetImportPlanner → (15)
17. SegmentationAssetImportExecutor → (15, 16)
18. DocumentPicker → (app-level)
19. DocumentPickerMultiple → (app-level)
20. WebView → (13)
21. ContentView → (18, 19, 20, 2, 14, 15, 16, 17)
```

---

## Quick SDK Integration Guide

### Minimal (Foundation Layer Only)
```swift
import Foundation

// File import
let fileService = FileImportService()
let imported = try await fileService.importDocument(at: url, destinationDirectory: dir)

// File registry
let fileStore = ImportedFileStore()
await fileStore.register(importedFile: imported)
let fileURL = await fileStore.url(for: imported.id)

// Session persistence
let sessionStore = SessionStore()
let sessionID = try await sessionStore.save(json: jsonString)

// DICOM management
let dicomStore = DicomSeriesStore()
let seriesID = await dicomStore.register(files: [file1, file2])
```

### With JavaScript Bridge
```swift
// URL scheme handler
let handler = NiivueURLSchemeHandler()
handler.importedFileStore = fileStore
handler.dicomSeriesStore = dicomStore

// WebView configuration
let config = WKWebViewConfiguration()
config.setURLSchemeHandler(handler, forURLScheme: "niivue")

// WebView manager
let webView = WKWebView(frame: .zero, configuration: config)
let manager = WebViewManager()

// Load content
try await manager.loadImageFromUrl(url: "niivue://app/files/<id>", fileName: "scan.nii.gz")
```

### Complete App Integration
```swift
// Views
@StateObject private var webViewManager = WebViewManager()
@StateObject private var sessionStore = SessionStore()

// File import
let fileService = FileImportService()
let imported = try await fileService.importDocument(at: url, destinationDirectory: dir)
await webViewManager.importedFileStore.register(importedFile: imported)

// Session save
let snapshot = try await webViewManager.exportSessionSnapshotJSON()
let sessionID = try await sessionStore.save(json: snapshot)

// Session restore
let json = try await sessionStore.load(id: sessionID)
try await webViewManager.restoreSessionJSON(json)
```

