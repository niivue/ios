# NiivueKit Swift Package Manager Design

## Executive Summary

This document defines the complete Swift Package Manager (SPM) structure for **NiivueKit**, a Swift SDK that wraps the Niivue neuroimaging visualization library. The package bundles a React application (built JS/CSS/HTML), WebAssembly modules (dcm2niix for DICOM processing), and Swift source files into a distributable framework.

## Package.swift Configuration

```swift
// swift-tools-version: 5.9
// Requires Swift 5.9+ for modern resource bundling and concurrency features

import PackageDescription

let package = Package(
    name: "NiivueKit",

    // MARK: - Platform Support
    platforms: [
        .iOS(.v16),        // iOS 16+ required for WebGL 2.0 + WKWebView enhancements
        .macCatalyst(.v16), // Mac Catalyst support for Apple Silicon Macs
        .visionOS(.v1)      // visionOS support (future WebXR compatibility)
    ],

    // MARK: - Products
    products: [
        // Main library product - what consumers will import
        .library(
            name: "NiivueKit",
            targets: ["NiivueKit"]
        )
    ],

    // MARK: - Dependencies
    dependencies: [
        // No external SPM dependencies required
        // The package is self-contained with bundled resources
    ],

    // MARK: - Targets
    targets: [
        // Main target containing all Swift code and resources
        .target(
            name: "NiivueKit",
            dependencies: [],
            resources: [
                // React application build output (JS/CSS/HTML)
                .copy("Resources/dist"),

                // Sample neuroimaging files for demos/testing
                .copy("Resources/samples"),

                // WebAssembly modules (dcm2niix)
                // Already included in dist/assets/ from Vite build
            ],
            swiftSettings: [
                // Enable strict concurrency checking
                .enableUpcomingFeature("StrictConcurrency"),

                // Enable actor isolation checking
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),

        // Test target
        .testTarget(
            name: "NiivueKitTests",
            dependencies: ["NiivueKit"],
            resources: [
                // Test fixtures (small test volumes)
                .copy("Resources/Fixtures")
            ]
        )
    ],

    // MARK: - Swift Language Version
    swiftLanguageVersions: [.v5]
)
```

## Directory Structure

```
NiivueKit/
├── Package.swift                           # SPM manifest (above)
├── README.md                               # Package documentation
├── LICENSE                                 # MIT or Apache 2.0
├── CHANGELOG.md                            # Version history
│
├── Sources/
│   └── NiivueKit/
│       ├── NiivueKit.swift                 # Public API entry point
│       │
│       ├── Core/                           # Core WebView management
│       │   ├── WebViewManager.swift        # Main Niivue WebView controller
│       │   ├── JavaScriptEvaluating.swift  # JS evaluation protocol
│       │   └── JavaScriptQuote.swift       # Safe JS string escaping
│       │
│       ├── Networking/                     # Custom URL scheme handling
│       │   ├── NiivueURLSchemeHandler.swift # WKURLSchemeHandler implementation
│       │   └── NiivueURLRouter.swift       # URL routing logic
│       │
│       ├── Services/                       # Business logic services
│       │   ├── FileImportService.swift     # File import/management
│       │   ├── ImportedFileStore.swift     # Imported file registry
│       │   ├── DicomSeriesStore.swift      # DICOM series management
│       │   ├── DrawingExportService.swift  # Drawing export utilities
│       │   ├── SessionStore.swift          # Session persistence
│       │   ├── SessionSnapshotV1.swift     # Session snapshot model
│       │   └── Base64FileEncoder.swift     # Legacy base64 encoding
│       │
│       ├── Extensions/                     # Swift extensions
│       │   └── WKWebView+JavaScriptEvaluating.swift
│       │
│       ├── Models/                         # Data models
│       │   ├── VolumeInfo.swift           # Volume metadata
│       │   └── SharedData.swift           # Shared state models
│       │
│       └── Resources/                     # Bundled resources
│           ├── dist/                      # React app build output
│           │   ├── index.html
│           │   └── assets/
│           │       ├── index-[hash].js    # Main React bundle
│           │       ├── index-[hash].css   # Styles
│           │       ├── dcm2niix.jpeg-[hash].wasm  # DICOM converter
│           │       ├── blosc-[hash].js    # Compression codecs
│           │       ├── lz4-[hash].js
│           │       ├── zstd-[hash].js
│           │       └── [fonts/images]     # Additional assets
│           │
│           └── samples/                   # Sample neuroimaging files
│               └── T1w_DEMO.nii.gz        # Demo brain scan
│
├── Tests/
│   └── NiivueKitTests/
│       ├── Core/
│       │   ├── WebViewManagerTests.swift
│       │   ├── WebViewManagerStateTests.swift
│       │   ├── WebViewManagerCommandTests.swift
│       │   ├── JavaScriptEvaluatingTests.swift
│       │   └── JavaScriptQuoteTests.swift
│       │
│       ├── Networking/
│       │   └── NiivueURLRouterTests.swift
│       │
│       ├── Services/
│       │   ├── FileImportServiceTests.swift
│       │   ├── DicomSeriesStoreTests.swift
│       │   ├── DrawingExportServiceTests.swift
│       │   ├── SessionStoreTests.swift
│       │   └── Base64FileEncoderTests.swift
│       │
│       ├── Commands/                      # Command-specific tests
│       │   ├── OverlayCommandTests.swift
│       │   ├── TimeSeriesCommandTests.swift
│       │   ├── SegmentationCommandTests.swift
│       │   └── DicomCommandTests.swift
│       │
│       ├── Mocks/
│       │   └── MockJavaScriptEvaluator.swift
│       │
│       └── Resources/
│           └── Fixtures/
│               ├── ui-test-volume-1.nii   # Minimal test volumes
│               └── ui-test-volume-2.nii
│
└── Documentation/
    ├── GettingStarted.md                  # Integration guide
    ├── API_Reference.md                   # API documentation
    ├── Architecture.md                    # Technical architecture
    └── Migration.md                       # Migration guide
```

