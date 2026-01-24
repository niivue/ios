# NiivueKit

<p align="center">
  <img src="assets/niivuekit-logo.png" alt="NiivueKit Logo" width="200"/>
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift 6.0"></a>
  <a href="https://developer.apple.com/ios/"><img src="https://img.shields.io/badge/iOS-15.0+-blue.svg" alt="iOS 15.0+"></a>
  <a href="https://developer.apple.com/visionos/"><img src="https://img.shields.io/badge/visionOS-1.0+-purple.svg" alt="visionOS 1.0+"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-BSD--2--Clause-green.svg" alt="License"></a>
  <a href="https://github.com/niivue/niivue-ios-foundation/releases"><img src="https://img.shields.io/github/v/release/niivue/niivue-ios-foundation" alt="Release"></a>
</p>

**NiivueKit** is a powerful Swift SDK for bringing WebGL-accelerated neuroimaging visualization to iOS and visionOS applications. Built on top of the popular [Niivue](https://github.com/niivue/niivue) library, NiivueKit provides native Swift APIs for loading, rendering, and manipulating medical imaging data including NIfTI volumes, DICOM series, 3D meshes, and tractography.

---

## ✨ Features

### 🧠 Medical Imaging Formats
- **Volume Data**: NIfTI (.nii, .nii.gz), NRRD, MGH/MGZ, AFNI, ITK MHD
- **DICOM**: Direct import with automatic conversion via WebAssembly-powered dcm2niix
- **3D Meshes**: GIfTI, FreeSurfer, PLY, STL, OBJ, VTK
- **Tractography**: TCK, TRK, TRX formats

### 🎨 Visualization
- WebGL 2.0-accelerated rendering
- Multiplanar reconstruction (Axial, Coronal, Sagittal)
- 3D volume rendering with azimuth/elevation control
- 250+ scientific colormaps
- Customizable crosshairs and orientation indicators

### ✏️ Interactive Tools
- Drawing and segmentation tools
- Click-to-segment with volume calculation
- Undo/redo support for annotations
- Export drawings as NIfTI volumes

### 📱 iOS-Native Integration
- SwiftUI and UIKit compatible
- Gesture-driven navigation (pinch, pan, rotate)
- Document picker integration for file import
- Session save/restore with state preservation
- Actor-based thread safety

---

## 🚀 Quick Start (5 Minutes)

### 1. Add NiivueKit to Your Project

**Swift Package Manager** (Recommended):

```swift
dependencies: [
    .package(url: "https://github.com/niivue/niivue-ios-foundation.git", from: "1.0.0")
]
```

Then add `NiivueKit` to your target dependencies:

```swift
.target(
    name: "YourApp",
    dependencies: ["NiivueKit"]
)
```

### 2. Import and Initialize

**SwiftUI Example:**

```swift
import SwiftUI
import NiivueKit

struct ContentView: View {
    @StateObject private var webViewManager = WebViewManager()

    var body: some View {
        VStack {
            if webViewManager.isReady {
                NiivueWebView(manager: webViewManager)
                    .edgesIgnoringSafeArea(.all)
            } else {
                ProgressView("Loading NiivueKit...")
            }
        }
        .task {
            // Load a sample volume
            try? await webViewManager.loadVolumeFromURL(
                "https://niivue.github.io/niivue-demo-images/mni152.nii.gz"
            )
        }
    }
}
```

**UIKit Example:**

```swift
import UIKit
import NiivueKit

class ViewController: UIViewController {
    private var webViewManager: WebViewManager!

    override func viewDidLoad() {
        super.viewDidLoad()

        webViewManager = WebViewManager()

        // Add the WKWebView to your view hierarchy
        let webView = webViewManager.webView
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Load initial data
        Task { @MainActor in
            try await webViewManager.loadVolumeFromURL(
                "https://niivue.github.io/niivue-demo-images/mni152.nii.gz"
            )
        }
    }
}
```

### 3. Load Your First Volume

```swift
// From a remote URL
try await webViewManager.loadVolumeFromURL("https://example.com/brain.nii.gz")

// From a local file
try await webViewManager.loadVolumeFromFile(fileURL)

// From base64-encoded data
try await webViewManager.loadVolumeFromBase64(base64String, name: "scan.nii")
```

### 4. Control the Visualization

```swift
// Change view mode
try await webViewManager.setSliceType(.multiplanar)

// Adjust colormap
try await webViewManager.setColormap(volumeId: "vol1", colormap: "hot")

// Set opacity for overlay blending
try await webViewManager.setOpacity(volumeId: "vol1", opacity: 0.5)

// Move crosshair to specific voxel
try await webViewManager.setCrosshairPosition(voxel: SIMD3<Int>(128, 128, 64))
```

That's it! You now have a fully functional neuroimaging viewer in your iOS app.

---

## 📋 Requirements

| Component | Minimum Version | Recommended |
|-----------|----------------|-------------|
| **iOS** | 15.0+ | 17.0+ |
| **visionOS** | 1.0+ | 2.0+ |
| **Swift** | 6.0+ | 6.0+ |
| **Xcode** | 16.0+ | 16.0+ |
| **Device Memory** | 2GB RAM | 4GB+ RAM |

**Note**: NiivueKit requires WebGL 2.0 support, which is available in Safari 15+ (iOS 15+).

---

## 📦 Installation

### Swift Package Manager

Add NiivueKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/niivue/niivue-ios-foundation.git", from: "1.0.0")
]
```

Or in Xcode:
1. File > Add Package Dependencies
2. Enter: `https://github.com/niivue/niivue-ios-foundation.git`
3. Select version rule (e.g., "Up to Next Major Version")
4. Click "Add Package"

