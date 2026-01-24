# NiivueKit Universal Swift SDK Architecture

**Version:** 1.0.0
**Date:** January 4, 2026
**Author:** Claude Code (Opus 4.5)
**Status:** Design Document

---

## Executive Summary

This document defines the architecture for **NiivueKit**, a Universal Swift SDK that enables iOS/iPadOS/visionOS/macCatalyst developers to integrate neuroimaging visualization into their applications. The SDK encapsulates the complexity of WKWebView, JavaScript bridging, and WebGL rendering behind a clean, type-safe Swift API.

### Design Goals

1. **Zero JavaScript Knowledge Required** - Developers interact only with Swift types
2. **SwiftUI-First** - Native integration with modern declarative UI
3. **Protocol-Oriented** - Extensible via protocols for custom behaviors
4. **Async/Await Native** - Modern concurrency throughout
5. **Minimal Dependencies** - Self-contained with bundled JS/WASM

---

## Table of Contents

1. [Module Structure](#1-module-structure)
2. [Public API Surface](#2-public-api-surface)
3. [Integration Patterns](#3-integration-patterns)
4. [WebView Encapsulation](#4-webview-encapsulation)
5. [Dependency Strategy](#5-dependency-strategy)
6. [Error Handling](#6-error-handling)
7. [Type Definitions](#7-type-definitions)
8. [Code Examples](#8-code-examples)
9. [Migration Guide](#9-migration-guide)

---

## 1. Module Structure

### 1.1 Target Architecture

```
NiivueKit/
├── Sources/
│   └── NiivueKit/
│       ├── Core/                    # Core module (always included)
│       │   ├── NiivueView.swift           # Main SwiftUI view
│       │   ├── NiivueController.swift     # State and action management
│       │   ├── NiivueConfiguration.swift  # Configuration options
│       │   ├── NiivueError.swift          # Error types
│       │   └── Types/
│       │       ├── Volume.swift           # Volume metadata
│       │       ├── Mesh.swift             # Mesh metadata
│       │       ├── SliceType.swift        # View enumerations
│       │       ├── ColorMap.swift         # Colormap types
│       │       └── Coordinates.swift      # Coordinate types
│       │
│       ├── Loading/                 # Volume/mesh loading
│       │   ├── VolumeLoader.swift
│       │   ├── MeshLoader.swift
│       │   ├── DicomLoader.swift
│       │   └── FileImporter.swift
│       │
│       ├── Rendering/               # Rendering controls
│       │   ├── ViewControls.swift         # Slice type, layout
│       │   ├── RenderControls.swift       # 3D rendering options
│       │   └── OverlayControls.swift      # Colormap, opacity
│       │
│       ├── Drawing/                 # Drawing & segmentation
│       │   ├── DrawingController.swift
│       │   ├── SegmentationTools.swift
│       │   └── DrawingExporter.swift
│       │
│       ├── Events/                  # Event system
│       │   ├── NiivueEvents.swift
│       │   ├── LocationEvent.swift
│       │   └── VolumeEvent.swift
│       │
│       ├── Internal/                # Internal (not public)
│       │   ├── Bridge/
│       │   │   ├── JavaScriptBridge.swift
│       │   │   ├── MessageHandler.swift
│       │   │   └── CommandBuilder.swift
│       │   ├── WebView/
│       │   │   ├── NiivueWebView.swift
│       │   │   ├── URLSchemeHandler.swift
│       │   │   └── URLRouter.swift
│       │   └── Resources/
│       │       └── BundleAccessor.swift
│       │
│       └── Resources/               # Bundled assets
│           ├── dist/                # React app build
│           └── samples/             # Demo files
│
├── Tests/
│   └── NiivueKitTests/
│       ├── CoreTests/
│       ├── LoadingTests/
│       ├── RenderingTests/
│       └── Fixtures/
│
└── Package.swift
```

### 1.2 Access Control Strategy

| Access Level | Usage |
|--------------|-------|
| `public` | Types and methods intended for SDK consumers |
| `internal` | Implementation details within NiivueKit module |
| `private` | Type-internal implementation |
| `@_spi(Internal)` | Advanced APIs for plugin authors (opt-in) |

### 1.3 Module Dependencies Graph

```
┌─────────────────────────────────────────────────────────────────┐
│                        Public API Layer                          │
│  ┌──────────────┐  ┌─────────────────┐  ┌──────────────────┐    │
│  │  NiivueView  │  │NiivueController │  │ NiivueDelegate   │    │
│  └──────┬───────┘  └────────┬────────┘  └────────┬─────────┘    │
│         │                   │                     │              │
├─────────┼───────────────────┼─────────────────────┼──────────────┤
│         ▼                   ▼                     ▼              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                   Feature Controllers                      │   │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────────────┐  │   │
│  │  │VolumeLoader│  │DrawingCtrl │  │ RenderingControls  │  │   │
│  │  └─────┬──────┘  └─────┬──────┘  └─────────┬──────────┘  │   │
│  └────────┼───────────────┼───────────────────┼─────────────┘   │
│           │               │                   │                  │
├───────────┼───────────────┼───────────────────┼──────────────────┤
│           ▼               ▼                   ▼                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                    Internal Bridge Layer                    │   │
│  │  ┌────────────────┐  ┌───────────────┐  ┌──────────────┐ │   │
│  │  │JavaScriptBridge│  │MessageHandler │  │URLSchemeHdlr │ │   │
│  │  └───────┬────────┘  └───────┬───────┘  └──────┬───────┘ │   │
│  └──────────┼───────────────────┼─────────────────┼─────────┘   │
│             │                   │                 │              │
├─────────────┼───────────────────┼─────────────────┼──────────────┤
│             ▼                   ▼                 ▼              │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │                  WKWebView + React/Niivue                  │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Public API Surface

### 2.1 Entry Point: NiivueView (SwiftUI)

The primary integration point for SwiftUI applications.

```swift
/// A SwiftUI view that displays an interactive neuroimaging viewer.
///
/// NiivueView provides a complete neuroimaging visualization experience including:
/// - 2D slice views (axial, coronal, sagittal)
/// - Multiplanar reconstruction
/// - 3D volume rendering
/// - Interactive drawing and segmentation
///
/// ## Basic Usage
/// ```swift
/// struct ContentView: View {
///     @StateObject private var controller = NiivueController()
///
///     var body: some View {
///         NiivueView(controller: controller)
///             .onAppear {
///                 Task {
///                     try await controller.loadVolume(from: myVolumeURL)
///                 }
///             }
///     }
/// }
/// ```
@MainActor
public struct NiivueView: View {

    // MARK: - Initialization

    /// Creates a NiivueView with the specified controller.
    /// - Parameter controller: The controller managing viewer state and actions.
    public init(controller: NiivueController)

    /// Creates a NiivueView with a new controller using the specified configuration.
    /// - Parameter configuration: Configuration options for the viewer.
    public init(configuration: NiivueConfiguration = .default)

    // MARK: - View Modifiers

    /// Adds a delegate to receive viewer events.
    public func onEvent(_ handler: @escaping (NiivueEvent) -> Void) -> NiivueView

    /// Sets the initial volumes to load when the view appears.
    public func initialVolumes(_ urls: [URL]) -> NiivueView

    /// Enables or disables the heads-up display (HUD).
    public func showsHUD(_ shows: Bool) -> NiivueView

    /// Sets the background color of the viewer.
    public func backgroundColor(_ color: Color) -> NiivueView
}
```

### 2.2 State Management: NiivueController

The controller manages all viewer state and exposes actions.

```swift
/// Controls a NiivueView instance and provides the primary API for viewer interactions.
///
/// NiivueController is an `ObservableObject` that publishes state changes for SwiftUI binding.
/// All mutating operations are async and should be awaited.
///
/// ## Thread Safety
/// All public methods must be called from the main actor. The controller uses
/// Swift concurrency to ensure thread-safe state updates.
@MainActor
public final class NiivueController: ObservableObject {

    // MARK: - Published State (Read-Only)

    /// Whether the viewer has finished loading and is ready for commands.
    @Published public private(set) var isReady: Bool

    /// Currently loaded volumes with their metadata.
    @Published public private(set) var volumes: [Volume]

    /// Currently loaded meshes with their metadata.
    @Published public private(set) var meshes: [Mesh]

    /// Current crosshair location in various coordinate systems.
    @Published public private(set) var crosshairLocation: CrosshairLocation?

    /// Current view configuration (slice type, layout, etc.).
    @Published public private(set) var viewConfiguration: ViewConfiguration

    /// Current error, if any.
    @Published public private(set) var error: NiivueError?

    // MARK: - Configuration

    /// The configuration used to initialize this controller.
    public let configuration: NiivueConfiguration

    // MARK: - Initialization

    /// Creates a controller with the specified configuration.
    public init(configuration: NiivueConfiguration = .default)

    // MARK: - Volume Loading

    /// Loads a volume from a URL, replacing any existing volumes.
    /// - Parameters:
    ///   - url: The URL of the volume file (local or remote).
    ///   - options: Optional loading options.
    /// - Throws: `NiivueError.loadingFailed` if the volume cannot be loaded.
    public func loadVolume(from url: URL, options: VolumeLoadOptions = .default) async throws

    /// Loads multiple volumes, with the first as the background.
    public func loadVolumes(_ urls: [URL], options: VolumeLoadOptions = .default) async throws

    /// Adds a volume as an overlay without clearing existing volumes.
    public func addOverlay(from url: URL, options: OverlayOptions = .default) async throws

    /// Loads a DICOM series from a directory or list of files.
    public func loadDicomSeries(from urls: [URL]) async throws

    /// Removes a volume by its identifier.
    public func removeVolume(_ volume: Volume) async throws

    /// Removes all volumes.
    public func clearVolumes() async throws

    // MARK: - Mesh Loading

    /// Loads a mesh from a URL.
    public func loadMesh(from url: URL, options: MeshLoadOptions = .default) async throws

    /// Removes a mesh by its identifier.
    public func removeMesh(_ mesh: Mesh) async throws

    // MARK: - View Control

    /// Sets the slice type (axial, coronal, sagittal, multiplanar, render).
    public func setSliceType(_ sliceType: SliceType) async throws

    /// Sets the multiplanar layout.
    public func setLayout(_ layout: MultiplanarLayout) async throws

    /// Moves the crosshair to the specified coordinate.
    public func setCrosshair(mm: SIMD3<Double>) async throws
    public func setCrosshair(voxel: SIMD3<Int>) async throws

    // MARK: - 3D Rendering

    /// Sets the 3D view angle.
    public func setRenderAngle(azimuth: Double, elevation: Double) async throws

    /// Sets the clip plane for 3D rendering.
    public func setClipPlane(_ clipPlane: ClipPlane) async throws

    /// Sets the zoom level.
    public func setZoom(_ multiplier: Double) async throws

    // MARK: - Volume Display

    /// Sets the colormap for a volume.
    public func setColormap(_ colormap: ColorMap, for volume: Volume) async throws

    /// Sets the opacity for a volume.
    public func setOpacity(_ opacity: Double, for volume: Volume) async throws

    /// Sets the intensity window (min/max) for a volume.
    public func setIntensityWindow(min: Double, max: Double, for volume: Volume) async throws

    /// Sets the current frame for a 4D volume.
    public func setFrame(_ frame: Int, for volume: Volume) async throws

    // MARK: - Drawing & Segmentation

    /// Returns a controller for drawing operations.
    public var drawing: DrawingController { get }

    // MARK: - Export

    /// Exports the current view as an image.
    public func exportImage() async throws -> UIImage

    /// Exports the current drawing as NIfTI data.
    public func exportDrawing() async throws -> Data

    /// Exports a session snapshot for later restoration.
    public func exportSession() async throws -> SessionSnapshot

    /// Restores a previously exported session.
    public func restoreSession(_ snapshot: SessionSnapshot) async throws
}
```

### 2.3 Configuration

```swift
/// Configuration options for NiivueKit.
public struct NiivueConfiguration: Sendable {

    // MARK: - Presets

    /// Default configuration suitable for most use cases.
    public static let `default`: NiivueConfiguration

    /// Configuration optimized for low-memory devices.
    public static let lowMemory: NiivueConfiguration

    /// Configuration optimized for performance over quality.
    public static let performance: NiivueConfiguration

    // MARK: - Display Options

    /// Background color of the viewer (default: black).
    public var backgroundColor: Color

    /// Crosshair color (default: red).
    public var crosshairColor: Color

    /// Crosshair line width in pixels (default: 1).
    public var crosshairWidth: Double

    /// Whether to show 3D crosshair in render mode (default: false).
    public var show3DCrosshair: Bool

    /// Whether to show colorbar (default: true).
    public var showColorbar: Bool

    /// Whether to show ruler (default: false).
    public var showRuler: Bool

    /// Whether to show orientation labels (default: true).
    public var showOrientationLabels: Bool

    /// Whether to show orientation cube in 3D (default: false).
    public var showOrientationCube: Bool

    // MARK: - Rendering Options

    /// Use radiological convention (left-right flipped) (default: false).
    public var radiologicalConvention: Bool

    /// Use nearest-neighbor interpolation (default: false, uses linear).
    public var nearestInterpolation: Bool

    /// Initial slice type (default: .multiplanar).
    public var initialSliceType: SliceType

    /// Initial multiplanar layout (default: .auto).
    public var initialLayout: MultiplanarLayout

    /// Initial drag mode (default: .contrast).
    public var initialDragMode: DragMode

    // MARK: - Performance Options

    /// Maximum texture size (0 = auto-detect from GPU).
    public var maxTextureSize: Int

    /// Enable gradient-based volume rendering (default: true).
    public var enableGradient: Bool

    // MARK: - Initialization

    public init(
        backgroundColor: Color = .black,
        crosshairColor: Color = .red,
        // ... all parameters with defaults
    )
}
```

### 2.4 Delegate Protocol

```swift
/// Protocol for receiving events from a NiivueController.
@MainActor
public protocol NiivueDelegate: AnyObject {

    /// Called when the viewer becomes ready.
    func niivueDidBecomeReady(_ controller: NiivueController)

    /// Called when a volume is loaded.
    func niivue(_ controller: NiivueController, didLoadVolume volume: Volume)

    /// Called when the crosshair location changes.
    func niivue(_ controller: NiivueController, crosshairDidMoveTo location: CrosshairLocation)

    /// Called when an error occurs.
    func niivue(_ controller: NiivueController, didEncounterError error: NiivueError)

    /// Called when intensity window changes (user drag).
    func niivue(_ controller: NiivueController, intensityDidChange volume: Volume)

    /// Called when 3D rotation changes.
    func niivue(_ controller: NiivueController, rotationDidChange azimuth: Double, elevation: Double)
}

/// Default implementations (all optional).
public extension NiivueDelegate {
    func niivueDidBecomeReady(_ controller: NiivueController) {}
    func niivue(_ controller: NiivueController, didLoadVolume volume: Volume) {}
    func niivue(_ controller: NiivueController, crosshairDidMoveTo location: CrosshairLocation) {}
    func niivue(_ controller: NiivueController, didEncounterError error: NiivueError) {}
    func niivue(_ controller: NiivueController, intensityDidChange volume: Volume) {}
    func niivue(_ controller: NiivueController, rotationDidChange azimuth: Double, elevation: Double) {}
}
```

### 2.5 Drawing Controller

```swift
/// Controller for drawing and segmentation operations.
@MainActor
public final class DrawingController: ObservableObject {

    // MARK: - State

    /// Whether drawing mode is enabled.
    @Published public var isEnabled: Bool

    /// Current pen color.
    @Published public var penColor: PenColor

    /// Whether pen fills regions.
    @Published public var fillEnabled: Bool

    /// Drawing layer opacity.
    @Published public var opacity: Double

    /// Colormap for drawing visualization.
    @Published public var colormap: ColorMap

    /// Whether click-to-segment is enabled.
    @Published public var clickToSegmentEnabled: Bool

    // MARK: - Actions

    /// Undoes the last drawing operation.
    public func undo() async throws

    /// Clears all drawing data.
    public func clear() async throws

    /// Exports the current drawing as NIfTI data.
    public func export() async throws -> Data

    /// Loads a drawing from NIfTI data.
    public func load(from data: Data) async throws
}

/// Pen colors for drawing.
public enum PenColor: Int, CaseIterable, Sendable {
    case eraser = 0
    case red = 1
    case green = 2
    case blue = 3
    case yellow = 4
    case cyan = 5
    case purple = 6
}
```

---

## 3. Integration Patterns

### 3.1 SwiftUI Integration

#### Basic Usage

```swift
import SwiftUI
import NiivueKit

struct NeuroimagingView: View {
    @StateObject private var controller = NiivueController()
    @State private var volumeURL: URL?

    var body: some View {
        NavigationStack {
            NiivueView(controller: controller)
                .showsHUD(true)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Open") {
                            // Present file picker
                        }
                    }
                }
        }
        .task {
            // Load sample volume when view appears
            if let sampleURL = Bundle.main.url(forResource: "brain", withExtension: "nii.gz") {
                try? await controller.loadVolume(from: sampleURL)
            }
        }
    }
}
```

#### With Bindings

```swift
struct AdvancedViewer: View {
    @StateObject private var controller = NiivueController()

    var body: some View {
        VStack {
            NiivueView(controller: controller)

            // Slice type picker
            Picker("View", selection: sliceTypeBinding) {
                ForEach(SliceType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            // Colormap picker for first volume
            if let firstVolume = controller.volumes.first {
                ColorMapPicker(
                    selection: colormapBinding(for: firstVolume),
                    colormaps: ColorMap.allBuiltIn
                )
            }
        }
    }

    private var sliceTypeBinding: Binding<SliceType> {
        Binding(
            get: { controller.viewConfiguration.sliceType },
            set: { newValue in
                Task { try? await controller.setSliceType(newValue) }
            }
        )
    }

    private func colormapBinding(for volume: Volume) -> Binding<ColorMap> {
        Binding(
            get: { volume.colormap },
            set: { newValue in
                Task { try? await controller.setColormap(newValue, for: volume) }
            }
        )
    }
}
```

### 3.2 UIKit Integration

```swift
import UIKit
import NiivueKit

/// UIKit wrapper for NiivueView.
public final class NiivueUIView: UIView {

    /// The controller managing this view.
    public let controller: NiivueController

    /// Delegate for receiving events.
    public weak var delegate: NiivueDelegate?

    private var hostingController: UIHostingController<NiivueView>?

    public init(frame: CGRect = .zero, configuration: NiivueConfiguration = .default) {
        self.controller = NiivueController(configuration: configuration)
        super.init(frame: frame)
        setupHostingController()
    }

    required init?(coder: NSCoder) {
        self.controller = NiivueController()
        super.init(coder: coder)
        setupHostingController()
    }

    private func setupHostingController() {
        let niivueView = NiivueView(controller: controller)
            .onEvent { [weak self] event in
                self?.handleEvent(event)
            }

        let hosting = UIHostingController(rootView: niivueView)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        hostingController = hosting
    }

    private func handleEvent(_ event: NiivueEvent) {
        switch event {
        case .ready:
            delegate?.niivueDidBecomeReady(controller)
        case .volumeLoaded(let volume):
            delegate?.niivue(controller, didLoadVolume: volume)
        case .crosshairMoved(let location):
            delegate?.niivue(controller, crosshairDidMoveTo: location)
        case .error(let error):
            delegate?.niivue(controller, didEncounterError: error)
        }
    }
}

// MARK: - UIViewController Convenience

public final class NiivueViewController: UIViewController {

    public let niivueView: NiivueUIView

    public var controller: NiivueController {
        niivueView.controller
    }

    public init(configuration: NiivueConfiguration = .default) {
        self.niivueView = NiivueUIView(configuration: configuration)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.niivueView = NiivueUIView()
        super.init(coder: coder)
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.addSubview(niivueView)
        niivueView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            niivueView.topAnchor.constraint(equalTo: view.topAnchor),
            niivueView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            niivueView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            niivueView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
```

### 3.3 Combine Publishers

```swift
import Combine

extension NiivueController {

    /// Publisher that emits when the viewer becomes ready.
    public var readyPublisher: AnyPublisher<Void, Never> {
        $isReady
            .filter { $0 }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Publisher that emits volume changes.
    public var volumesPublisher: AnyPublisher<[Volume], Never> {
        $volumes.eraseToAnyPublisher()
    }

    /// Publisher that emits crosshair location changes.
    public var crosshairPublisher: AnyPublisher<CrosshairLocation?, Never> {
        $crosshairLocation.eraseToAnyPublisher()
    }

    /// Publisher that emits errors.
    public var errorPublisher: AnyPublisher<NiivueError, Never> {
        $error
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
}

// Usage example
class ViewModel: ObservableObject {
    private let controller = NiivueController()
    private var cancellables = Set<AnyCancellable>()

    @Published var intensityAtCrosshair: Double = 0

    init() {
        controller.crosshairPublisher
            .compactMap { $0?.intensityValues.first }
            .receive(on: DispatchQueue.main)
            .assign(to: &$intensityAtCrosshair)
    }
}
```

### 3.4 Async/Await Patterns

```swift
// Sequential loading
func loadStudy(baseURL: URL, overlayURL: URL) async throws {
    try await controller.loadVolume(from: baseURL)
    try await controller.addOverlay(from: overlayURL)
    try await controller.setSliceType(.multiplanar)
}

// Parallel loading with TaskGroup
func loadMultipleVolumes(_ urls: [URL]) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        for (index, url) in urls.enumerated() {
            group.addTask {
                if index == 0 {
                    try await self.controller.loadVolume(from: url)
                } else {
                    try await self.controller.addOverlay(from: url)
                }
            }
        }
        try await group.waitForAll()
    }
}

// Cancellation support
class LoadingViewModel: ObservableObject {
    private var loadingTask: Task<Void, Error>?

    func startLoading(url: URL) {
        loadingTask?.cancel()
        loadingTask = Task {
            try await controller.loadVolume(from: url)
        }
    }

    func cancelLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
}
```

---

## 4. WebView Encapsulation

### 4.1 Bridge Architecture

The SDK completely hides WKWebView from consumers through a layered abstraction:

```
┌─────────────────────────────────────────────────────────────────┐
│                      Public Swift API                            │
│   controller.loadVolume(from: url)                              │
│   controller.setColormap(.hot, for: volume)                     │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CommandBuilder (Internal)                     │
│   Builds type-safe JavaScript commands                          │
│   Handles JSON serialization, escaping, validation              │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   JavaScriptBridge (Internal)                    │
│   Executes commands via WKWebView.evaluateJavaScript            │
│   Handles async Promise resolution                              │
│   Converts JS results to Swift types                            │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                   MessageHandler (Internal)                      │
│   Receives messages from JavaScript via postMessage             │
│   Parses JSON payloads                                          │
│   Routes to appropriate handlers                                │
└───────────────────────────────┬─────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                        WKWebView                                 │
│   Runs React app with Niivue                                    │
│   WebGL 2.0 rendering                                           │
│   Custom niivue:// URL scheme                                   │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 JavaScript Bridge Protocol

```swift
/// Internal protocol for JavaScript evaluation.
/// Not exposed to SDK consumers.
@MainActor
internal protocol JavaScriptBridging: AnyObject {
    /// Executes a command with no return value.
    func execute(_ command: String) async throws

    /// Executes a command and returns a decoded result.
    func execute<T: Decodable>(_ command: String, returning: T.Type) async throws -> T

    /// Executes an async JavaScript function.
    func executeAsync(_ functionBody: String) async throws -> String?
}
```

### 4.3 Command Builder (Type-Safe)

```swift
/// Builds JavaScript commands with type safety and proper escaping.
internal struct CommandBuilder {

    /// Builds a command to load volumes from URLs.
    static func loadVolumes(_ specs: [(url: String, name: String)]) throws -> String {
        let jsonArray = try specs.map { spec in
            let urlEscaped = try JSONEncoder().encode(spec.url)
            let nameEscaped = try JSONEncoder().encode(spec.name)
            return "{\"url\":\(String(data: urlEscaped, encoding: .utf8)!),\"name\":\(String(data: nameEscaped, encoding: .utf8)!)}"
        }.joined(separator: ",")

        return "return await window.loadVolumesFromUrls([\(jsonArray)])"
    }

    /// Builds a command to set colormap.
    static func setColormap(volumeIndex: Int, colormap: String) throws -> String {
        let escaped = try JSONEncoder().encode(colormap)
        return "window.setColormap(\(volumeIndex), \(String(data: escaped, encoding: .utf8)!))"
    }

    /// Builds a command to set slice type.
    static func setSliceType(_ type: SliceType) -> String {
        "window.setSliceType(\(type.rawValue))"
    }

    // ... additional command builders
}
```

### 4.4 Message Handler

```swift
/// Routes messages from JavaScript to appropriate handlers.
internal final class NiivueMessageHandler: NSObject, WKScriptMessageHandler {

    weak var controller: NiivueController?

    private let decoder = JSONDecoder()

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        Task { @MainActor in
            switch message.name {
            case "finishedLoading":
                controller?.handleReady()

            case "volumeLoaded":
                guard let jsonString = message.body as? String,
                      let data = jsonString.data(using: .utf8),
                      let volumeInfo = try? decoder.decode(VolumeInfo.self, from: data)
                else { return }
                controller?.handleVolumeLoaded(volumeInfo)

            case "locationChange":
                guard let jsonString = message.body as? String,
                      let data = jsonString.data(using: .utf8),
                      let location = try? decoder.decode(CrosshairLocation.self, from: data)
                else { return }
                controller?.handleLocationChange(location)

            case "error":
                guard let errorMessage = message.body as? String else { return }
                controller?.handleError(.javascriptError(errorMessage))

            default:
                break
            }
        }
    }
}
```

### 4.5 URL Scheme Handler

```swift
/// Handles niivue:// URL requests for serving bundled and imported files.
internal final class NiivueURLSchemeHandler: NSObject, WKURLSchemeHandler {

    private let router = URLRouter()
    private var importedFiles: [String: URL] = [:]

    enum Route {
        case bundledDist(path: String)
        case bundledSample(path: String)
        case importedFile(id: String)
        case dicomManifest(seriesId: String)
        case dicomFile(seriesId: String, fileName: String)
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let route = router.route(for: url) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        Task { [weak self] in
            do {
                let (data, mimeType) = try await self?.resolveRoute(route) ?? (Data(), "application/octet-stream")

                let response = URLResponse(
                    url: url,
                    mimeType: mimeType,
                    expectedContentLength: data.count,
                    textEncodingName: nil
                )

                await MainActor.run {
                    urlSchemeTask.didReceive(response)
                    urlSchemeTask.didReceive(data)
                    urlSchemeTask.didFinish()
                }
            } catch {
                await MainActor.run {
                    urlSchemeTask.didFailWithError(error)
                }
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Handle cancellation
    }

    // MARK: - File Registration

    func registerImportedFile(id: String, url: URL) {
        importedFiles[id] = url
    }
}
```

---

## 5. Dependency Strategy

### 5.1 Zero External Dependencies

NiivueKit has **no external Swift Package Manager dependencies**. All functionality is provided through:

1. **Bundled React Application** - Pre-built Vite/React app with Niivue
2. **Bundled WASM Modules** - dcm2niix for DICOM processing
3. **Apple Frameworks Only**:
   - WebKit (WKWebView)
   - SwiftUI
   - Combine
   - Foundation

### 5.2 Resource Bundling

```swift
// Package.swift resource configuration
.target(
    name: "NiivueKit",
    dependencies: [],
    resources: [
        // React app build - preserves hashed filenames
        .copy("Resources/dist"),
        // Sample files for demos
        .copy("Resources/samples")
    ]
)
```

### 5.3 Bundle Access

```swift
/// Internal utility for accessing bundled resources.
internal enum BundleAccessor {

    /// Returns the URL for the bundled dist directory.
    static var distDirectory: URL? {
        Bundle.module.url(forResource: "dist", withExtension: nil)
    }

    /// Returns the URL for a sample file.
    static func sampleURL(named name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "samples")
    }
}
```

### 5.4 JavaScript Bundle Updates

The JavaScript bundle is versioned with the SDK. Updates follow this process:

1. Build React app: `cd NiiVue/React && npm run build`
2. Copy to SDK: `cp -r dist/ Sources/NiivueKit/Resources/dist/`
3. Bump SDK version
4. SDK consumers update via SPM

---

## 6. Error Handling

### 6.1 Error Types

```swift
/// Errors that can occur when using NiivueKit.
public enum NiivueError: Error, LocalizedError, Sendable {

    // MARK: - Initialization Errors

    /// The viewer failed to initialize within the timeout period.
    case initializationTimeout

    /// WebGL is not available on this device.
    case webGLUnavailable

    // MARK: - Loading Errors

    /// Failed to load a volume from the specified URL.
    case volumeLoadFailed(url: URL, reason: String)

    /// Failed to load a mesh from the specified URL.
    case meshLoadFailed(url: URL, reason: String)

    /// The file format is not supported.
    case unsupportedFormat(extension: String)

    /// No valid DICOM files found in the selection.
    case noDicomFilesFound

    /// DICOM conversion failed.
    case dicomConversionFailed(reason: String)

    // MARK: - Operation Errors

    /// The viewer is not ready to accept commands.
    case notReady

    /// The specified volume was not found.
    case volumeNotFound(id: String)

    /// The specified mesh was not found.
    case meshNotFound(id: String)

    /// A JavaScript error occurred.
    case javascriptError(String)

    /// An invalid parameter was provided.
    case invalidParameter(name: String, reason: String)

    // MARK: - Export Errors

    /// No drawing data exists to export.
    case noDrawingData

    /// Export operation failed.
    case exportFailed(reason: String)

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .initializationTimeout:
            return "The viewer failed to initialize. Please try again."
        case .webGLUnavailable:
            return "WebGL is not available on this device."
        case .volumeLoadFailed(let url, let reason):
            return "Failed to load volume from \(url.lastPathComponent): \(reason)"
        case .meshLoadFailed(let url, let reason):
            return "Failed to load mesh from \(url.lastPathComponent): \(reason)"
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext)"
        case .noDicomFilesFound:
            return "No valid DICOM files found in the selection."
        case .dicomConversionFailed(let reason):
            return "DICOM conversion failed: \(reason)"
        case .notReady:
            return "The viewer is not ready. Please wait for initialization."
        case .volumeNotFound(let id):
            return "Volume not found: \(id)"
        case .meshNotFound(let id):
            return "Mesh not found: \(id)"
        case .javascriptError(let message):
            return "Internal error: \(message)"
        case .invalidParameter(let name, let reason):
            return "Invalid \(name): \(reason)"
        case .noDrawingData:
            return "No drawing data to export."
        case .exportFailed(let reason):
            return "Export failed: \(reason)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .initializationTimeout:
            return "Check your network connection and try again."
        case .webGLUnavailable:
            return "This device may not support neuroimaging visualization."
        case .volumeLoadFailed, .meshLoadFailed:
            return "Verify the file exists and is not corrupted."
        case .unsupportedFormat:
            return "Supported formats: NIfTI (.nii, .nii.gz), DICOM, NRRD, MGH/MGZ"
        case .noDicomFilesFound:
            return "Select files with .dcm extension or valid DICOM headers."
        case .notReady:
            return "Wait for the viewer to finish loading."
        default:
            return nil
        }
    }
}
```

### 6.2 Error Handling Patterns

```swift
// Pattern 1: Try-catch with user feedback
func loadVolume(url: URL) async {
    do {
        try await controller.loadVolume(from: url)
    } catch let error as NiivueError {
        showAlert(
            title: "Loading Failed",
            message: error.errorDescription ?? "Unknown error",
            suggestion: error.recoverySuggestion
        )
    } catch {
        showAlert(title: "Error", message: error.localizedDescription)
    }
}

// Pattern 2: Result type
extension NiivueController {
    func loadVolumeResult(from url: URL) async -> Result<Volume, NiivueError> {
        do {
            try await loadVolume(from: url)
            guard let volume = volumes.first else {
                return .failure(.volumeNotFound(id: ""))
            }
            return .success(volume)
        } catch let error as NiivueError {
            return .failure(error)
        } catch {
            return .failure(.javascriptError(error.localizedDescription))
        }
    }
}

// Pattern 3: Combine error handling
controller.errorPublisher
    .sink { error in
        logger.error("NiivueKit error: \(error.localizedDescription)")
        analytics.track("niivue_error", properties: ["type": String(describing: error)])
    }
    .store(in: &cancellables)
```

---

## 7. Type Definitions

### 7.1 Volume

```swift
/// Represents a loaded neuroimaging volume.
public struct Volume: Identifiable, Sendable, Equatable {

    /// Unique identifier for this volume.
    public let id: String

    /// Display name (typically the filename).
    public let name: String

    /// Number of frames for 4D volumes (1 for 3D).
    public let frameCount: Int

    /// Whether this is a 4D time-series volume.
    public var is4D: Bool { frameCount > 1 }

    /// Current colormap.
    public internal(set) var colormap: ColorMap

    /// Current opacity (0.0 - 1.0).
    public internal(set) var opacity: Double

    /// Current intensity window minimum.
    public internal(set) var intensityMin: Double

    /// Current intensity window maximum.
    public internal(set) var intensityMax: Double

    /// Current frame index (for 4D volumes).
    public internal(set) var currentFrame: Int
}
```

### 7.2 Mesh

```swift
/// Represents a loaded 3D mesh.
public struct Mesh: Identifiable, Sendable, Equatable {

    /// Unique identifier for this mesh.
    public let id: String

    /// Display name.
    public let name: String

    /// Current opacity.
    public internal(set) var opacity: Double

    /// Current color.
    public internal(set) var color: Color

    /// Current shader.
    public internal(set) var shader: MeshShader
}

/// Available mesh shaders.
public enum MeshShader: String, CaseIterable, Sendable {
    case standard = "Phong"
    case flat = "Flat"
    case toon = "Toon"
    case outline = "Outline"
    case matcap = "Matcap"
}
```

### 7.3 Coordinates

```swift
/// Crosshair location in multiple coordinate systems.
public struct CrosshairLocation: Sendable, Equatable {

    /// Position in millimeters (scanner space).
    public let mm: SIMD3<Double>

    /// Position in voxel indices.
    public let voxel: SIMD3<Int>

    /// Fractional position (0-1 in each dimension).
    public let fraction: SIMD3<Double>

    /// Intensity values at this location for each loaded volume.
    public let intensityValues: [Double]
}
```

### 7.4 View Configuration

```swift
/// Current view configuration state.
public struct ViewConfiguration: Sendable, Equatable {

    /// Current slice type.
    public var sliceType: SliceType

    /// Current multiplanar layout.
    public var layout: MultiplanarLayout

    /// Current drag mode.
    public var dragMode: DragMode

    /// Whether 2D crosshair is visible.
    public var show2DCrosshair: Bool

    /// Whether 3D crosshair is visible.
    public var show3DCrosshair: Bool

    /// Current zoom level.
    public var zoom: Double

    /// Current 3D view azimuth angle (degrees).
    public var azimuth: Double

    /// Current 3D view elevation angle (degrees).
    public var elevation: Double
}

/// Slice view types.
public enum SliceType: Int, CaseIterable, Sendable {
    case axial = 0
    case coronal = 1
    case sagittal = 2
    case multiplanar = 3
    case render = 4

    public var displayName: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        case .multiplanar: return "Multiplanar"
        case .render: return "3D Render"
        }
    }
}

/// Multiplanar layout options.
public enum MultiplanarLayout: Int, CaseIterable, Sendable {
    case auto = 0
    case column = 1
    case grid = 2
    case row = 3
}

/// Drag interaction modes.
public enum DragMode: Int, CaseIterable, Sendable {
    case none = 0
    case contrast = 1
    case measure = 2
    case pan = 3
    case slicer3D = 4
}
```

### 7.5 ColorMap

```swift
/// Built-in colormaps for volume visualization.
public enum ColorMap: String, CaseIterable, Sendable {
    case gray = "gray"
    case hot = "hot"
    case cool = "cool"
    case red = "red"
    case green = "green"
    case blue = "blue"
    case viridis = "viridis"
    case plasma = "plasma"
    case inferno = "inferno"
    case magma = "magma"
    case bone = "bone"
    case copper = "copper"
    case spring = "spring"
    case summer = "summer"
    case autumn = "autumn"
    case winter = "winter"
    case rainbow = "rainbow"
    case jet = "jet"

    /// All built-in colormaps.
    public static let allBuiltIn: [ColorMap] = allCases
}
```

### 7.6 Events

```swift
/// Events emitted by NiivueController.
public enum NiivueEvent: Sendable {
    /// The viewer became ready.
    case ready

    /// A volume was loaded.
    case volumeLoaded(Volume)

    /// A volume was removed.
    case volumeRemoved(Volume)

    /// The crosshair moved.
    case crosshairMoved(CrosshairLocation)

    /// Intensity window changed (user interaction).
    case intensityChanged(Volume)

    /// 3D rotation changed.
    case rotationChanged(azimuth: Double, elevation: Double)

    /// An error occurred.
    case error(NiivueError)
}
```

---

## 8. Code Examples

### 8.1 Complete App Example

```swift
import SwiftUI
import NiivueKit

@main
struct NeuroimagingApp: App {
    var body: some Scene {
        WindowGroup {
            MainView()
        }
    }
}

struct MainView: View {
    @StateObject private var controller = NiivueController(
        configuration: .init(
            initialSliceType: .multiplanar,
            showOrientationLabels: true
        )
    )
    @State private var showFilePicker = false
    @State private var showSettings = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                NiivueView(controller: controller)
                    .showsHUD(true)
                    .onEvent(handleEvent)

                if !controller.isReady {
                    LoadingOverlay()
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Open", systemImage: "plus") {
                        showFilePicker = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("Settings", systemImage: "gear") {
                        showSettings = true
                    }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data],
                allowsMultipleSelection: false
            ) { result in
                Task {
                    await handleFileImport(result)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(controller: controller)
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func handleEvent(_ event: NiivueEvent) {
        switch event {
        case .error(let error):
            errorMessage = error.localizedDescription
        default:
            break
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) async {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                try await controller.loadVolume(from: url)
            } catch let error as NiivueError {
                errorMessage = error.localizedDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }
}

struct LoadingOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .scaleEffect(1.5)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var controller: NiivueController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("View") {
                    Picker("Slice Type", selection: sliceTypeBinding) {
                        ForEach(SliceType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    Picker("Layout", selection: layoutBinding) {
                        Text("Auto").tag(MultiplanarLayout.auto)
                        Text("Column").tag(MultiplanarLayout.column)
                        Text("Grid").tag(MultiplanarLayout.grid)
                        Text("Row").tag(MultiplanarLayout.row)
                    }
                }

                if let volume = controller.volumes.first {
                    Section("Volume: \(volume.name)") {
                        Picker("Colormap", selection: colormapBinding(for: volume)) {
                            ForEach(ColorMap.allBuiltIn, id: \.self) { colormap in
                                Text(colormap.rawValue.capitalized).tag(colormap)
                            }
                        }

                        HStack {
                            Text("Opacity")
                            Slider(value: opacityBinding(for: volume), in: 0...1)
                            Text(String(format: "%.0f%%", volume.opacity * 100))
                                .frame(width: 50)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // Bindings omitted for brevity - same pattern as earlier examples
}
```

### 8.2 DICOM Loading Example

```swift
struct DicomImportView: View {
    @ObservedObject var controller: NiivueController
    @State private var isImporting = false
    @State private var progress: Double = 0
    @State private var statusMessage = ""

    var body: some View {
        VStack(spacing: 20) {
            if isImporting {
                ProgressView(value: progress) {
                    Text(statusMessage)
                }
                .progressViewStyle(.linear)
            } else {
                Button("Import DICOM Series") {
                    Task { await importDicom() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }

    private func importDicom() async {
        // In practice, you'd use a folder picker
        let dicomFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DICOM")

        do {
            isImporting = true
            statusMessage = "Scanning for DICOM files..."

            let dicomFiles = try FileManager.default
                .contentsOfDirectory(at: dicomFolder, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "dcm" }

            guard !dicomFiles.isEmpty else {
                throw NiivueError.noDicomFilesFound
            }

            statusMessage = "Converting \(dicomFiles.count) DICOM files..."
            progress = 0.5

            try await controller.loadDicomSeries(from: dicomFiles)

            progress = 1.0
            statusMessage = "Import complete!"

            try await Task.sleep(nanoseconds: 1_000_000_000)
            isImporting = false

        } catch {
            statusMessage = "Error: \(error.localizedDescription)"
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            isImporting = false
        }
    }
}
```

### 8.3 Drawing & Segmentation Example

```swift
struct SegmentationView: View {
    @ObservedObject var controller: NiivueController

    var drawing: DrawingController {
        controller.drawing
    }

    var body: some View {
        VStack {
            NiivueView(controller: controller)

            HStack(spacing: 16) {
                // Enable drawing toggle
                Toggle("Draw", isOn: $drawing.isEnabled)
                    .toggleStyle(.button)

                // Pen color picker
                Menu {
                    ForEach(PenColor.allCases, id: \.self) { color in
                        Button(colorName(color)) {
                            drawing.penColor = color
                        }
                    }
                } label: {
                    Circle()
                        .fill(swiftUIColor(for: drawing.penColor))
                        .frame(width: 24, height: 24)
                }

                // Click-to-segment toggle
                Toggle("Auto-Segment", isOn: $drawing.clickToSegmentEnabled)
                    .toggleStyle(.button)

                // Undo button
                Button("Undo", systemImage: "arrow.uturn.backward") {
                    Task { try? await drawing.undo() }
                }

                // Export button
                Button("Export", systemImage: "square.and.arrow.up") {
                    Task { await exportDrawing() }
                }
            }
            .padding()
        }
    }

    private func exportDrawing() async {
        do {
            let niftiData = try await drawing.export()
            // Save or share niftiData
        } catch {
            print("Export failed: \(error)")
        }
    }

    private func colorName(_ color: PenColor) -> String {
        switch color {
        case .eraser: return "Eraser"
        case .red: return "Red"
        case .green: return "Green"
        case .blue: return "Blue"
        case .yellow: return "Yellow"
        case .cyan: return "Cyan"
        case .purple: return "Purple"
        }
    }

    private func swiftUIColor(for pen: PenColor) -> Color {
        switch pen {
        case .eraser: return .white
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        case .yellow: return .yellow
        case .cyan: return .cyan
        case .purple: return .purple
        }
    }
}
```

---

## 9. Migration Guide

### 9.1 From Current Implementation to SDK

The current `niivue-ios-foundation` implementation uses direct access to `WebViewManager`. Here's how to migrate:

#### Before (Current)

```swift
// Current implementation
@StateObject private var webViewManager = WebViewManager()

// Loading
try await webViewManager.loadImageFromUrl(url: niivueURL, fileName: fileName)

// Settings
try await webViewManager.setSliceType(sliceType: newValue)
try await webViewManager.setColormap(volumeIndex: 0, colormap: "hot")

// Drawing
try await webViewManager.setPenValue(penValue: 1, isFilled: true, drawingEnabled: true)
```

#### After (SDK)

```swift
// SDK implementation
@StateObject private var controller = NiivueController()

// Loading
try await controller.loadVolume(from: url)

// Settings
try await controller.setSliceType(.multiplanar)
try await controller.setColormap(.hot, for: controller.volumes[0])

// Drawing
controller.drawing.isEnabled = true
controller.drawing.penColor = .red
controller.drawing.fillEnabled = true
```

### 9.2 Key Differences

| Aspect | Current | SDK |
|--------|---------|-----|
| Entry Point | `WebViewManager` | `NiivueController` |
| View | Custom `WebView` wrapper | `NiivueView` |
| Type Safety | Raw integers | Enums (`SliceType`, `ColorMap`) |
| Volume Access | Index-based | `Volume` struct |
| Drawing | Multiple parameters | `DrawingController` |
| Events | String-based messages | `NiivueEvent` enum |
| Errors | Generic `Error` | `NiivueError` enum |

### 9.3 Gradual Migration Path

1. **Phase 1**: Add NiivueKit as dependency alongside existing code
2. **Phase 2**: Create `NiivueController` wrapper around existing `WebViewManager`
3. **Phase 3**: Replace UI components one at a time with SDK equivalents
4. **Phase 4**: Remove legacy code once fully migrated

---

## Appendix A: API Coverage Matrix

Based on the Phase 2 report analysis, here's the planned API coverage:

| Category | Methods | Current | SDK v1.0 Target |
|----------|---------|---------|-----------------|
| Volume Loading | 20+ | ~30% | 80% |
| Volume Display | 15+ | ~33% | 90% |
| Mesh Operations | 18+ | ~5% | 50% |
| 3D Rendering | 8+ | ~0% | 70% |
| Drawing/Segmentation | 25+ | ~24% | 60% |
| Measurements | 10+ | 0% | 30% |
| Navigation | 12+ | ~11% | 80% |
| Configuration | 100+ | ~6% | 40% |
| Event Callbacks | 25+ | ~8% | 50% |
| **Overall** | **200+** | **~25%** | **~60%** |

---

## Appendix B: Platform Support Matrix

| Platform | Min Version | Status |
|----------|-------------|--------|
| iOS | 16.0 | Primary target |
| iPadOS | 16.0 | Full support |
| macCatalyst | 16.0 | Supported |
| visionOS | 1.0 | Experimental |
| macOS (native) | - | Not planned (use Catalyst) |
| tvOS | - | Not planned |
| watchOS | - | Not applicable |

---

## Appendix C: Performance Characteristics

| Operation | Typical Time | Notes |
|-----------|--------------|-------|
| Viewer initialization | 1-3s | WebView + React startup |
| Volume load (50MB) | 2-5s | Includes texture upload |
| DICOM series (100 slices) | 5-15s | Includes dcm2niix WASM |
| Colormap change | <50ms | GPU texture update |
| Slice navigation | <16ms | 60fps capable |
| Drawing stroke | <16ms | Real-time feedback |
| Session export | <100ms | JSON serialization |
| Session restore | 2-5s | Reload + apply state |

---

*Document generated by Claude Code (Opus 4.5) for NiiVue iOS Foundation*