## Resource Bundling Strategy

### 1. Bundle.module Access Pattern

SPM automatically creates a `Bundle.module` extension for accessing package resources:

```swift
// In NiivueURLSchemeHandler.swift
private func serveDistFile(path: String, task: WKURLSchemeTask) {
    // SPM pattern: Use Bundle.module instead of Bundle.main
    guard let resourceURL = Bundle.module.resourceURL else {
        task.didFailWithError(HandlerError.fileNotFound)
        return
    }

    let fileURL = resourceURL
        .appendingPathComponent("dist")
        .appendingPathComponent(path)
    serveFile(at: fileURL, task: task)
}

private func serveSampleFile(path: String, task: WKURLSchemeTask) {
    guard let resourceURL = Bundle.module.resourceURL else {
        task.didFailWithError(HandlerError.fileNotFound)
        return
    }

    let fileURL = resourceURL
        .appendingPathComponent("samples")
        .appendingPathComponent(path)
    serveFile(at: fileURL, task: task)
}
```

### 2. Resource Organization

- **`.copy("Resources/dist")`**: Preserves directory structure for React build output
  - Critical for relative asset paths in Vite-generated HTML/JS
  - Maintains hash-based filenames for cache busting

- **`.copy("Resources/samples")`**: Preserves binary neuroimaging files
  - NIfTI files are binary and must not be processed
  - Maintains .gz compression

### 3. WASM File Handling

WebAssembly modules are already bundled in the `dist/assets/` directory by Vite:
- `dcm2niix.jpeg-[hash].wasm` - DICOM to NIfTI converter
- No special SPM handling required - served via WKURLSchemeHandler like other assets

### 4. Build Phase Considerations

When integrating NiivueKit into an app:
1. SPM automatically copies resources into the framework bundle
2. Resources are accessible via `Bundle.module` at runtime
3. No manual build phase scripts required
4. WKWebView loads via custom `niivue://` scheme handled by `NiivueURLSchemeHandler`

## Platform Support Details

### iOS 16+ (Primary Target)

**Minimum iOS 16 rationale:**
- WebGL 2.0 support (stable since iOS 15, but iOS 16 has critical bug fixes)
- WKWebView JavaScript evaluation improvements
- Swift Concurrency enhancements (async/await maturity)
- SwiftUI 4.0 features if used in consumer apps

**Required capabilities:**
```swift
// In Package.swift platforms array
.iOS(.v16)
```

### macOS Catalyst (Mac Support)

**Mac Catalyst support:**
- Enables iPad apps to run on Apple Silicon Macs
- Full WebGL 2.0 support on macOS 11+
- Same codebase, no platform-specific code required

**Platform declaration:**
```swift
.macCatalyst(.v16) // Aligned with iOS 16
```

