# Changelog

All notable changes to NiivueKit will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned
- Intensity windowing controls (cal_min/cal_max sliders)
- Volume removal and reordering APIs
- 3D azimuth/elevation gesture controls
- Mesh shader and property controls
- Distance and angle measurement tools

---

## [1.0.0] - 2026-01-15

### Added
- **Core WebViewManager**: Type-safe Swift bridge to Niivue JavaScript library
- **Volume Loading**: Support for NIfTI, NRRD, MGH, AFNI formats via URL, file, or base64
- **DICOM Import**: Manifest-based DICOM loading with WebAssembly dcm2niix conversion
  - `DicomSeriesStore` actor for thread-safe file management
  - Custom `niivue://` URL scheme for serving DICOM files
  - Document picker integration for iOS file import
- **Drawing Tools**: Segmentation with pen tools, undo/redo, and NIfTI export
  - `setPenValue()` for setting drawing color/value
  - `setDrawOpacity()` for transparency control
  - `saveDrawing()` for exporting as NIfTI
  - `drawUndo()` for undo support
- **Visualization Controls**:
  - Slice type selection (Axial, Coronal, Sagittal, Multiplanar, 3D Render)
  - Colormap selection from 250+ scientific colormaps
  - Opacity control for multi-volume overlay
  - Crosshair positioning and HUD display
  - Radiological vs neurological convention toggle
  - Corner orientation text display
  - 3D orientation cube
- **Session Management**:
  - `SessionStore` actor for persistent state save/restore
  - `SessionSnapshotV1` format with volume sources, view settings
  - Automatic session restoration on app launch
- **File Import Service**:
  - Security-scoped resource access handling
  - File copying to app container with unique IDs
  - Custom URL scheme resolution for imported files
- **Testing Infrastructure**:
  - 77 Swift unit tests with full coverage
  - 16 JavaScript bridge tests
  - UI tests with accessibility identifiers
  - Mock evaluator for deterministic testing

### Architecture
- Actor-based concurrency for thread-safe data stores
- `@MainActor` isolation for UI-related managers
- Custom WKURLSchemeHandler for `niivue://` protocol
- JSON-safe JavaScript string escaping via `JavaScriptQuote`
- Weak script message handler to prevent retain cycles

### Documentation
- Comprehensive inline code documentation
- DocC-compatible API documentation
- Getting Started tutorial
- DICOM import guide
- Troubleshooting guide
- Example projects (SwiftUI, UIKit)

### Platform Support
- iOS 15.0+
- visionOS 1.0+
- Swift 6.0
- Xcode 16.0+

### Dependencies
- Niivue 0.47.1
- @niivue/dicom-loader 0.2.0
- React 19.0.0
- Vite 6.0.7

### Known Limitations
- No direct mesh property controls (shader, opacity)
- No intensity windowing UI (cal_min/cal_max)
- No volume removal/reordering APIs
- No measurement tools (distance, angle)
- No clip plane controls
- Limited 3D gesture support (no azimuth/elevation)

---

## [0.9.0-beta] - 2026-01-04

### Added
- Beta release of core functionality
- DICOM Import Pack (Phase 2 Tasks 7-9)
- JavaScript bridge modules for volume and drawing commands
- Basic SwiftUI integration

### Fixed
- Memory leaks in WKScriptMessageHandler
- File access permissions for security-scoped resources
- WASM module loading in Vite build

---

## [0.5.0-alpha] - 2025-12-15

### Added
- Initial alpha release
- WebViewManager prototype
- Basic volume loading from URLs
- Proof-of-concept SwiftUI app

### Known Issues
- No DICOM support
- Limited error handling
- No session persistence

---

## Versioning Guidelines

### Major Version (X.0.0)
Increment when making incompatible API changes:
- Removing public APIs
- Changing method signatures
- Renaming types or properties
- Significant architectural changes

Example:
```swift
// 1.x.x
func loadVolume(from url: String) async throws

// 2.0.0 - Breaking change
func loadVolume(from source: VolumeSource) async throws  // Changed parameter type
```

### Minor Version (0.X.0)
Increment when adding functionality in a backwards-compatible manner:
- New public methods or properties
- New optional parameters with defaults
- Performance improvements
- New supported formats

Example:
```swift
// 1.0.0
func setColormap(volumeId: String, colormap: String) async throws

// 1.1.0 - New feature, backwards compatible
func setColormapNegative(volumeId: String, colormap: String) async throws
```

### Patch Version (0.0.X)
Increment for backwards-compatible bug fixes:
- Crash fixes
- Memory leak fixes
- Incorrect behavior fixes
- Documentation improvements