### CocoaPods

```ruby
pod 'NiivueKit', '~> 1.0'
```

### Carthage

```
github "niivue/niivue-ios-foundation" ~> 1.0
```

---

## 📚 Documentation

### Guides
- [**Getting Started Tutorial**](Documentation/GettingStarted.md) - Build your first neuroimaging app
- [**Loading Volumes**](Documentation/LoadingVolumes.md) - All volume loading methods
- [**DICOM Import Guide**](Documentation/DicomImport.md) - Working with DICOM series
- [**Drawing Tools**](Documentation/DrawingTools.md) - Segmentation and annotations
- [**API Reference**](https://niivue.github.io/niivue-ios-foundation/documentation/niivuekit/) - Full API documentation (DocC)

### Migration & Troubleshooting
- [**Migration Guide**](Documentation/MigrationGuide.md) - Upgrading from WKWebView to NiivueKit
- [**Troubleshooting**](Documentation/Troubleshooting.md) - Common issues and solutions
- [**FAQ**](Documentation/FAQ.md) - Frequently asked questions

### Example Projects
- [**Minimal SwiftUI Example**](Examples/MinimalSwiftUI/) - Simplest possible implementation
- [**UIKit Integration**](Examples/UIKitIntegration/) - UIKit-based viewer
- [**DICOM Viewer**](Examples/DicomViewer/) - Complete DICOM import workflow
- [**Advanced Features**](Examples/AdvancedFeatures/) - Drawing, sessions, multi-volume rendering

---

## 🎯 Use Cases

### Clinical Applications
- **Surgical Planning**: Pre-operative volume rendering and measurement
- **Radiology Review**: DICOM series viewing with multiplanar reconstruction
- **Patient Education**: Interactive 3D brain anatomy visualization

### Research Tools
- **Neuroimaging Analysis**: On-device viewing of fMRI/DTI results
- **Tractography Visualization**: White matter pathway rendering
- **Atlas Overlay**: Compare individual scans with reference atlases

### Educational Apps
- **Medical Student Training**: Interactive neuroanatomy exploration
- **Patient Portals**: Personal medical imaging access
- **STEM Education**: 3D visualization of biological structures

---

## 🛠️ Core Components

### WebViewManager
The main interface to NiivueKit. Manages the WKWebView and provides type-safe Swift APIs:

```swift
@MainActor
final class WebViewManager: ObservableObject {
    @Published var isReady: Bool
    @Published var volumes: [VolumeInfo]
    @Published var lastLocationString: String?

    // Volume loading
    func loadVolumeFromURL(_ url: String) async throws
    func loadVolumeFromFile(_ fileURL: URL) async throws
    func loadVolumeFromBase64(_ base64: String, name: String) async throws

    // Visualization control
    func setSliceType(_ type: SliceType) async throws
    func setColormap(volumeId: String, colormap: String) async throws
    func setOpacity(volumeId: String, opacity: Double) async throws

    // Drawing tools
    func setPenValue(_ value: UInt8, isFilled: Bool) async throws
    func setDrawOpacity(_ opacity: Double) async throws
    func saveDrawing() async throws -> Data
}
```

### DicomSeriesStore
Actor-based thread-safe DICOM file management:

```swift
actor DicomSeriesStore {
    func register(files: [URL]) -> String
    func manifestText(for seriesId: String) -> String
    func url(for seriesId: String, fileName: String) -> URL?
}
```

### SessionStore
Persistent session management with state restoration:

```swift
actor SessionStore {
    func save(snapshot: SessionSnapshotV1) async throws
    func load() async throws -> SessionSnapshotV1?
    func delete() async throws
}
```

---

## 🔬 Advanced Features

### DICOM Import with Automatic Conversion

```swift
// Import DICOM series from document picker
@State private var showingDicomPicker = false

Button("Import DICOM Series") {
    showingDicomPicker = true
}
.fileImporter(
    isPresented: $showingDicomPicker,
    allowedContentTypes: [.data],
    allowsMultipleSelection: true
) { result in
    Task {
        let urls = try result.get()
        let seriesId = await dicomStore.register(files: urls)
        try await webViewManager.loadDicomSeriesFromManifestURL(
            "niivue://app/dicom/\(seriesId)/niivue-manifest.txt"
        )
    }
}
```

### Drawing and Segmentation

```swift
// Enable drawing mode
try await webViewManager.setPenValue(1, isFilled: false)
try await webViewManager.setDrawOpacity(0.5)

// Save drawing as NIfTI
let drawingData = try await webViewManager.saveDrawing()
let documentURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let outputURL = documentURL.appendingPathComponent("segmentation.nii.gz")
try drawingData.write(to: outputURL)
```

### Session Persistence

```swift
// Save current state
let snapshot = SessionSnapshotV1(
    volumeSources: webViewManager.volumeSources,
    sliceType: currentSliceType,
    multiplanarLayout: currentLayout
)
try await sessionStore.save(snapshot: snapshot)

// Restore on next launch
if let snapshot = try await sessionStore.load() {
    for source in snapshot.volumeSources {
        try await webViewManager.loadVolume(from: source)
    }
    try await webViewManager.setSliceType(snapshot.sliceType)
    try await webViewManager.setMultiplanarLayout(snapshot.multiplanarLayout)
}
```

---

## 🧪 Testing

NiivueKit includes comprehensive test coverage:

```bash
# Run all tests
xcodebuild test -scheme NiivueKit -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

# Run specific test suite
xcodebuild test -only-testing:NiivueKitTests/WebViewManagerTests

# Run UI tests
xcodebuild test -scheme NiivueKit -only-testing:NiivueKitUITests
```

Current test coverage:
- **Unit Tests**: 77 tests covering all major components
- **UI Tests**: Accessibility identifier validation
- **Integration Tests**: End-to-end volume loading workflows

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
git clone https://github.com/niivue/niivue-ios-foundation.git
cd niivue-ios-foundation
open NiiVue.xcodeproj
```

Run tests before submitting PRs:

```bash
npm run test:swift  # Swift unit tests
npm run test:js     # JavaScript bridge tests
```

---

## 📄 License

NiivueKit is released under the BSD 2-Clause License. See [LICENSE](LICENSE) for details.

The underlying Niivue library is also BSD-2-Clause licensed.

---

## 🙏 Acknowledgments

- **Niivue Team**: For the excellent WebGL neuroimaging library
- **@niivue/dicom-loader**: WASM-based DICOM conversion
- **dcm2niix**: DICOM to NIfTI conversion tool

---

## 📞 Support

- **Documentation**: [https://niivue.github.io/niivue-ios-foundation/](https://niivue.github.io/niivue-ios-foundation/)
- **Issue Tracker**: [GitHub Issues](https://github.com/niivue/niivue-ios-foundation/issues)
- **Discussions**: [GitHub Discussions](https://github.com/niivue/niivue-ios-foundation/discussions)
- **Email**: support@niivue.com

---

## 🗺️ Roadmap

### Version 1.1 (Q2 2026)
- [ ] Mesh property controls (opacity, shader selection)
- [ ] Tractography rendering enhancements
- [ ] Distance and angle measurement tools
- [ ] Custom clip plane controls

### Version 1.2 (Q3 2026)
- [ ] Intensity windowing UI (cal_min/cal_max)
- [ ] Volume removal and reordering APIs
- [ ] 3D gesture controls (azimuth/elevation)
- [ ] Enhanced DICOM series detection

### Version 2.0 (Q4 2026)
- [ ] visionOS spatial computing optimizations
- [ ] Metal rendering backend option
- [ ] Offline NIfTI caching for DICOM imports
- [ ] Multi-viewer synchronization

See [CHANGELOG.md](CHANGELOG.md) for version history.

---

<p align="center">
  Made with ❤️ for the neuroimaging community
</p>