**Conditional compilation (if needed):**
```swift
#if targetEnvironment(macCatalyst)
// Mac-specific optimizations (e.g., window sizing)
#endif
```

### visionOS 1.0+ (Future WebXR)

**visionOS support:**
- Forward compatibility for spatial computing
- WebGL/WebGPU rendering in immersive views
- Potential WebXR integration for 3D medical visualization

**Platform declaration:**
```swift
.visionOS(.v1)
```

**Conditional compilation:**
```swift
#if os(visionOS)
// visionOS-specific features (e.g., spatial window placement)
#endif
```

### Unsupported Platforms

- **watchOS**: Excluded (no WKWebView support)
- **tvOS**: Excluded (limited WebGL support, no medical use case)
- **macOS (non-Catalyst)**: Not initially supported
  - Could be added later with AppKit WKWebView integration
  - Would require separate target or extensive `#if os(macOS)` conditionals

## Versioning Strategy

### Semantic Versioning Approach

NiivueKit follows **strict semantic versioning (SemVer 2.0.0)**:

```
MAJOR.MINOR.PATCH

Examples:
1.0.0 - Initial release
1.1.0 - Add visionOS support (new feature, backward compatible)
1.1.1 - Fix WASM loading bug (backward compatible fix)
2.0.0 - Breaking change to WebViewManager API
```

### Version Components

**MAJOR version** (breaking changes):
- Changes to public API that require consumer code changes
- Removal of deprecated APIs
- Changes to Swift concurrency patterns (e.g., adding `@MainActor` to public types)
- Minimum platform version bumps (e.g., iOS 16 → iOS 17)
- Example: `WebViewManager.loadImage()` → `WebViewManager.loadVolume()`

**MINOR version** (new features):
- New public APIs (backward compatible)
- New platform support (e.g., visionOS)
- New neuroimaging format support
- Performance improvements
- Example: Adding `exportSessionSnapshotJSON()` method

**PATCH version** (bug fixes):
- Bug fixes that don't change API
- Documentation updates
- Internal refactoring (no public API changes)
- WASM module updates (if no API changes)
- Example: Fixing memory leak in URL scheme handler

### Bundled Asset Versioning

**React/WASM asset versions:**
- Tracked in `CHANGELOG.md` but NOT in package version
- Asset updates that don't change Swift API = PATCH version
- Asset updates that ADD new capabilities = MINOR version
- Asset updates that REMOVE capabilities = MAJOR version

**Example versioning scenarios:**

| Change | Swift API Impact | Version Bump | Rationale |
|--------|------------------|--------------|-----------|
| Update dcm2niix.wasm (same API) | None | PATCH (1.0.0 → 1.0.1) | Internal dependency update |
| Update Niivue.js (new colormap) | None | PATCH (1.0.1 → 1.0.2) | New feature, but no Swift API change |
| Add `setColormap()` Swift method | New public API | MINOR (1.0.2 → 1.1.0) | Backward compatible API addition |
| Change `loadImage()` signature | Breaking change | MAJOR (1.1.0 → 2.0.0) | Requires consumer code changes |

### Git Tagging Strategy

```bash
# Release tags follow vX.Y.Z format
git tag -a v1.0.0 -m "Release 1.0.0 - Initial public release"
git tag -a v1.1.0 -m "Release 1.1.0 - Add visionOS support"

# Pre-release versions
git tag -a v2.0.0-beta.1 -m "Release 2.0.0 Beta 1"
git tag -a v2.0.0-rc.1 -m "Release 2.0.0 Release Candidate 1"
```

### Package.swift Version Declaration

SPM packages don't declare their own version in `Package.swift`. Instead:

1. **Git tags** define versions (e.g., `v1.0.0`, `v1.1.0`)
2. **Consumers** specify version requirements:

```swift
// In consumer app's Package.swift
dependencies: [
    .package(url: "https://github.com/niivue/NiivueKit.git", from: "1.0.0"),
    // or
    .package(url: "https://github.com/niivue/NiivueKit.git", .upToNextMajor(from: "1.0.0")),
    // or
    .package(url: "https://github.com/niivue/NiivueKit.git", exact: "1.0.0")
]
```

### Breaking Change Policy

**Deprecation cycle:**
1. Add `@available` deprecation warning in MINOR version
2. Remove deprecated API in next MAJOR version

