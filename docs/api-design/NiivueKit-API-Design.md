# NiivueKit: Swift SDK API Design Document

**Version:** 1.0.0
**Date:** January 4, 2026
**Author:** Claude Opus 4.5
**Target Platforms:** iOS 15.0+, iPadOS 15.0+, macOS 12.0+ (Catalyst), visionOS 1.0+

---

## Table of Contents

1. [Design Philosophy](#1-design-philosophy)
2. [Core Types & Protocols](#2-core-types--protocols)
3. [SwiftUI Integration](#3-swiftui-integration)
4. [UIKit Integration](#4-uikit-integration)
5. [Async/Await Design](#5-asyncawait-design)
6. [Type-Safe Enumerations](#6-type-safe-enumerations)
7. [Coordinate Systems](#7-coordinate-systems)
8. [Event Handling](#8-event-handling)
9. [Configuration System](#9-configuration-system)
10. [Property Wrappers & Result Builders](#10-property-wrappers--result-builders)
11. [Complete API Reference](#11-complete-api-reference)
12. [Usage Examples](#12-usage-examples)

---

## 1. Design Philosophy

NiivueKit follows Apple's Swift API Design Guidelines with these core principles:

### 1.1 Clarity at the Point of Use

```swift
// Good: Clear and specific
await viewer.loadVolume(from: dicomURL, options: .init(colormap: .gray))

// Avoid: Ambiguous
await viewer.load(dicomURL, nil, nil, true)
```

### 1.2 Progressive Disclosure

Simple tasks should be simple; advanced features should be discoverable:

```swift
// Simple: Load and display
let viewer = NiivueView()
await viewer.loadVolume(from: niftiURL)

// Advanced: Full control
await viewer.loadVolume(
    from: niftiURL,
    options: VolumeOptions(
        colormap: .viridis,
        opacity: 0.8,
        intensityRange: .custom(min: 100, max: 3000)
    )
)
```

### 1.3 Type Safety Over Stringly-Typed APIs

```swift
// Good: Compiler-checked
viewer.sliceType = .multiplanar
viewer.dragMode = .measurement

// Avoid: Runtime errors possible
viewer.setSliceType("multiplanar")
```

### 1.4 Value Semantics Where Possible

Configuration objects use structs for predictable behavior:

```swift
var config = NiivueConfiguration()
config.crosshairColor = .red
config.isColorbarVisible = true
viewer.configuration = config  // Entire config applied atomically
```

---

## 2. Core Types & Protocols

### 2.1 Main Entry Point: `NiivueController`

The primary API surface is a reference-type controller that manages the WebView lifecycle:

```swift
/// The main controller for neuroimaging visualization.
///
/// `NiivueController` manages the lifecycle of a Niivue WebGL renderer
/// running inside a WKWebView. It provides Swift-native async APIs for
/// loading volumes, meshes, and controlling visualization parameters.
///
/// ## Usage
///
/// ```swift
/// let controller = NiivueController()
/// await controller.loadVolume(from: niftiURL)
/// controller.sliceType = .render
/// ```
@MainActor
public final class NiivueController: ObservableObject {

    // MARK: - Published State

    /// The currently loaded volumes.
    @Published public private(set) var volumes: [NiivueVolume] = []

    /// The currently loaded meshes.
    @Published public private(set) var meshes: [NiivueMesh] = []

    /// Current crosshair position in world coordinates (mm).
    @Published public private(set) var crosshairPosition: WorldCoordinate?

    /// Current crosshair position in voxel coordinates.
    @Published public private(set) var crosshairVoxel: VoxelCoordinate?

    /// Whether the viewer is currently loading data.
    @Published public private(set) var isLoading: Bool = false

    /// The current slice type (axial, coronal, sagittal, multiplanar, render).
    @Published public var sliceType: SliceType = .multiplanar

    /// The current drag interaction mode.
    @Published public var dragMode: DragMode = .crosshair

    /// The current 3D rendering azimuth angle in degrees.
    @Published public private(set) var azimuth: Double = 110

    /// The current 3D rendering elevation angle in degrees.
    @Published public private(set) var elevation: Double = 10

    /// The current zoom multiplier.
    @Published public var zoom: Double = 1.0

    // MARK: - Configuration

    /// The viewer configuration. Changes are applied immediately.
    public var configuration: NiivueConfiguration {
        get { _configuration }
        set {
            _configuration = newValue
            Task { try? await applyConfiguration(newValue) }
        }
    }

    // MARK: - Initialization

    /// Creates a new controller with default configuration.
    public init()

    /// Creates a new controller with custom configuration.
    public init(configuration: NiivueConfiguration)

    // MARK: - Volume Loading

    /// Loads a volume from a URL.
    ///
    /// - Parameters:
    ///   - url: The URL of the volume file (NIfTI, NRRD, MGH, etc.)
    ///   - options: Optional loading and display options.
    /// - Returns: The loaded volume representation.
    /// - Throws: `NiivueError` if loading fails.
    @discardableResult
    public func loadVolume(
        from url: URL,
        options: VolumeOptions = .default
    ) async throws -> NiivueVolume

    /// Loads a volume from in-memory data.
    @discardableResult
    public func loadVolume(
        data: Data,
        filename: String,
        options: VolumeOptions = .default
    ) async throws -> NiivueVolume

    /// Loads a DICOM series from a directory.
    @discardableResult
    public func loadDICOMSeries(
        from directoryURL: URL,
        options: VolumeOptions = .default
    ) async throws -> NiivueVolume

    /// Loads a DICOM series from individual files.
    @discardableResult
    public func loadDICOMSeries(
        files: [URL],
        options: VolumeOptions = .default
    ) async throws -> NiivueVolume

    /// Adds an overlay volume.
    @discardableResult
    public func addOverlay(
        from url: URL,
        options: VolumeOptions = .default
    ) async throws -> NiivueVolume

    /// Removes a volume by reference.
    public func removeVolume(_ volume: NiivueVolume) async throws

    /// Removes all volumes.
    public func removeAllVolumes() async throws

    /// Reorders volumes (changes overlay stacking).
    public func reorderVolumes(_ volumes: [NiivueVolume]) async throws

    // MARK: - Volume Display

    /// Sets the intensity window for a volume.
    public func setIntensityRange(
        for volume: NiivueVolume,
        min: Double,
        max: Double
    ) async throws

    /// Sets the colormap for a volume.
    public func setColormap(
        for volume: NiivueVolume,
        _ colormap: Colormap
    ) async throws

    /// Sets the opacity for a volume.
    public func setOpacity(
        for volume: NiivueVolume,
        _ opacity: Double
    ) async throws

    /// Sets the current 4D frame for a volume.
    public func setFrame(
        for volume: NiivueVolume,
        frame: Int
    ) async throws

    // MARK: - Mesh Loading

    /// Loads a mesh from a URL.
    @discardableResult
    public func loadMesh(
        from url: URL,
        options: MeshOptions = .default
    ) async throws -> NiivueMesh

    /// Removes a mesh.
    public func removeMesh(_ mesh: NiivueMesh) async throws

    /// Removes all meshes.
    public func removeAllMeshes() async throws

    // MARK: - Navigation

    /// Moves the crosshair to world coordinates.
    public func moveCrosshair(to position: WorldCoordinate) async throws

    /// Moves the crosshair to voxel coordinates.
    public func moveCrosshair(toVoxel position: VoxelCoordinate) async throws

    /// Moves the crosshair to fractional coordinates (0-1 in each dimension).
    public func moveCrosshair(toFraction position: FractionalCoordinate) async throws

    /// Sets the 3D view orientation.
    public func setViewOrientation(
        azimuth: Double,
        elevation: Double
    ) async throws

    /// Sets the clip plane for 3D rendering.
    public func setClipPlane(
        depth: Double,
        azimuth: Double,
        elevation: Double
    ) async throws

    /// Removes all clip planes.
    public func removeClipPlanes() async throws

    // MARK: - Drawing & Segmentation

    /// Enables or disables drawing mode.
    public var isDrawingEnabled: Bool

    /// The current pen value (label index) for drawing.
    public var penValue: Int

    /// The pen type for drawing operations.
    public var penType: PenType

    /// The opacity of the drawing overlay.
    public var drawingOpacity: Double

    /// Undoes the last drawing stroke.
    public func undoDrawing() async throws

    /// Clears all drawing.
    public func clearDrawing() async throws

    /// Exports the current drawing as NIfTI data.
    public func exportDrawing() async throws -> Data

    /// Enables click-to-segment mode.
    public var isClickToSegmentEnabled: Bool

    // MARK: - Export

    /// Captures the current view as an image.
    public func captureImage() async throws -> UIImage

    /// Exports a volume as NIfTI data.
    public func exportVolume(_ volume: NiivueVolume) async throws -> Data

    /// Exports the entire session state.
    public func exportSession() async throws -> NiivueSession

    /// Restores a session state.
    public func restoreSession(_ session: NiivueSession) async throws

    // MARK: - Measurement

    /// All completed distance measurements.
    @Published public private(set) var measurements: [DistanceMeasurement] = []

    /// All completed angle measurements.
    @Published public private(set) var angleMeasurements: [AngleMeasurement] = []

    /// Clears all measurements.
    public func clearMeasurements() async throws

    /// Clears all angle measurements.
    public func clearAngleMeasurements() async throws
}
```

### 2.2 Volume Representation: `NiivueVolume`

```swift
/// Represents a loaded neuroimaging volume.
///
/// `NiivueVolume` is a value type that describes a volume's properties
/// and provides methods to query and modify display parameters.
public struct NiivueVolume: Identifiable, Hashable, Sendable {

    /// Unique identifier for this volume.
    public let id: String

    /// Display name (typically derived from filename).
    public let name: String

    /// The URL this volume was loaded from, if applicable.
    public let sourceURL: URL?

    // MARK: - Dimensions

    /// Volume dimensions in voxels [x, y, z].
    public let dimensions: SIMD3<Int>

    /// Voxel size in millimeters [x, y, z].
    public let voxelSize: SIMD3<Double>

    /// Number of time points (for 4D data).
    public let timePoints: Int

    // MARK: - Intensity

    /// Global minimum intensity value.
    public let globalMin: Double

    /// Global maximum intensity value.
    public let globalMax: Double

    /// Robust minimum (2nd percentile).
    public let robustMin: Double

    /// Robust maximum (98th percentile).
    public let robustMax: Double

    /// Current display minimum (cal_min).
    public var displayMin: Double

    /// Current display maximum (cal_max).
    public var displayMax: Double

    // MARK: - Display Properties

    /// Current colormap.
    public var colormap: Colormap

    /// Negative colormap (for bidirectional data).
    public var colormapNegative: Colormap?

    /// Current opacity (0-1).
    public var opacity: Double

    /// Current 4D frame index (0-based).
    public var currentFrame: Int

    /// Whether the colorbar is visible for this volume.
    public var isColorbarVisible: Bool

    // MARK: - Coordinate Transformation

    /// Converts voxel coordinates to world coordinates (mm).
    public func voxelToWorld(_ voxel: VoxelCoordinate) -> WorldCoordinate

    /// Converts world coordinates (mm) to voxel coordinates.
    public func worldToVoxel(_ world: WorldCoordinate) -> VoxelCoordinate

    /// Gets the intensity value at a voxel position.
    public func intensity(at voxel: VoxelCoordinate) -> Double?

    /// Gets the intensity value at a world position.
    public func intensity(atWorld position: WorldCoordinate) -> Double?
}
```

### 2.3 Mesh Representation: `NiivueMesh`

```swift
/// Represents a loaded 3D mesh or tractography data.
public struct NiivueMesh: Identifiable, Hashable, Sendable {

    /// Unique identifier for this mesh.
    public let id: String

    /// Display name.
    public let name: String

    /// The URL this mesh was loaded from, if applicable.
    public let sourceURL: URL?

    /// The type of mesh data.
    public let meshType: MeshType

    // MARK: - Display Properties

    /// Current opacity (0-1).
    public var opacity: Double

    /// Base color in RGBA (0-255 per component).
    public var color: SIMD4<UInt8>

    /// Whether this mesh is visible.
    public var isVisible: Bool

    /// The shader used for rendering.
    public var shader: MeshShader

    // MARK: - Mesh Type

    /// The type of mesh content.
    public enum MeshType: String, Sendable {
        case surface
        case fiber
        case connectome
    }
}
```

### 2.4 Error Types

```swift
/// Errors that can occur during Niivue operations.
public enum NiivueError: LocalizedError, Sendable {

    /// The file format is not supported.
    case unsupportedFormat(String)

    /// The file could not be read.
    case fileReadError(URL, underlying: Error?)

    /// The DICOM series contains no valid images.
    case emptyDICOMSeries

    /// The DICOM files belong to multiple series.
    case mixedDICOMSeries(seriesCount: Int)

    /// DICOM to NIfTI conversion failed.
    case dicomConversionFailed(String)

    /// The JavaScript bridge is not ready.
    case bridgeNotReady

    /// A JavaScript evaluation error occurred.
    case javascriptError(String)

    /// The volume was not found.
    case volumeNotFound(String)

    /// The mesh was not found.
    case meshNotFound(String)

    /// Insufficient storage for the operation.
    case insufficientStorage(required: Int64, available: Int64)

    /// The operation was cancelled.
    case cancelled

    /// An unknown error occurred.
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported file format: \(format)"
        case .fileReadError(let url, let underlying):
            return "Could not read file at \(url.lastPathComponent): \(underlying?.localizedDescription ?? "Unknown error")"
        case .emptyDICOMSeries:
            return "No valid DICOM images found in the selected files"
        case .mixedDICOMSeries(let count):
            return "Selected files contain \(count) different DICOM series. Please select files from a single series."
        case .dicomConversionFailed(let message):
            return "DICOM conversion failed: \(message)"
        case .bridgeNotReady:
            return "The visualization engine is not ready. Please try again."
        case .javascriptError(let message):
            return "Visualization error: \(message)"
        case .volumeNotFound(let id):
            return "Volume not found: \(id)"
        case .meshNotFound(let id):
            return "Mesh not found: \(id)"
        case .insufficientStorage(let required, let available):
            return "Insufficient storage. Required: \(ByteCountFormatter.string(fromByteCount: required, countStyle: .file)), Available: \(ByteCountFormatter.string(fromByteCount: available, countStyle: .file))"
        case .cancelled:
            return "Operation was cancelled"
        case .unknown(let message):
            return message
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unsupportedFormat:
            return "NiivueKit supports NIfTI, NRRD, MGH/MGZ, DICOM, and other common neuroimaging formats."
        case .fileReadError:
            return "Ensure the file exists and you have permission to read it."
        case .emptyDICOMSeries:
            return "Verify the files have .dcm extension or valid DICOM headers."
        case .mixedDICOMSeries:
            return "Select files from only one imaging series."
        case .dicomConversionFailed:
            return "Try with a different DICOM series or verify file integrity."
        case .insufficientStorage:
            return "Free up storage space and try again."
        default:
            return nil
        }
    }
}
```

---

## 3. SwiftUI Integration

### 3.1 Primary View: `NiivueView`

```swift
/// A SwiftUI view that displays neuroimaging data using Niivue.
///
/// `NiivueView` wraps a WKWebView running the Niivue WebGL renderer
/// and provides native SwiftUI bindings for common operations.
///
/// ## Basic Usage
///
/// ```swift
/// struct ContentView: View {
///     @StateObject private var controller = NiivueController()
///
///     var body: some View {
///         NiivueView(controller: controller)
///             .task {
///                 try? await controller.loadVolume(from: niftiURL)
///             }
///     }
/// }
/// ```
///
/// ## With Overlays
///
/// ```swift
/// NiivueView(controller: controller) {
///     // Overlay content rendered on top of WebGL canvas
///     CrosshairInfoOverlay(controller: controller)
/// }
/// ```
public struct NiivueView<Overlay: View>: View {

    /// Creates a Niivue view with the specified controller.
    public init(controller: NiivueController)

    /// Creates a Niivue view with an overlay.
    public init(
        controller: NiivueController,
        @ViewBuilder overlay: () -> Overlay
    )

    public var body: some View
}

// Convenience initializer without overlay
extension NiivueView where Overlay == EmptyView {
    public init(controller: NiivueController)
}
```

### 3.2 Declarative Volume Loading with ViewModifier

```swift
/// A view modifier for declaratively loading volumes.
public struct VolumeLoaderModifier: ViewModifier {
    let url: URL?
    let options: VolumeOptions
    @Binding var volume: NiivueVolume?
    @Binding var error: Error?

    public func body(content: Content) -> some View
}

extension NiivueView {
    /// Loads a volume when the view appears.
    public func loadVolume(
        from url: URL?,
        options: VolumeOptions = .default,
        into binding: Binding<NiivueVolume?>,
        error: Binding<Error?> = .constant(nil)
    ) -> some View
}

// Usage:
struct ContentView: View {
    @StateObject private var controller = NiivueController()
    @State private var volume: NiivueVolume?
    @State private var loadError: Error?

    var body: some View {
        NiivueView(controller: controller)
            .loadVolume(
                from: selectedURL,
                into: $volume,
                error: $loadError
            )
    }
}
```

### 3.3 Convenience Components

```swift
/// A ready-to-use neuroimaging viewer with standard controls.
public struct NiivueViewer: View {

    /// Creates a viewer with optional toolbar configuration.
    public init(
        controller: NiivueController = NiivueController(),
        showsToolbar: Bool = true,
        toolbarPlacement: ToolbarPlacement = .automatic
    )

    public var body: some View
}

/// Displays crosshair position information.
public struct CrosshairInfoView: View {
    @ObservedObject var controller: NiivueController

    public init(controller: NiivueController)
    public var body: some View
}

/// A colormap picker for volume coloring.
public struct ColormapPicker: View {
    @Binding var selection: Colormap
    let colormaps: [Colormap]

    public init(
        selection: Binding<Colormap>,
        colormaps: [Colormap] = Colormap.allCases
    )

    public var body: some View
}

/// A dual-thumb slider for intensity windowing.
public struct IntensityRangeSlider: View {
    @Binding var range: ClosedRange<Double>
    let bounds: ClosedRange<Double>

    public init(
        range: Binding<ClosedRange<Double>>,
        bounds: ClosedRange<Double>
    )

    public var body: some View
}
```

---

## 4. UIKit Integration

### 4.1 UIKit View Controller

```swift
/// A UIKit view controller that hosts a Niivue viewer.
@MainActor
public class NiivueViewController: UIViewController {

    /// The controller managing the Niivue instance.
    public let controller: NiivueController

    /// Delegate for receiving events.
    public weak var delegate: NiivueViewControllerDelegate?

    /// Creates a view controller with a new controller.
    public init()

    /// Creates a view controller with an existing controller.
    public init(controller: NiivueController)

    /// Creates a view controller with configuration.
    public init(configuration: NiivueConfiguration)

    // MARK: - Lifecycle

    public override func viewDidLoad()
    public override func viewDidLayoutSubviews()
}

/// Delegate protocol for UIKit event handling.
@MainActor
public protocol NiivueViewControllerDelegate: AnyObject {

    /// Called when the crosshair position changes.
    func niivueViewController(
        _ viewController: NiivueViewController,
        didMoveCrosshairTo position: WorldCoordinate,
        voxel: VoxelCoordinate,
        values: [VolumeIntensityValue]
    )

    /// Called when a volume is loaded.
    func niivueViewController(
        _ viewController: NiivueViewController,
        didLoadVolume volume: NiivueVolume
    )

    /// Called when a volume's intensity range changes.
    func niivueViewController(
        _ viewController: NiivueViewController,
        didChangeIntensityFor volume: NiivueVolume
    )

    /// Called when a measurement is completed.
    func niivueViewController(
        _ viewController: NiivueViewController,
        didCompleteMeasurement measurement: DistanceMeasurement
    )

    /// Called when click-to-segment completes.
    func niivueViewController(
        _ viewController: NiivueViewController,
        didSegmentVolume result: SegmentationResult
    )

    /// Called when an error occurs.
    func niivueViewController(
        _ viewController: NiivueViewController,
        didEncounterError error: NiivueError
    )
}
```

### 4.2 UIView Subclass

```swift
/// A UIView that displays Niivue content.
@MainActor
public class NiivueUIView: UIView {

    /// The controller managing the Niivue instance.
    public let controller: NiivueController

    /// Creates a view with a new controller.
    public override init(frame: CGRect)

    /// Creates a view with an existing controller.
    public init(frame: CGRect, controller: NiivueController)

    /// Creates a view from a storyboard/nib.
    public required init?(coder: NSCoder)
}
```

---

## 5. Async/Await Design

### 5.1 Design Principles

All methods that interact with the JavaScript bridge are `async` because they involve:
1. Message passing to WKWebView
2. JavaScript execution
3. Response parsing

```swift
// All bridge operations are async and throwing
public func loadVolume(from url: URL) async throws -> NiivueVolume
public func setColormap(for volume: NiivueVolume, _ colormap: Colormap) async throws
public func moveCrosshair(to position: WorldCoordinate) async throws
```

### 5.2 Synchronous State Access

Published properties are synchronously readable but async to modify:

```swift
// Synchronous read
let currentSlice = controller.sliceType

// Async write (through property observer)
controller.sliceType = .render  // Triggers async apply internally
```

### 5.3 Batched Operations

For performance, batch multiple operations:

```swift
/// Applies multiple changes in a single JavaScript evaluation.
public func batch(_ operations: () async throws -> Void) async throws

// Usage:
try await controller.batch {
    try await controller.setColormap(for: volume1, .viridis)
    try await controller.setOpacity(for: volume1, 0.5)
    try await controller.setIntensityRange(for: volume1, min: 0, max: 1000)
}
```

### 5.4 Combine Publishers (Alternative)

For reactive programming patterns:

```swift
extension NiivueController {

    /// Publisher for crosshair position changes.
    public var crosshairPositionPublisher: AnyPublisher<WorldCoordinate, Never> {
        $crosshairPosition
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }

    /// Publisher for volume loading events.
    public var volumeLoadedPublisher: AnyPublisher<NiivueVolume, Never>

    /// Publisher for errors.
    public var errorPublisher: AnyPublisher<NiivueError, Never>

    /// Publisher for intensity changes.
    public var intensityChangedPublisher: AnyPublisher<NiivueVolume, Never>

    /// Publisher for measurement completions.
    public var measurementCompletedPublisher: AnyPublisher<DistanceMeasurement, Never>

    /// Publisher for segmentation results.
    public var segmentationPublisher: AnyPublisher<SegmentationResult, Never>
}

// Usage with Combine:
controller.crosshairPositionPublisher
    .debounce(for: .milliseconds(100), scheduler: RunLoop.main)
    .sink { position in
        updateCoordinateDisplay(position)
    }
    .store(in: &cancellables)
```

### 5.5 AsyncSequence for Streaming Events

```swift
/// An async sequence of location change events.
public struct LocationChangeSequence: AsyncSequence {
    public typealias Element = LocationChangeEvent

    public struct AsyncIterator: AsyncIteratorProtocol {
        public mutating func next() async -> LocationChangeEvent?
    }

    public func makeAsyncIterator() -> AsyncIterator
}

extension NiivueController {
    /// An async sequence of location changes.
    public var locationChanges: LocationChangeSequence { get }
}

// Usage:
Task {
    for await event in controller.locationChanges {
        print("Position: \(event.worldPosition)")
        for value in event.intensityValues {
            print("  \(value.volumeName): \(value.intensity)")
        }
    }
}
```

---

## 6. Type-Safe Enumerations

### 6.1 Slice Types

```swift
/// The type of slice view to display.
public enum SliceType: Int, CaseIterable, Sendable, Codable {
    /// Axial (transverse) view.
    case axial = 0

    /// Coronal view.
    case coronal = 1

    /// Sagittal view.
    case sagittal = 2

    /// Multi-planar reconstruction showing all three views.
    case multiplanar = 3

    /// 3D volume rendering.
    case render = 4

    /// Display name for UI.
    public var displayName: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        case .multiplanar: return "Multiplanar"
        case .render: return "3D Render"
        }
    }

    /// SF Symbol name for this slice type.
    public var systemImage: String {
        switch self {
        case .axial: return "square.split.2x1"
        case .coronal: return "square.split.1x2"
        case .sagittal: return "square.split.2x1.fill"
        case .multiplanar: return "square.grid.2x2"
        case .render: return "cube"
        }
    }
}
```

### 6.2 Drag Modes

```swift
/// The interaction mode for mouse/touch dragging.
public enum DragMode: Int, CaseIterable, Sendable, Codable {
    /// No drag interaction.
    case none = 0

    /// Adjust contrast/brightness window.
    case contrast = 1

    /// Draw distance measurement line.
    case measurement = 2

    /// Pan the view.
    case pan = 3

    /// Rotate the 3D view.
    case slicer3D = 4

    /// Callback only (custom handling).
    case callbackOnly = 5

    /// Region of interest selection.
    case roiSelection = 6

    /// Draw angle measurement.
    case angle = 7

    /// Move crosshair.
    case crosshair = 8

    /// Adjust window/level.
    case windowing = 9

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .contrast: return "Contrast"
        case .measurement: return "Measure Distance"
        case .pan: return "Pan"
        case .slicer3D: return "3D Rotate"
        case .callbackOnly: return "Custom"
        case .roiSelection: return "ROI Selection"
        case .angle: return "Measure Angle"
        case .crosshair: return "Crosshair"
        case .windowing: return "Window/Level"
        }
    }
}
```

### 6.3 Pen Types

```swift
/// The pen type for drawing operations.
public enum PenType: Int, CaseIterable, Sendable, Codable {
    /// Freehand drawing.
    case pen = 0

    /// Rectangular mask.
    case rectangle = 1

    /// Elliptical mask.
    case ellipse = 2

    public var displayName: String {
        switch self {
        case .pen: return "Freehand"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        }
    }
}
```

### 6.4 Colormaps

```swift
/// Available colormaps for volume display.
public enum Colormap: String, CaseIterable, Sendable, Codable {
    // Grayscale
    case gray

    // Sequential
    case viridis
    case plasma
    case inferno
    case magma
    case cividis
    case hot
    case cool
    case bone
    case copper
    case jet
    case turbo
    case hsv
    case warm
    case cool2 = "cool"

    // Medical
    case freesurfer
    case aal
    case actc
    case ct_artery = "ct_artery"
    case ct_bones = "ct_bones"
    case ct_brain = "ct_brain"
    case ct_kidneys = "ct_kidneys"
    case ct_liver = "ct_liver"
    case ct_lungs = "ct_lungs"
    case ct_muscles = "ct_muscles"
    case ct_soft_tissue = "ct_soft_tissue"

    // Diverging
    case redyellow = "red-yellow"
    case bluecyan = "blue-cyan"
    case redwhiteblue = "red-white-blue"

    // Qualitative
    case random
    case `$itksnap` = "itksnap"
    case `$nih` = "nih"

    /// The display name for UI.
    public var displayName: String {
        rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    /// Colormaps suitable for anatomical data.
    public static var anatomical: [Colormap] {
        [.gray, .bone, .copper]
    }

    /// Colormaps suitable for statistical maps.
    public static var statistical: [Colormap] {
        [.hot, .cool, .jet, .viridis, .plasma, .inferno, .redyellow, .bluecyan]
    }

    /// Colormaps suitable for label/segmentation data.
    public static var label: [Colormap] {
        [.freesurfer, .aal, .random, .$itksnap, .$nih]
    }

    /// Colormaps suitable for CT imaging.
    public static var ct: [Colormap] {
        [.ct_brain, .ct_bones, .ct_artery, .ct_kidneys, .ct_liver, .ct_lungs, .ct_muscles, .ct_soft_tissue]
    }
}
```

### 6.5 Multiplanar Layout

```swift
/// Layout options for multiplanar view.
public enum MultiplanarLayout: Int, CaseIterable, Sendable, Codable {
    /// Automatic layout based on canvas aspect ratio.
    case auto = 0

    /// Stack slices in a column.
    case column = 1

    /// Arrange slices in a 2x2 grid.
    case grid = 2

    /// Arrange slices in a row.
    case row = 3

    public var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .column: return "Column"
        case .grid: return "Grid"
        case .row: return "Row"
        }
    }
}
```

### 6.6 Mesh Shaders

```swift
/// Available shaders for mesh rendering.
public enum MeshShader: String, CaseIterable, Sendable, Codable {
    /// Standard Phong lighting.
    case phong = "Phong"

    /// Flat shading.
    case flat = "Flat"

    /// Matcap (material capture) shading.
    case matcap = "Matcap"

    /// Matcap with curvature.
    case matcapCurvature = "MatcapCurvature"

    /// Hemisphere lighting.
    case hemisphere = "Hemisphere"

    /// Fresnel (rim lighting) effect.
    case fresnel = "Fresnel"

    /// Cartoon/toon shading.
    case toon = "Toon"

    /// Outline (silhouette) effect.
    case outline = "Outline"

    /// X-ray transparency effect.
    case xray = "Xray"

    public var displayName: String { rawValue }
}
```

---

## 7. Coordinate Systems

### 7.1 Strongly-Typed Coordinates

```swift
/// A position in world coordinates (millimeters from scanner origin).
public struct WorldCoordinate: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double)

    /// Creates from a SIMD3 vector.
    public init(_ vector: SIMD3<Double>)

    /// Converts to SIMD3.
    public var simd: SIMD3<Double> {
        SIMD3(x, y, z)
    }

    /// The origin (0, 0, 0).
    public static let zero = WorldCoordinate(x: 0, y: 0, z: 0)

    /// Distance to another coordinate.
    public func distance(to other: WorldCoordinate) -> Double
}

/// A position in voxel coordinates (integer indices into volume).
public struct VoxelCoordinate: Hashable, Sendable, Codable {
    public var i: Int
    public var j: Int
    public var k: Int

    public init(i: Int, j: Int, k: Int)

    /// Creates from a SIMD3 vector.
    public init(_ vector: SIMD3<Int>)

    /// Converts to SIMD3.
    public var simd: SIMD3<Int> {
        SIMD3(i, j, k)
    }

    /// Checks if within bounds.
    public func isWithinBounds(of dimensions: SIMD3<Int>) -> Bool {
        i >= 0 && i < dimensions.x &&
        j >= 0 && j < dimensions.y &&
        k >= 0 && k < dimensions.z
    }
}

/// A position in fractional coordinates (0-1 normalized to volume extent).
public struct FractionalCoordinate: Hashable, Sendable, Codable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double)

    /// Clamps to valid range [0, 1].
    public var clamped: FractionalCoordinate {
        FractionalCoordinate(
            x: max(0, min(1, x)),
            y: max(0, min(1, y)),
            z: max(0, min(1, z))
        )
    }

    /// Center of volume.
    public static let center = FractionalCoordinate(x: 0.5, y: 0.5, z: 0.5)
}
```

### 7.2 Coordinate Conversion

```swift
extension NiivueVolume {
    /// Converts voxel to world coordinates.
    public func voxelToWorld(_ voxel: VoxelCoordinate) -> WorldCoordinate

    /// Converts world to voxel coordinates.
    public func worldToVoxel(_ world: WorldCoordinate) -> VoxelCoordinate

    /// Converts voxel to fractional coordinates.
    public func voxelToFraction(_ voxel: VoxelCoordinate) -> FractionalCoordinate

    /// Converts fractional to voxel coordinates.
    public func fractionToVoxel(_ frac: FractionalCoordinate) -> VoxelCoordinate

    /// Converts world to fractional coordinates.
    public func worldToFraction(_ world: WorldCoordinate) -> FractionalCoordinate

    /// Converts fractional to world coordinates.
    public func fractionToWorld(_ frac: FractionalCoordinate) -> WorldCoordinate
}
```

---

## 8. Event Handling

### 8.1 Combined Approach: Closures + Combine + AsyncSequence

```swift
extension NiivueController {

    // MARK: - Closure-Based Handlers

    /// Called when the crosshair position changes.
    public var onLocationChange: ((LocationChangeEvent) -> Void)?

    /// Called when a volume is loaded.
    public var onVolumeLoaded: ((NiivueVolume) -> Void)?

    /// Called when a mesh is loaded.
    public var onMeshLoaded: ((NiivueMesh) -> Void)?

    /// Called when intensity range changes.
    public var onIntensityChange: ((NiivueVolume) -> Void)?

    /// Called when the 3D view rotates.
    public var onAzimuthElevationChange: ((Double, Double) -> Void)?

    /// Called when zoom changes.
    public var onZoomChange: ((Double) -> Void)?

    /// Called when a measurement completes.
    public var onMeasurementComplete: ((DistanceMeasurement) -> Void)?

    /// Called when an angle measurement completes.
    public var onAngleMeasurementComplete: ((AngleMeasurement) -> Void)?

    /// Called when click-to-segment completes.
    public var onClickToSegment: ((SegmentationResult) -> Void)?

    /// Called when a clip plane changes.
    public var onClipPlaneChange: ((ClipPlane) -> Void)?

    /// Called when the 4D frame changes.
    public var onFrameChange: ((NiivueVolume, Int) -> Void)?

    /// Called when an error occurs.
    public var onError: ((NiivueError) -> Void)?
}

// MARK: - Event Types

/// Event data for location changes.
public struct LocationChangeEvent: Sendable {
    /// World coordinates in mm.
    public let worldPosition: WorldCoordinate

    /// Voxel coordinates.
    public let voxelPosition: VoxelCoordinate

    /// Fractional coordinates.
    public let fractionalPosition: FractionalCoordinate

    /// Intensity values at this location for each loaded volume.
    public let intensityValues: [VolumeIntensityValue]

    /// The slice type where the click occurred.
    public let sliceType: SliceType

    /// Formatted coordinate string.
    public let formattedString: String
}

/// Intensity value at a location for a specific volume.
public struct VolumeIntensityValue: Sendable {
    /// The volume ID.
    public let volumeID: String

    /// The volume name.
    public let volumeName: String

    /// The intensity value.
    public let intensity: Double

    /// World coordinates.
    public let worldPosition: WorldCoordinate

    /// Voxel coordinates.
    public let voxelPosition: VoxelCoordinate
}

/// A completed distance measurement.
public struct DistanceMeasurement: Identifiable, Sendable {
    public let id: UUID

    /// Start point in world coordinates.
    public let startWorld: WorldCoordinate

    /// End point in world coordinates.
    public let endWorld: WorldCoordinate

    /// Distance in millimeters.
    public let distanceMM: Double

    /// The slice type where measurement was made.
    public let sliceType: SliceType

    /// Slice position in mm.
    public let slicePosition: Double

    /// Formatted distance string.
    public var formattedDistance: String {
        String(format: "%.2f mm", distanceMM)
    }
}

/// A completed angle measurement.
public struct AngleMeasurement: Identifiable, Sendable {
    public let id: UUID

    /// First line endpoints in world coordinates.
    public let firstLine: (start: WorldCoordinate, end: WorldCoordinate)

    /// Second line endpoints in world coordinates.
    public let secondLine: (start: WorldCoordinate, end: WorldCoordinate)

    /// Angle in degrees.
    public let angleDegrees: Double

    /// The slice type where measurement was made.
    public let sliceType: SliceType
}

/// Result of a click-to-segment operation.
public struct SegmentationResult: Sendable {
    /// Volume in cubic millimeters.
    public let volumeMM3: Double

    /// Volume in milliliters.
    public let volumeML: Double

    /// Formatted volume string.
    public var formattedVolume: String {
        if volumeML >= 1 {
            return String(format: "%.2f mL", volumeML)
        } else {
            return String(format: "%.1f mm\u{00B3}", volumeMM3)
        }
    }
}

/// Clip plane parameters.
public struct ClipPlane: Sendable {
    /// Depth from 0 (far) to 1 (near). Values > 1 disable the clip plane.
    public let depth: Double

    /// Azimuth angle in degrees.
    public let azimuth: Double

    /// Elevation angle in degrees.
    public let elevation: Double

    /// Creates a disabled clip plane.
    public static let disabled = ClipPlane(depth: 2, azimuth: 0, elevation: 0)
}
```

---

## 9. Configuration System

### 9.1 Configuration Struct

```swift
/// Configuration options for the Niivue viewer.
public struct NiivueConfiguration: Sendable, Codable, Equatable {

    // MARK: - Text & Labels

    /// Height of text labels as fraction of canvas height. -1 for automatic.
    public var textHeight: Double = -1.0

    /// Font size scaling factor.
    public var fontSizeScaling: Double = 0.4

    /// Minimum font size in pixels.
    public var fontMinPx: Double = 13

    /// Loading text displayed while volumes load.
    public var loadingText: String = "Loading..."

    // MARK: - Colorbar

    /// Whether to show the colorbar.
    public var isColorbarVisible: Bool = false

    /// Height of colorbar as fraction of canvas height.
    public var colorbarHeight: Double = 0.05

    /// Width of colorbar in pixels. -1 for automatic (full width).
    public var colorbarWidth: Double = -1

    /// Whether to show border around colorbar.
    public var showColorbarBorder: Bool = true

    // MARK: - Crosshair

    /// Crosshair color (RGBA, 0-1).
    public var crosshairColor: SIMD4<Double> = [1, 0, 0, 1]

    /// Crosshair line width.
    public var crosshairWidth: Double = 1

    /// Unit for crosshair width measurement.
    public var crosshairWidthUnit: CrosshairWidthUnit = .voxels

    /// Gap in center of crosshair.
    public var crosshairGap: Double = 0

    /// Whether to show 3D crosshair in render mode.
    public var show3DCrosshair: Bool = false

    // MARK: - Colors

    /// Background color (RGBA, 0-1).
    public var backgroundColor: SIMD4<Double> = [0, 0, 0, 1]

    /// Font color (RGBA, 0-1).
    public var fontColor: SIMD4<Double> = [0.5, 0.5, 0.5, 1]

    /// Selection box color (RGBA, 0-1).
    public var selectionBoxColor: SIMD4<Double> = [1, 1, 1, 0.5]

    /// Clip plane color (RGBA, 0-1).
    public var clipPlaneColor: SIMD4<Double> = [0.7, 0, 0.7, 0.5]

    /// Ruler color (RGBA, 0-1).
    public var rulerColor: SIMD4<Double> = [1, 0, 0, 0.8]

    // MARK: - Ruler

    /// Whether to show the ruler.
    public var isRulerVisible: Bool = false

    /// Ruler line width.
    public var rulerWidth: Double = 4

    // MARK: - Orientation

    /// Whether to show the orientation cube.
    public var isOrientationCubeVisible: Bool = false

    /// Whether to show corner orientation text.
    public var isCornerOrientationTextVisible: Bool = false

    /// Whether to show all orientation markers.
    public var showAllOrientationMarkers: Bool = false

    /// Use radiological convention (left-right flipped).
    public var isRadiologicalConvention: Bool = false

    /// Whether nose points left in sagittal view.
    public var sagittalNoseLeft: Bool = false

    // MARK: - Rendering

    /// Use nearest neighbor interpolation instead of linear.
    public var isNearestInterpolation: Bool = false

    /// Atlas outline opacity (0 for none).
    public var atlasOutline: Double = 0

    /// Mesh thickness on 2D slices. Use .infinity for unlimited.
    public var meshThicknessOn2D: Double = .infinity

    /// Initial slice type.
    public var sliceType: SliceType = .multiplanar

    /// Multiplanar layout.
    public var multiplanarLayout: MultiplanarLayout = .auto

    /// Padding between multiplanar views in pixels.
    public var multiplanarPadPixels: Double = 0

    /// Force render view in multiplanar.
    public var multiplanarShowRender: ShowRender = .auto

    // MARK: - Interaction

    /// Primary drag mode.
    public var dragMode: DragMode = .contrast

    /// Enable drag and drop file loading.
    public var dragAndDropEnabled: Bool = true

    /// Double touch timeout in milliseconds.
    public var doubleTouchTimeout: Double = 500

    /// Long touch timeout in milliseconds.
    public var longTouchTimeout: Double = 1000

    // MARK: - Drawing

    /// Enable drawing mode.
    public var drawingEnabled: Bool = false

    /// Pen value (label index).
    public var penValue: Int = 1

    /// Pen type.
    public var penType: PenType = .pen

    /// Pen size in voxels.
    public var penSize: Int = 1

    /// Use filled pen strokes.
    public var isFilledPen: Bool = false

    /// Maximum undo bitmaps to store.
    public var maxDrawUndoBitmaps: Int = 8

    /// Flood fill neighbor connectivity (6, 18, or 26).
    public var floodFillNeighbors: Int = 6

    // MARK: - Click to Segment

    /// Enable click-to-segment mode.
    public var clickToSegment: Bool = false

    /// Click-to-segment radius in mm.
    public var clickToSegmentRadius: Double = 3

    /// Use bright regions for click-to-segment.
    public var clickToSegmentBright: Bool = true

    /// Maximum distance in mm for click-to-segment.
    public var clickToSegmentMaxDistanceMM: Double = .infinity

    /// Restrict click-to-segment to 2D.
    public var clickToSegmentIs2D: Bool = false

    // MARK: - Measurements

    /// Show measurement units (mm).
    public var showMeasurementUnits: Bool = true

    /// Measurement text justification.
    public var measurementTextJustify: TextJustify = .center

    /// Measurement text color (RGBA, 0-1).
    public var measurementTextColor: SIMD4<Double> = [1, 0, 0, 1]

    /// Measurement line color (RGBA, 0-1).
    public var measurementLineColor: SIMD4<Double> = [1, 0, 0, 1]

    /// Measurement text height as fraction of canvas.
    public var measurementTextHeight: Double = 0.06

    // MARK: - Volume Rendering

    /// Gradient opacity for volume rendering.
    public var gradientOpacity: Double = 0.0

    /// Gradient amount.
    public var gradientAmount: Double = 0.0

    /// Render overlay blend factor.
    public var renderOverlayBlend: Double = 1.0

    /// Render silhouette amount.
    public var renderSilhouette: Double = 0.0

    // MARK: - Nested Types

    /// Unit for crosshair width.
    public enum CrosshairWidthUnit: String, Sendable, Codable {
        case voxels
        case mm
        case percent
    }

    /// When to show render view in multiplanar.
    public enum ShowRender: Int, Sendable, Codable {
        case never = 0
        case always = 1
        case auto = 2
    }

    /// Text justification for measurements.
    public enum TextJustify: String, Sendable, Codable {
        case start
        case center
        case end
    }

    // MARK: - Presets

    /// Default configuration.
    public static let `default` = NiivueConfiguration()

    /// Configuration optimized for neuroimaging.
    public static var neuroimaging: NiivueConfiguration {
        var config = NiivueConfiguration()
        config.isColorbarVisible = true
        config.isOrientationCubeVisible = true
        config.sliceType = .multiplanar
        return config
    }

    /// Configuration optimized for radiological viewing.
    public static var radiology: NiivueConfiguration {
        var config = NiivueConfiguration()
        config.isRadiologicalConvention = true
        config.backgroundColor = [0, 0, 0, 1]
        config.sliceType = .axial
        return config
    }

    /// Configuration optimized for 3D visualization.
    public static var render3D: NiivueConfiguration {
        var config = NiivueConfiguration()
        config.sliceType = .render
        config.show3DCrosshair = true
        config.isOrientationCubeVisible = true
        return config
    }

    /// Configuration optimized for segmentation/drawing.
    public static var segmentation: NiivueConfiguration {
        var config = NiivueConfiguration()
        config.drawingEnabled = true
        config.penType = .pen
        config.penValue = 1
        config.sliceType = .multiplanar
        config.crosshairColor = [0, 1, 0, 1]  // Green crosshair
        return config
    }
}
```

### 9.2 Volume Options

```swift
/// Options for loading and displaying a volume.
public struct VolumeOptions: Sendable {
    /// The colormap to use.
    public var colormap: Colormap = .gray

    /// Negative colormap (for bidirectional data).
    public var colormapNegative: Colormap?

    /// Initial opacity (0-1).
    public var opacity: Double = 1.0

    /// Intensity range.
    public var intensityRange: IntensityRange = .automatic

    /// Trust cal_min/cal_max from header.
    public var trustCalMinMax: Bool = true

    /// Percentile fraction for robust min/max.
    public var percentileFrac: Double = 0.02

    /// Ignore zero voxels when calculating intensity range.
    public var ignoreZeroVoxels: Bool = false

    /// Use QForm instead of SForm for orientation.
    public var useQFormNotSForm: Bool = false

    /// Initial 4D frame (0-based).
    public var frame4D: Int = 0

    /// Whether colorbar is visible for this volume.
    public var colorbarVisible: Bool = true

    /// Intensity range options.
    public enum IntensityRange: Sendable {
        /// Use automatic range calculation.
        case automatic

        /// Use values from file header.
        case fromHeader

        /// Use custom min/max values.
        case custom(min: Double, max: Double)

        /// Use robust percentile range.
        case robust(percentile: Double)
    }

    /// Default options.
    public static let `default` = VolumeOptions()

    /// Options for overlay volumes.
    public static var overlay: VolumeOptions {
        var options = VolumeOptions()
        options.opacity = 0.5
        return options
    }

    /// Options for statistical maps.
    public static var statisticalMap: VolumeOptions {
        var options = VolumeOptions()
        options.colormap = .hot
        options.colormapNegative = .cool
        options.intensityRange = .custom(min: 2.5, max: 6.0)  // t-values
        return options
    }

    /// Options for label/segmentation volumes.
    public static var labelMap: VolumeOptions {
        var options = VolumeOptions()
        options.colormap = .freesurfer
        options.intensityRange = .automatic
        options.ignoreZeroVoxels = true
        return options
    }
}
```

### 9.3 Mesh Options

```swift
/// Options for loading and displaying a mesh.
public struct MeshOptions: Sendable {
    /// Initial opacity (0-1).
    public var opacity: Double = 1.0

    /// Base color in RGBA (0-255).
    public var color: SIMD4<UInt8> = [255, 255, 255, 255]

    /// Whether the mesh is initially visible.
    public var visible: Bool = true

    /// The shader to use for rendering.
    public var shader: MeshShader = .phong

    /// Whether the colorbar is visible.
    public var colorbarVisible: Bool = true

    /// Default options.
    public static let `default` = MeshOptions()

    /// Options for brain surfaces.
    public static var brainSurface: MeshOptions {
        var options = MeshOptions()
        options.shader = .matcap
        options.color = [200, 200, 200, 255]
        return options
    }

    /// Options for tractography.
    public static var tractography: MeshOptions {
        var options = MeshOptions()
        options.shader = .phong
        return options
    }
}
```

---

## 10. Property Wrappers & Result Builders

### 10.1 @NiivueBinding Property Wrapper

```swift
/// A property wrapper that synchronizes with a Niivue JavaScript property.
@propertyWrapper
public struct NiivueBinding<Value> {
    private let keyPath: WritableKeyPath<NiivueController, Value>
    private let jsProperty: String

    public var wrappedValue: Value {
        get { /* read from controller */ }
        nonmutating set { /* update controller and sync to JS */ }
    }

    public init(_ jsProperty: String, on keyPath: WritableKeyPath<NiivueController, Value>)
}

// Usage in view:
struct ControlsView: View {
    @ObservedObject var controller: NiivueController

    var body: some View {
        Picker("Slice Type", selection: $controller.sliceType) {
            ForEach(SliceType.allCases, id: \.self) { type in
                Text(type.displayName).tag(type)
            }
        }
    }
}
```

### 10.2 Volume Configuration DSL

```swift
/// Result builder for configuring volumes declaratively.
@resultBuilder
public struct VolumeConfigurationBuilder {
    public static func buildBlock(_ components: VolumeModifier...) -> [VolumeModifier]
    public static func buildOptional(_ component: [VolumeModifier]?) -> [VolumeModifier]
    public static func buildEither(first: [VolumeModifier]) -> [VolumeModifier]
    public static func buildEither(second: [VolumeModifier]) -> [VolumeModifier]
}

/// A modifier for volume configuration.
public protocol VolumeModifier {
    func apply(to options: inout VolumeOptions)
}

// Built-in modifiers
public struct ColormapModifier: VolumeModifier {
    let colormap: Colormap
    public func apply(to options: inout VolumeOptions) {
        options.colormap = colormap
    }
}

public struct OpacityModifier: VolumeModifier {
    let opacity: Double
    public func apply(to options: inout VolumeOptions) {
        options.opacity = opacity
    }
}

public struct IntensityRangeModifier: VolumeModifier {
    let range: VolumeOptions.IntensityRange
    public func apply(to options: inout VolumeOptions) {
        options.intensityRange = range
    }
}

// DSL functions
public func colormap(_ colormap: Colormap) -> ColormapModifier {
    ColormapModifier(colormap: colormap)
}

public func opacity(_ value: Double) -> OpacityModifier {
    OpacityModifier(opacity: value)
}

public func intensityRange(min: Double, max: Double) -> IntensityRangeModifier {
    IntensityRangeModifier(range: .custom(min: min, max: max))
}

// Extension for DSL usage
extension NiivueController {
    @discardableResult
    public func loadVolume(
        from url: URL,
        @VolumeConfigurationBuilder configure: () -> [VolumeModifier]
    ) async throws -> NiivueVolume {
        var options = VolumeOptions.default
        for modifier in configure() {
            modifier.apply(to: &options)
        }
        return try await loadVolume(from: url, options: options)
    }
}

// Usage:
try await controller.loadVolume(from: niftiURL) {
    colormap(.viridis)
    opacity(0.8)
    intensityRange(min: 0, max: 1000)
}
```

### 10.3 View Builder Extensions

```swift
extension NiivueView {
    /// Configures the viewer with a builder pattern.
    public func configure(_ configuration: NiivueConfiguration) -> some View {
        self.onAppear {
            controller.configuration = configuration
        }
    }

    /// Sets the slice type.
    public func sliceType(_ type: SliceType) -> some View {
        self.onAppear {
            controller.sliceType = type
        }
    }

    /// Sets the drag mode.
    public func dragMode(_ mode: DragMode) -> some View {
        self.onAppear {
            controller.dragMode = mode
        }
    }

    /// Adds an action for location changes.
    public func onLocationChange(
        perform action: @escaping (LocationChangeEvent) -> Void
    ) -> some View {
        self.onAppear {
            controller.onLocationChange = action
        }
    }

    /// Adds an action for volume loading.
    public func onVolumeLoaded(
        perform action: @escaping (NiivueVolume) -> Void
    ) -> some View {
        self.onAppear {
            controller.onVolumeLoaded = action
        }
    }
}

// Usage:
NiivueView(controller: controller)
    .configure(.neuroimaging)
    .sliceType(.multiplanar)
    .dragMode(.crosshair)
    .onLocationChange { event in
        print("Position: \(event.worldPosition)")
    }
    .onVolumeLoaded { volume in
        print("Loaded: \(volume.name)")
    }
```

---

## 11. Complete API Reference

### 11.1 Public Types Summary

| Type | Category | Description |
|------|----------|-------------|
| `NiivueController` | Core | Main controller for managing Niivue instance |
| `NiivueView` | SwiftUI | SwiftUI view displaying Niivue content |
| `NiivueViewController` | UIKit | UIKit view controller for Niivue |
| `NiivueUIView` | UIKit | UIKit view for Niivue |
| `NiivueVolume` | Data | Volume representation |
| `NiivueMesh` | Data | Mesh representation |
| `NiivueConfiguration` | Config | Viewer configuration options |
| `VolumeOptions` | Config | Volume loading options |
| `MeshOptions` | Config | Mesh loading options |
| `SliceType` | Enum | View type enumeration |
| `DragMode` | Enum | Interaction mode enumeration |
| `PenType` | Enum | Drawing pen type enumeration |
| `Colormap` | Enum | Colormap enumeration |
| `MultiplanarLayout` | Enum | Layout enumeration |
| `MeshShader` | Enum | Mesh shader enumeration |
| `WorldCoordinate` | Coord | World coordinate type |
| `VoxelCoordinate` | Coord | Voxel coordinate type |
| `FractionalCoordinate` | Coord | Fractional coordinate type |
| `LocationChangeEvent` | Event | Location change event data |
| `VolumeIntensityValue` | Event | Intensity value at location |
| `DistanceMeasurement` | Event | Distance measurement result |
| `AngleMeasurement` | Event | Angle measurement result |
| `SegmentationResult` | Event | Click-to-segment result |
| `ClipPlane` | Event | Clip plane parameters |
| `NiivueError` | Error | Error type enumeration |
| `NiivueSession` | Export | Session state for save/restore |

### 11.2 NiivueController Methods Summary

| Category | Method | Description |
|----------|--------|-------------|
| Volume | `loadVolume(from:options:)` | Load volume from URL |
| Volume | `loadVolume(data:filename:options:)` | Load volume from data |
| Volume | `loadDICOMSeries(from:options:)` | Load DICOM from directory |
| Volume | `loadDICOMSeries(files:options:)` | Load DICOM from files |
| Volume | `addOverlay(from:options:)` | Add overlay volume |
| Volume | `removeVolume(_:)` | Remove volume |
| Volume | `removeAllVolumes()` | Remove all volumes |
| Volume | `reorderVolumes(_:)` | Reorder volume stack |
| Display | `setIntensityRange(for:min:max:)` | Set intensity window |
| Display | `setColormap(for:_:)` | Set volume colormap |
| Display | `setOpacity(for:_:)` | Set volume opacity |
| Display | `setFrame(for:frame:)` | Set 4D frame |
| Mesh | `loadMesh(from:options:)` | Load mesh from URL |
| Mesh | `removeMesh(_:)` | Remove mesh |
| Mesh | `removeAllMeshes()` | Remove all meshes |
| Nav | `moveCrosshair(to:)` | Move crosshair to world coords |
| Nav | `moveCrosshair(toVoxel:)` | Move crosshair to voxel coords |
| Nav | `moveCrosshair(toFraction:)` | Move crosshair to fraction coords |
| Nav | `setViewOrientation(azimuth:elevation:)` | Set 3D orientation |
| Nav | `setClipPlane(depth:azimuth:elevation:)` | Set clip plane |
| Nav | `removeClipPlanes()` | Remove clip planes |
| Draw | `undoDrawing()` | Undo last stroke |
| Draw | `clearDrawing()` | Clear all drawing |
| Draw | `exportDrawing()` | Export drawing as NIfTI |
| Export | `captureImage()` | Capture view as image |
| Export | `exportVolume(_:)` | Export volume as NIfTI |
| Export | `exportSession()` | Export session state |
| Export | `restoreSession(_:)` | Restore session state |
| Measure | `clearMeasurements()` | Clear distance measurements |
| Measure | `clearAngleMeasurements()` | Clear angle measurements |

---

## 12. Usage Examples

### 12.1 Basic Volume Loading

```swift
import NiivueKit
import SwiftUI

struct BasicViewer: View {
    @StateObject private var controller = NiivueController()

    let volumeURL: URL

    var body: some View {
        NiivueView(controller: controller)
            .task {
                do {
                    try await controller.loadVolume(from: volumeURL)
                } catch {
                    print("Failed to load volume: \(error)")
                }
            }
    }
}
```

### 12.2 Multiple Volumes with Overlays

```swift
struct OverlayViewer: View {
    @StateObject private var controller = NiivueController()

    let anatomicalURL: URL
    let statisticalMapURL: URL

    var body: some View {
        NiivueView(controller: controller)
            .task {
                // Load anatomical as base
                try? await controller.loadVolume(
                    from: anatomicalURL,
                    options: VolumeOptions(colormap: .gray)
                )

                // Add statistical map overlay
                try? await controller.addOverlay(
                    from: statisticalMapURL,
                    options: .statisticalMap
                )
            }
    }
}
```

### 12.3 DICOM Import

```swift
struct DicomImporter: View {
    @StateObject private var controller = NiivueController()
    @State private var isImporting = false

    var body: some View {
        VStack {
            NiivueView(controller: controller)

            Button("Import DICOM") {
                isImporting = true
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            Task {
                switch result {
                case .success(let urls):
                    try await controller.loadDICOMSeries(files: urls)
                case .failure(let error):
                    print("Import failed: \(error)")
                }
            }
        }
    }
}
```

### 12.4 Interactive Controls

```swift
struct InteractiveViewer: View {
    @StateObject private var controller = NiivueController()
    @State private var selectedVolume: NiivueVolume?

    var body: some View {
        NavigationSplitView {
            // Sidebar with controls
            Form {
                Section("View") {
                    Picker("Slice Type", selection: $controller.sliceType) {
                        ForEach(SliceType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }

                    Picker("Drag Mode", selection: $controller.dragMode) {
                        ForEach(DragMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                if let volume = selectedVolume {
                    Section("Volume: \(volume.name)") {
                        ColormapPicker(
                            selection: Binding(
                                get: { volume.colormap },
                                set: { newColormap in
                                    Task {
                                        try? await controller.setColormap(
                                            for: volume,
                                            newColormap
                                        )
                                    }
                                }
                            )
                        )

                        IntensityRangeSlider(
                            range: Binding(
                                get: { volume.displayMin...volume.displayMax },
                                set: { newRange in
                                    Task {
                                        try? await controller.setIntensityRange(
                                            for: volume,
                                            min: newRange.lowerBound,
                                            max: newRange.upperBound
                                        )
                                    }
                                }
                            ),
                            bounds: volume.globalMin...volume.globalMax
                        )
                    }
                }
            }
        } detail: {
            NiivueView(controller: controller)
                .onVolumeLoaded { volume in
                    selectedVolume = volume
                }
        }
    }
}
```

### 12.5 Drawing and Segmentation

```swift
struct SegmentationTool: View {
    @StateObject private var controller = NiivueController()
    @State private var penColor = 1

    var body: some View {
        VStack {
            NiivueView(controller: controller)

            HStack {
                Picker("Label", selection: $penColor) {
                    Text("Erase").tag(0)
                    Text("Label 1").tag(1)
                    Text("Label 2").tag(2)
                    Text("Label 3").tag(3)
                }
                .onChange(of: penColor) { _, newValue in
                    controller.penValue = newValue
                }

                Button("Undo") {
                    Task { try? await controller.undoDrawing() }
                }

                Button("Clear") {
                    Task { try? await controller.clearDrawing() }
                }

                Button("Export") {
                    Task {
                        if let data = try? await controller.exportDrawing() {
                            // Save data...
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            controller.isDrawingEnabled = true
            controller.dragMode = .crosshair
        }
    }
}
```

### 12.6 Measurement Mode

```swift
struct MeasurementViewer: View {
    @StateObject private var controller = NiivueController()

    var body: some View {
        VStack {
            NiivueView(controller: controller)
                .onMeasurementComplete { measurement in
                    print("Distance: \(measurement.formattedDistance)")
                }

            HStack {
                Button("Distance") {
                    controller.dragMode = .measurement
                }

                Button("Angle") {
                    controller.dragMode = .angle
                }

                Button("Clear") {
                    Task {
                        try? await controller.clearMeasurements()
                        try? await controller.clearAngleMeasurements()
                    }
                }
            }

            List(controller.measurements) { measurement in
                HStack {
                    Image(systemName: "ruler")
                    Text(measurement.formattedDistance)
                }
            }
        }
    }
}
```

### 12.7 Combine Integration

```swift
import Combine

class ViewerCoordinator: ObservableObject {
    let controller = NiivueController()
    private var cancellables = Set<AnyCancellable>()

    @Published var currentPosition: WorldCoordinate?
    @Published var intensityAtCrosshair: Double?

    init() {
        // Debounce location updates
        controller.crosshairPositionPublisher
            .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
            .sink { [weak self] position in
                self?.currentPosition = position
            }
            .store(in: &cancellables)

        // React to volume loading
        controller.volumeLoadedPublisher
            .sink { volume in
                print("Volume loaded: \(volume.name)")
            }
            .store(in: &cancellables)
    }
}
```

### 12.8 UIKit Integration

```swift
import UIKit
import NiivueKit

class NeuroImageViewController: UIViewController, NiivueViewControllerDelegate {

    private var niivueVC: NiivueViewController!

    override func viewDidLoad() {
        super.viewDidLoad()

        niivueVC = NiivueViewController(
            configuration: .neuroimaging
        )
        niivueVC.delegate = self

        addChild(niivueVC)
        view.addSubview(niivueVC.view)
        niivueVC.view.frame = view.bounds
        niivueVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        niivueVC.didMove(toParent: self)

        // Load volume
        Task {
            try await niivueVC.controller.loadVolume(from: volumeURL)
        }
    }

    // MARK: - NiivueViewControllerDelegate

    func niivueViewController(
        _ viewController: NiivueViewController,
        didMoveCrosshairTo position: WorldCoordinate,
        voxel: VoxelCoordinate,
        values: [VolumeIntensityValue]
    ) {
        // Update coordinate display
        updateCoordinateLabel(position: position, voxel: voxel)

        // Update intensity display
        if let firstValue = values.first {
            updateIntensityLabel(value: firstValue.intensity)
        }
    }

    func niivueViewController(
        _ viewController: NiivueViewController,
        didEncounterError error: NiivueError
    ) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
```

---

## Appendix A: Migration from JavaScript API

| JavaScript | Swift |
|------------|-------|
| `nv.setSliceType(nv.sliceTypeMultiplanar)` | `controller.sliceType = .multiplanar` |
| `nv.loadVolumes([{url: 'brain.nii.gz'}])` | `try await controller.loadVolume(from: url)` |
| `nv.setColormap(nv.volumes[0].id, 'viridis')` | `try await controller.setColormap(for: volume, .viridis)` |
| `nv.volumes[0].cal_min = 0` | `try await controller.setIntensityRange(for: volume, min: 0, max: max)` |
| `nv.setDragMode(nv.dragModes.measurement)` | `controller.dragMode = .measurement` |
| `nv.onLocationChange = (data) => {...}` | `controller.onLocationChange = { event in ... }` |
| `nv.setRenderAzimuthElevation(120, 15)` | `try await controller.setViewOrientation(azimuth: 120, elevation: 15)` |
| `nv.drawUndo()` | `try await controller.undoDrawing()` |
| `nv.setPenValue(2, false)` | `controller.penValue = 2` |

---

## Appendix B: Supported File Formats

### Volumes
- NIfTI (.nii, .nii.gz)
- NRRD (.nrrd, .nhdr)
- MGH/MGZ (.mgh, .mgz)
- AFNI (.HEAD/.BRIK)
- ITK MetaImage (.mhd/.raw)
- DICOM (via dcm2niix conversion)
- ECAT7 (.v)
- DSI Studio (.fib.gz)

### Meshes
- GIfTI (.gii)
- FreeSurfer (.pial, .white, .inflated)
- PLY (.ply)
- STL (.stl)
- OBJ (.obj)
- VTK (.vtk)
- MZ3 (.mz3)

### Tractography
- TCK (.tck) - MRtrix
- TRK (.trk) - TrackVis
- TRX (.trx) - BIDS
- TT (.tt) - 3D Slicer

---

*This API design document is version 1.0.0. For updates and implementation status, see the NiivueKit repository.*