Example:
```swift
// 1.0.0 - Bug: crashes on empty volume list
func loadVolumes(_ urls: [String]) async throws {
    for url in urls {
        // Missing nil check
    }
}

// 1.0.1 - Fixed crash
func loadVolumes(_ urls: [String]) async throws {
    guard !urls.isEmpty else { return }
    for url in urls {
        // ...
    }
}
```

---

## What to Document

### Added
- New features, APIs, or capabilities
- New supported file formats
- New example projects
- New documentation guides

### Changed
- Modifications to existing functionality (backwards-compatible)
- Performance improvements
- Updated dependencies
- Documentation restructuring

### Deprecated
- Features marked for removal in future versions
- Include migration path

Example:
```markdown
### Deprecated
- `loadVolumeFromURL(_:)` - Use `loadVolume(from: .url(urlString))` instead. Will be removed in 2.0.0.
```

### Removed
- Features removed in this version
- Provide migration instructions

### Fixed
- Bug fixes with issue numbers
- Memory leaks
- Incorrect behavior

### Security
- Security vulnerability fixes
- Updated dependencies with security patches

---

## Release Checklist

Before releasing a new version:

- [ ] Update version number in `Package.swift`
- [ ] Update version number in `NiivueKit.podspec`
- [ ] Add release entry to this CHANGELOG.md
- [ ] Update documentation with new APIs
- [ ] Run full test suite: `npm run test:all`
- [ ] Update README.md if new features added
- [ ] Tag release in git: `git tag -a v1.0.0 -m "Release 1.0.0"`
- [ ] Push tags: `git push origin --tags`
- [ ] Create GitHub release with changelog excerpt
- [ ] Update documentation site
- [ ] Announce on social media / community channels

---

## Example Changelog Entry

```markdown
## [1.2.0] - 2026-03-15

### Added
- **Intensity Windowing Controls** ([#45](https://github.com/niivue/niivue-ios-foundation/issues/45))
  - `setCalMinMax(volumeIndex:min:max:)` method for direct windowing control
  - `getCalMinMax(volumeIndex:)` to retrieve current window settings
  - SwiftUI dual-slider component for interactive adjustment
  - Auto-range button to reset to data range
- **Volume Removal API** ([#52](https://github.com/niivue/niivue-ios-foundation/pull/52))
  - `removeVolume(at index: Int)` to remove specific volume
  - `removeAllVolumes()` to clear all loaded volumes
  - Swipe-to-delete gesture support in volume list UI
- **3D Azimuth/Elevation Controls** ([#58](https://github.com/niivue/niivue-ios-foundation/issues/58))
  - `setRenderAzimuthElevation(azimuth:elevation:)` for programmatic rotation
  - Two-finger rotation gesture mapping
  - `onAzimuthElevationChange` callback for UI synchronization

### Changed
- **Improved DICOM Import Performance** ([#63](https://github.com/niivue/niivue-ios-foundation/pull/63))
  - 40% faster conversion for large series (>100 files)
  - Reduced memory usage by 25% during conversion
  - Added progress reporting with ETA calculation
- **Updated Dependencies**
  - Niivue 0.48.0 → 0.49.2 (fixes WebGL context loss on iOS 17.4)
  - @niivue/dicom-loader 0.2.0 → 0.3.1 (improved compression support)

### Deprecated
- `loadVolumeFromURL(_:)` - Use `loadVolume(from: .url(urlString))` instead.
  Will be removed in 2.0.0. Migration path: Replace method calls with new enum-based source.

### Fixed
- **DICOM Import Crash** ([#67](https://github.com/niivue/niivue-ios-foundation/issues/67))
  - Fixed crash when importing DICOM series with missing SeriesInstanceUID
  - Added validation for required DICOM tags before conversion
- **Memory Leak in SessionStore** ([#71](https://github.com/niivue/niivue-ios-foundation/pull/71))
  - Fixed strong reference cycle in session snapshot callbacks
  - Reduced baseline memory usage by 15MB
- **WebGL Context Loss** ([#74](https://github.com/niivue/niivue-ios-foundation/issues/74))
  - Improved handling of app backgrounding during rendering
  - Auto-recovery when context is restored

### Security
- Updated fflate dependency to 0.8.3 (fixes CVE-2024-XXXXX)
- Added validation for base64-encoded volume data to prevent injection attacks

[1.2.0]: https://github.com/niivue/niivue-ios-foundation/compare/v1.1.0...v1.2.0
```

---

[Unreleased]: https://github.com/niivue/niivue-ios-foundation/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/niivue/niivue-ios-foundation/releases/tag/v1.0.0
[0.9.0-beta]: https://github.com/niivue/niivue-ios-foundation/releases/tag/v0.9.0-beta
[0.5.0-alpha]: https://github.com/niivue/niivue-ios-foundation/releases/tag/v0.5.0-alpha