**Example:**
```swift
// v1.5.0 - Deprecate old method
@available(*, deprecated, renamed: "loadVolume(from:)")
func loadImage(from url: URL) async throws {
    try await loadVolume(from: url)
}

func loadVolume(from url: URL) async throws {
    // New implementation
}

// v2.0.0 - Remove deprecated method
// loadImage() is completely removed
```

### CHANGELOG.md Format

```markdown
# Changelog

All notable changes to NiivueKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- (pending changes)

### Changed
- (pending changes)

### Deprecated
- (pending changes)

### Removed
- (pending changes)

### Fixed
- (pending changes)

### Security
- (pending changes)

## [1.1.0] - 2026-02-01

### Added
- visionOS platform support
- `exportSessionSnapshotJSON()` method for session persistence
- Sample neuroimaging file (`T1w_DEMO.nii.gz`)

### Changed
- Updated Niivue.js to v0.45.0 (bundled in dist/)
- Improved WASM loading performance

### Fixed
- Fixed memory leak in `NiivueURLSchemeHandler`
- Fixed race condition in volume loading

## [1.0.0] - 2026-01-15

### Added
- Initial public release
- Swift Package Manager distribution
- iOS 16+ and macOS Catalyst support
- React app bundling (Vite build)
- WebAssembly DICOM converter (dcm2niix)
- Custom `niivue://` URL scheme for resource loading
- Comprehensive test suite
```

## Target Structure Rationale

### Single Target Approach

**Decision: Use a single `NiivueKit` target** (not splitting into Core/UI/DICOM)

**Rationale:**
1. **Tight coupling**: WebView, URL scheme handler, and services are deeply interdependent
2. **Simplicity**: Single import statement for consumers (`import NiivueKit`)
3. **Resource bundling**: All resources (dist/, samples/) are accessed from one bundle
4. **Binary size**: No benefit to splitting - consumers get same binary size either way
5. **API surface**: Not enough public API to justify modularization

**Alternative considered (rejected):**
```swift
// REJECTED: Over-engineered for initial release
.library(name: "NiivueKitCore", targets: ["NiivueKitCore"])
.library(name: "NiivueKitUI", targets: ["NiivueKitUI"])
.library(name: "NiivueKitDICOM", targets: ["NiivueKitDICOM"])
```

### Future Modularization Trigger

If the package grows to include:
- Standalone DICOM processing (without WebView)
- SwiftUI view components separate from core engine
- Command-line tools

Then consider splitting into:
```swift
targets: [
    .target(name: "NiivueKitCore"),     // Core WebView + JS bridge
    .target(name: "NiivueKitUI"),       // SwiftUI components
    .target(name: "NiivueKitDICOM"),    // DICOM utilities
]
```

## Public API Design

### Minimal Public Surface

**Public types (exposed to consumers):**
```swift
// Core types
public final class WebViewManager { }
public protocol JavaScriptEvaluating { }

// Service types
public struct FileImportService { }
public struct ImportedFileStore { }
public struct DicomSeriesStore { }
public struct SessionStore { }

// Model types
public struct VolumeInfo: Codable { }
public struct SessionSnapshotV1: Codable { }
```

**Internal types (package-private):**
```swift
// URL handling
internal final class NiivueURLSchemeHandler { }
internal struct NiivueURLRouter { }

// Utilities
internal enum JavaScriptQuote { }
internal struct Base64FileEncoder { }
```

### Access Control Strategy

```swift
// NiivueKit.swift - Public API entry point

/// The main entry point for NiivueKit.
///
/// NiivueKit wraps the Niivue neuroimaging visualization library,
/// providing a native Swift API for medical image rendering in iOS apps.
///
/// ## Topics
/// ### Core Components
/// - ``WebViewManager``
/// - ``JavaScriptEvaluating``
///
/// ### File Management
/// - ``FileImportService``
/// - ``ImportedFileStore``
///
/// ### DICOM Support
/// - ``DicomSeriesStore``
///
/// ### Session Persistence
/// - ``SessionStore``
/// - ``SessionSnapshotV1``
///
/// ### Models
/// - ``VolumeInfo``
public enum NiivueKit {
    /// The current version of NiivueKit.
    public static let version = "1.0.0"

    /// The bundled Niivue.js version.
    public static let niivueVersion = "0.45.0"

    /// The bundled dcm2niix WASM version.
    public static let dcm2niixVersion = "1.0.20220720"
}
```

## Testing Strategy

### Unit Tests

**Coverage targets:**
- 80%+ code coverage for public APIs
- 100% coverage for critical paths (file import, JS evaluation, URL routing)

**Test isolation:**
- Use `MockJavaScriptEvaluator` to avoid WKWebView dependency
- Test resources in `Tests/Resources/Fixtures/`
- XCTest framework (no third-party dependencies)

### Integration Tests

**Testing with real WKWebView:**
```swift
// Example integration test
@MainActor
final class WebViewManagerIntegrationTests: XCTestCase {
    var manager: WebViewManager!

    override func setUp() async throws {
        manager = WebViewManager()
        manager.load()

        // Wait for WebView to finish loading
        try await waitForReady(timeout: 10.0)
    }

    func testLoadSampleVolume() async throws {
        let sampleURL = "niivue://app/samples/T1w_DEMO.nii.gz"
        try await manager.loadImageFromUrl(url: sampleURL, fileName: "T1w_DEMO.nii.gz")

        XCTAssertEqual(manager.volumes.count, 1)
        XCTAssertEqual(manager.volumes[0].name, "T1w_DEMO.nii.gz")
    }
}
```

### Test Fixtures

**Minimal test volumes:**
- `ui-test-volume-1.nii` (360 bytes) - Simple 3D volume
- `ui-test-volume-2.nii` (360 bytes) - Second volume for overlay tests

**Rationale:** Keep package size minimal; full datasets tested in consumer apps

## Migration from Xcode Project

### Current State (Xcode App Target)

```
NiiVue.xcodeproj
└── NiiVue (iOS App)
    ├── Sources/*.swift
    ├── Resources/dist/
    └── Resources/samples/
```

### Transition Steps

1. **Create SPM Package Structure**
   ```bash
   mkdir NiivueKit
   cd NiivueKit
   swift package init --type library
   ```

2. **Copy Source Files**
   ```bash
   # Copy Swift sources
   cp -r ../NiiVue/NiiVue/Web Sources/NiivueKit/Core/
   cp -r ../NiiVue/NiiVue/Services Sources/NiivueKit/Services/

   # Copy resources
   cp -r ../NiiVue/React/dist Sources/NiivueKit/Resources/dist
   cp -r ../NiiVue/NiiVue/samples Sources/NiivueKit/Resources/samples
   ```

3. **Update Code for SPM**
   - Change `Bundle.main` → `Bundle.module`
   - Add public/internal access modifiers
   - Remove app-specific code (NiiVueApp.swift, ContentView.swift)

4. **Create Tests**
   ```bash
   cp -r ../NiiVue/NiiVueTests Tests/NiivueKitTests
   ```

5. **Test SPM Build**
   ```bash
   swift build
   swift test
   ```

6. **Create Example App**
   - Separate Xcode project that imports NiivueKit via SPM
   - Demonstrates integration
   - Uses ContentView.swift as reference

### Bundle.main → Bundle.module Changes

**Before (Xcode app):**
```swift
// NiivueURLSchemeHandler.swift
guard let resourceURL = Bundle.main.resourceURL else {
    task.didFailWithError(HandlerError.fileNotFound)
    return
}
```

**After (SPM package):**
```swift
// NiivueURLSchemeHandler.swift
guard let resourceURL = Bundle.module.resourceURL else {
    task.didFailWithError(HandlerError.fileNotFound)
    return
}
```

**Compatibility layer (if needed):**
```swift
extension Bundle {
    static var niivueResources: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }
}
```

## Distribution Strategy

### GitHub Repository Structure

```
niivue/NiivueKit (GitHub repo)
├── Package.swift
├── Sources/...
├── Tests/...
├── README.md
├── LICENSE
├── CHANGELOG.md
├── .github/
│   └── workflows/
│       ├── ci.yml           # Run tests on PR
│       ├── release.yml      # Create GitHub release on tag
│       └── docs.yml         # Generate DocC documentation
└── Examples/
    └── NiivueKitExample/    # Example Xcode project
        └── NiivueKitExample.xcodeproj
```

### GitHub Actions CI

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode
        run: sudo xcode-select -s /Applications/Xcode_15.2.app

      - name: Build
        run: swift build

      - name: Run tests
        run: swift test --enable-code-coverage

      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

### Consumer Integration

**Add to Xcode project:**
1. File → Add Package Dependencies
2. Enter URL: `https://github.com/niivue/NiivueKit.git`
3. Version rule: "Up to Next Major Version" (1.0.0 < 2.0.0)

**Add to Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/niivue/NiivueKit.git", from: "1.0.0")
],
targets: [
    .target(
        name: "MyApp",
        dependencies: ["NiivueKit"]
    )
]
```

## Documentation Generation

### DocC Documentation

**Generate documentation:**
```bash
# Generate DocC archive
swift package generate-documentation \
  --target NiivueKit \
  --output-path ./docs

# Preview documentation
swift package --disable-sandbox preview-documentation \
  --target NiivueKit
```

**Host on GitHub Pages:**
```yaml
# .github/workflows/docs.yml
name: Documentation

on:
  push:
    branches: [ main ]
    tags: [ 'v*' ]

jobs:
  build-docs:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Generate Documentation
        run: |
          swift package generate-documentation \
            --target NiivueKit \
            --output-path ./docs \
            --hosting-base-path NiivueKit

      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs
```

### README.md Structure

```markdown
# NiivueKit

Swift Package for neuroimaging visualization on iOS, macOS Catalyst, and visionOS.

## Features

- WebGL 2.0 neuroimaging visualization
- Support for NIfTI, DICOM, and other medical imaging formats
- Built-in DICOM to NIfTI conversion (WebAssembly)
- Drawing and segmentation tools
- Session persistence
- Offline operation (no network required)

## Requirements

- iOS 16.0+ / macOS 13.0+ (Catalyst) / visionOS 1.0+
- Xcode 15.0+
- Swift 5.9+

## Installation

### Swift Package Manager

Add NiivueKit to your `Package.swift`:

\`\`\`swift
dependencies: [
    .package(url: "https://github.com/niivue/NiivueKit.git", from: "1.0.0")
]
\`\`\`

Or add it via Xcode:
1. File → Add Package Dependencies
2. Enter: `https://github.com/niivue/NiivueKit.git`

## Quick Start

\`\`\`swift
import SwiftUI
import NiivueKit

struct ContentView: View {
    @StateObject private var manager = WebViewManager()

    var body: some View {
        NiivueWebView(manager: manager)
            .onAppear {
                manager.load()
            }
            .task {
                // Load sample volume
                try? await manager.loadImageFromUrl(
                    url: "niivue://app/samples/T1w_DEMO.nii.gz",
                    fileName: "T1w_DEMO.nii.gz"
                )
            }
    }
}
\`\`\`

## Documentation

- [Getting Started Guide](Documentation/GettingStarted.md)
- [API Reference](https://niivue.github.io/NiivueKit)
- [Architecture Overview](Documentation/Architecture.md)

## License

MIT License - see [LICENSE](LICENSE)
```

## Dependency Management

### No External SPM Dependencies

**Decision: Zero external SPM dependencies**

**Rationale:**
1. **Self-contained**: All functionality in bundled JS/WASM
2. **Stability**: No risk of dependency conflicts
3. **Binary size**: No bloat from unused transitive dependencies
4. **Build speed**: Faster builds without external fetches

### Bundled Dependencies (in React dist/)

These are NOT SPM dependencies - they're bundled in the React build:

- **Niivue.js** (v0.45.0) - Neuroimaging visualization
- **dcm2niix WASM** (v1.0.20220720) - DICOM conversion
- **React** (v18.x) - UI framework
- **Vite** - Build tool (dev only)

**Update process:**
```bash
# Update React app dependencies
cd NiiVue/React
npm update
npm run build

# Copy new dist/ to SPM package
cp -r dist ../NiivueKit/Sources/NiivueKit/Resources/dist

# Update version in NiivueKit.swift
# Bump package version (PATCH for asset updates, MINOR for new features)
```

### Future External Dependencies (If Needed)

**Criteria for adding SPM dependencies:**
- Widely adopted (> 1000 GitHub stars)
- Actively maintained (commits in last 6 months)
- Pure Swift (no Objective-C bridging)
- Small binary footprint (< 500KB)

**Potential future dependencies:**
- **Swift Collections** - If complex data structures needed
- **Swift Numerics** - If advanced math operations needed
- **AsyncAlgorithms** - If advanced async patterns needed

## Security Considerations

### Path Traversal Protection

`NiivueURLRouter` validates all URLs to prevent directory traversal attacks:

```swift
// Security check in route()
guard !components.contains(".."), !components.contains(".") else {
    return nil
}
```

### Content Security Policy

The bundled `index.html` should include:

```html
<meta http-equiv="Content-Security-Policy"
      content="default-src 'self' niivue:;
               script-src 'self' 'unsafe-eval';
               style-src 'self' 'unsafe-inline';">
```

**Rationale:**
- `niivue:` - Allow custom scheme resources
- `unsafe-eval` - Required for WASM (dcm2niix)
- `unsafe-inline` - Required for dynamic styles (Material-UI)

### Sandboxing

**App Sandbox entitlements (if distributed via App Store):**
```xml
<!-- NiiVue.entitlements -->
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.files.user-selected.read-write</key>
<true/>  <!-- For file picker -->
<key>com.apple.security.network.client</key>
<false/>  <!-- Offline operation -->
```

## Performance Optimization

### Resource Loading

**WKURLSchemeHandler chunking:**
- 64KB chunks for large files (minimizes memory pressure)
- Async file I/O on background queue
- Cancellation support for interrupted requests

**Vite asset optimization:**
- Hash-based filenames for cache busting
- Code splitting (if React app grows)
- Tree-shaking to remove unused code

### Memory Management

**WebView lifecycle:**
```swift
// In consumer app
struct ContentView: View {
    @StateObject private var manager = WebViewManager()

    var body: some View {
        NiivueWebView(manager: manager)
            .onDisappear {
                // WebView deallocates automatically when manager is released
                // No manual cleanup required
            }
    }
}
```

**Large file handling:**
- URL-based loading (not base64) for files > 1MB
- Streaming from disk (via WKURLSchemeHandler)
- No full file buffering in memory

## Build Optimization

### Release Builds

**Recommended Xcode build settings for consumer apps:**

```swift
// Build Settings → Swift Compiler - Code Generation
SWIFT_OPTIMIZATION_LEVEL = -O               // Optimize for speed
SWIFT_COMPILATION_MODE = wholemodule        // Whole module optimization

// Build Settings → Apple Clang - Code Generation
GCC_OPTIMIZATION_LEVEL = s                  // Optimize for size

// Build Settings → Linking
DEAD_CODE_STRIPPING = YES                   // Remove unused code
```

### Binary Size

**Expected binary size contribution:**
- Swift code: ~500KB (compiled)
- React dist/: ~3.9MB (bundled resources)
- Total: ~4.4MB added to app

**Size optimization:**
- Use asset catalogs for images (App Thinning)
- Consider on-demand resources for sample files
- Strip debug symbols in release builds

## Troubleshooting Guide

### Common Integration Issues

**Issue: "Module 'NiivueKit' not found"**
```
Solution: Clean build folder (Cmd+Shift+K) and rebuild
```

**Issue: WebView shows blank screen**
```swift
// Check resource loading
guard let resourceURL = Bundle.module.resourceURL else {
    print("ERROR: Bundle resources not found")
    return
}
print("Resources at: \(resourceURL)")
```

**Issue: WASM file fails to load**
```
Solution: Verify Content-Type header in NiivueURLSchemeHandler
Must be: application/wasm
```

**Issue: Memory leak in WKWebView**
```swift
// Ensure weak script message handler
private lazy var scriptMessageHandler = WeakScriptMessageHandler(owner: self)
```

## Release Checklist

Before releasing a new version:

- [ ] Update version in `NiivueKit.swift`
- [ ] Update `CHANGELOG.md` with changes
- [ ] Run full test suite (`swift test`)
- [ ] Test integration in example app
- [ ] Update documentation (DocC comments)
- [ ] Create git tag (`git tag -a vX.Y.Z`)
- [ ] Push tag (`git push origin vX.Y.Z`)
- [ ] Create GitHub release with notes
- [ ] Verify SPM installation in fresh project

## Conclusion

This SPM package design provides:

1. **Modern Swift Package structure** with single target for simplicity
2. **Comprehensive resource bundling** for React app, WASM, and samples
3. **Multi-platform support** (iOS, Mac Catalyst, visionOS)
4. **Strict semantic versioning** with clear breaking change policy
5. **Zero external dependencies** for maximum stability
6. **Complete test coverage** with unit and integration tests
7. **Production-ready** security, performance, and documentation

The package is designed for easy distribution, integration, and long-term maintenance.
