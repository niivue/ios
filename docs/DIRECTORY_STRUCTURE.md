# NiivueKit Directory Structure Reference

This document shows the complete directory structure for the NiivueKit Swift Package.

## Overview

```
NiivueKit/
├── Package.swift                           # SPM manifest
├── README.md                               # Package documentation
├── LICENSE                                 # MIT or Apache 2.0
├── CHANGELOG.md                            # Version history
│
├── Sources/                                # All Swift source code
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
│       └── Resources/                     # Bundled resources (SPM resources)
│           ├── dist/                      # React app build output (Vite)
│           │   ├── index.html             # Entry point HTML
│           │   └── assets/                # Hashed assets from Vite build
│           │       ├── index-[hash].js    # Main React bundle (~1MB)
│           │       ├── index-[hash].css   # Styles (~23KB)
│           │       ├── dcm2niix.jpeg-[hash].wasm  # DICOM converter (~900KB)
│           │       ├── blosc-[hash].js    # Blosc compression codec (~600KB)
│           │       ├── lz4-[hash].js      # LZ4 compression codec (~36KB)
│           │       ├── zstd-[hash].js     # Zstd compression codec (size varies)
│           │       ├── worker.jpeg-[hash].js  # Web worker for DICOM processing
│           │       ├── chunk-INHXZS53-[hash].js  # Code-split chunk
│           │       └── roboto-*.woff2     # Font files (~10KB each)
│           │
│           └── samples/                   # Sample neuroimaging files
│               └── T1w_DEMO.nii.gz        # Demo brain scan (~4.2MB)
│
├── Tests/                                  # All test code
│   └── NiivueKitTests/
│       ├── Core/                          # Core component tests
│       │   ├── WebViewManagerTests.swift
│       │   ├── WebViewManagerStateTests.swift
│       │   ├── WebViewManagerCommandTests.swift
│       │   ├── JavaScriptEvaluatingTests.swift
│       │   └── JavaScriptQuoteTests.swift
│       │
│       ├── Networking/                    # URL handling tests
│       │   └── NiivueURLRouterTests.swift
│       │
│       ├── Services/                      # Service layer tests
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
│       │   ├── DicomCommandTests.swift
│       │   └── HUDMessageParsingTests.swift
│       │
│       ├── Mocks/                         # Test utilities
│       │   └── MockJavaScriptEvaluator.swift
│       │
│       └── Resources/
│           └── Fixtures/                  # Test data
│               ├── ui-test-volume-1.nii   # Minimal test volume (360 bytes)
│               └── ui-test-volume-2.nii   # Second test volume (360 bytes)
│
├── Documentation/                          # Developer documentation
│   ├── GettingStarted.md                  # Integration guide
│   ├── API_Reference.md                   # API documentation
│   ├── Architecture.md                    # Technical architecture
│   └── Migration.md                       # Migration guide from Xcode project
│
├── Examples/                               # Example integration projects
│   └── NiivueKitExample/                  # Demo Xcode project
│       ├── NiivueKitExample.xcodeproj
│       └── Sources/
│           ├── App.swift
│           └── ContentView.swift          # Example usage of NiivueKit
│
└── .github/                                # GitHub-specific files
    └── workflows/
        ├── ci.yml                         # CI pipeline (build + test)
        ├── release.yml                    # Release automation
        └── docs.yml                       # DocC documentation generation
```

## File Organization Strategy

### Sources/NiivueKit/

**Core/** - Essential WebView and JavaScript bridge
- `WebViewManager.swift`: Main @MainActor class managing WKWebView lifecycle
- `JavaScriptEvaluating.swift`: Protocol for testable JS evaluation
- `JavaScriptQuote.swift`: Safe string escaping using JSONEncoder

**Networking/** - Custom URL scheme (niivue://)
- `NiivueURLSchemeHandler.swift`: WKURLSchemeHandler for serving bundled resources
- `NiivueURLRouter.swift`: Routes niivue:// URLs with security validation

**Services/** - Business logic layer
- `FileImportService.swift`: Import files from document picker to app sandbox
- `ImportedFileStore.swift`: Registry of imported files with UUID-based storage
- `DicomSeriesStore.swift`: Manage multi-file DICOM series
- `DrawingExportService.swift`: Export segmentation drawings as NIfTI
- `SessionStore.swift`: Persist and restore viewer sessions
- `SessionSnapshotV1.swift`: Codable session snapshot format
- `Base64FileEncoder.swift`: Legacy base64 encoding (for small files)

**Extensions/** - Swift language extensions
- `WKWebView+JavaScriptEvaluating.swift`: Conform WKWebView to protocol

**Models/** - Data structures
- `VolumeInfo.swift`: Metadata for loaded volumes (id, name, nFrame4D)
- `SharedData.swift`: Shared state models (if needed)

**Resources/** - Bundled assets
- `dist/`: Vite build output (MUST use .copy() in Package.swift)
- `samples/`: Demo neuroimaging files

### Tests/NiivueKitTests/

Mirrors `Sources/` structure with `Tests` suffix:

**Core/** - Core component tests
- Tests for WebViewManager state management
- Tests for JavaScript evaluation and quoting
- Tests for async command execution

**Networking/** - URL routing tests
- Path traversal security tests
- Valid/invalid URL parsing
- Route type validation

**Services/** - Service layer tests
- File import workflow tests
- DICOM series management tests
- Session persistence tests

**Commands/** - Feature-specific tests
- Overlay (multi-volume) commands
- Time-series (4D volume) commands
- Segmentation/drawing commands
- DICOM import commands

**Mocks/** - Test doubles
- `MockJavaScriptEvaluator`: In-memory JS evaluator for unit tests

**Resources/Fixtures/** - Test data
- Minimal NIfTI files for fast tests (avoid large files in repo)

## Resource Bundling Details

### dist/ Directory (React Build Output)

**Structure from Vite:**
```
dist/
├── index.html                 # Entry point (loads assets via <script> tags)
└── assets/
    ├── index-[hash].js        # Main bundle (React app + Niivue.js)
    ├── index-[hash].css       # Material-UI styles
    ├── dcm2niix.jpeg-[hash].wasm  # WebAssembly DICOM converter
    ├── blosc-[hash].js        # Compression codec (Zarr support)
    ├── lz4-[hash].js          # Compression codec
    ├── zstd-[hash].js         # Compression codec
    ├── worker.jpeg-[hash].js  # Web Worker for DICOM
    └── roboto-*.woff2         # Font files
```

**Hash-based filenames:**
- Example: `index-Wk_2fF5U.js`
- Hash changes when file content changes
- Enables cache busting
- MUST preserve filenames (use `.copy()` not `.process()`)

**Total size:** ~3.9MB (primarily dcm2niix.wasm and JS bundles)

### samples/ Directory

**Sample files:**
```
samples/
└── T1w_DEMO.nii.gz            # Compressed NIfTI brain scan (~4.2MB)
```

**Purpose:**
- Demo/testing without requiring external files
- Reference implementation for file loading
- Can be extended with more samples in future versions

**Considerations:**
- Binary files (MUST use `.copy()`)
- Keep size minimal to avoid bloating package
- Full datasets should be in consumer apps, not SDK

## Access Patterns

### Loading Resources in Swift Code

**Bundle.module pattern (SPM automatic):**

```swift
// In NiivueURLSchemeHandler.swift
private func serveDistFile(path: String, task: WKURLSchemeTask) {
    guard let resourceURL = Bundle.module.resourceURL else {
        task.didFailWithError(HandlerError.fileNotFound)
        return
    }

    // Example: path = "assets/index-Wk_2fF5U.js"
    let fileURL = resourceURL
        .appendingPathComponent("dist")      // Resources/dist/
        .appendingPathComponent(path)        // Resources/dist/assets/index-Wk_2fF5U.js

    serveFile(at: fileURL, task: task)
}
```

**Sample file loading:**

```swift
private func serveSampleFile(path: String, task: WKURLSchemeTask) {
    guard let resourceURL = Bundle.module.resourceURL else {
        task.didFailWithError(HandlerError.fileNotFound)
        return
    }

    // Example: path = "T1w_DEMO.nii.gz"
    let fileURL = resourceURL
        .appendingPathComponent("samples")   // Resources/samples/
        .appendingPathComponent(path)        // Resources/samples/T1w_DEMO.nii.gz

    serveFile(at: fileURL, task: task)
}
```

### Loading Resources from JavaScript

**In React app (niivue:// custom scheme):**

```javascript
// Load bundled sample
await window.loadImageFromUrl(
    "niivue://app/samples/T1w_DEMO.nii.gz",
    "T1w_DEMO.nii.gz"
);

// Load imported file (from user's document picker)
await window.loadImageFromUrl(
    "niivue://app/files/550e8400-e29b-41d4-a716-446655440000",
    "patient_scan.nii.gz"
);
```

**URL routing:**
- `niivue://app/index.html` → `Resources/dist/index.html`
- `niivue://app/assets/index-[hash].js` → `Resources/dist/assets/index-[hash].js`
- `niivue://app/samples/T1w_DEMO.nii.gz` → `Resources/samples/T1w_DEMO.nii.gz`
- `niivue://app/files/<uuid>` → Application Support (not bundled)

## Migration from Xcode Project

### Current Structure (niivue-ios-foundation)

```
niivue-ios-foundation/
└── NiiVue/
    ├── NiiVue.xcodeproj          # Xcode project (will become Example)
    ├── NiiVue/                   # iOS app sources
    │   ├── Web/                  # → Sources/NiivueKit/Core/ + Networking/
    │   ├── Services/             # → Sources/NiivueKit/Services/
    │   ├── samples/              # → Sources/NiivueKit/Resources/samples/
    │   ├── NiiVueApp.swift       # App-specific (stays in Example)
    │   └── ContentView.swift     # App-specific (stays in Example)
    │
    ├── NiiVueTests/              # → Tests/NiivueKitTests/
    │
    └── React/                    # React build (stays separate)
        └── dist/                 # → Sources/NiivueKit/Resources/dist/
```

### New Structure (NiivueKit SPM)

```
NiivueKit/                        # New SPM package root
├── Package.swift                 # NEW
├── Sources/NiivueKit/            # Migrated from NiiVue/NiiVue/
├── Tests/NiivueKitTests/         # Migrated from NiiVue/NiiVueTests/
└── Examples/NiivueKitExample/    # Simplified version of NiiVue.xcodeproj
```

### Migration Script

```bash
#!/bin/bash
# migrate-to-spm.sh

# 1. Create new SPM package structure
mkdir -p NiivueKit/Sources/NiivueKit/{Core,Networking,Services,Extensions,Models,Resources}
mkdir -p NiivueKit/Tests/NiivueKitTests/{Core,Networking,Services,Commands,Mocks,Resources/Fixtures}

# 2. Copy Swift sources
cp NiiVue/NiiVue/Web/*.swift NiivueKit/Sources/NiivueKit/Core/
mv NiivueKit/Sources/NiivueKit/Core/NiivueURLSchemeHandler.swift NiivueKit/Sources/NiivueKit/Networking/
mv NiivueKit/Sources/NiivueKit/Core/NiivueURLRouter.swift NiivueKit/Sources/NiivueKit/Networking/
cp NiiVue/NiiVue/Services/*.swift NiivueKit/Sources/NiivueKit/Services/

# 3. Copy resources
cp -r NiiVue/React/dist NiivueKit/Sources/NiivueKit/Resources/
cp -r NiiVue/NiiVue/samples NiivueKit/Sources/NiivueKit/Resources/

# 4. Copy tests
cp -r NiiVue/NiiVueTests/*.swift NiivueKit/Tests/NiivueKitTests/
# Organize into subdirectories (manual step)

# 5. Create Package.swift
cp Package.swift NiivueKit/

# 6. Test build
cd NiivueKit
swift build
swift test
```

### Code Changes Required

**Bundle access:**
```swift
// Before (Xcode app):
Bundle.main.resourceURL

// After (SPM package):
Bundle.module.resourceURL
```

**Access control:**
```swift
// Before (internal by default):
final class WebViewManager { }

// After (explicit public):
public final class WebViewManager { }
```

**Remove app-specific code:**
- `NiiVueApp.swift` → Move to Examples/
- `ContentView.swift` → Move to Examples/
- `Assets.xcassets` → Move to Examples/

## File Sizes

### Sources/NiivueKit/Resources/

```
dist/                          ~3.9 MB total
├── index.html                 393 bytes
└── assets/
    ├── index-*.js             ~1.0 MB (React + Niivue.js)
    ├── index-*.css            23 KB
    ├── dcm2niix.*.wasm        900 KB
    ├── blosc-*.js             603 KB
    ├── lz4-*.js               36 KB
    ├── zstd-*.js              (varies)
    ├── worker.*.js            (varies)
    └── roboto-*.woff2         ~150 KB total (fonts)

samples/
└── T1w_DEMO.nii.gz            4.2 MB

Total bundled resources:       ~8.1 MB
```

### Compiled Swift Code

```
Estimated binary size:         ~500 KB
Total package contribution:    ~8.6 MB
```

**Optimization notes:**
- Most size is in resources (WASM + sample file)
- Consider optional sample file download in future
- Use App Thinning for platform-specific builds
- Strip debug symbols in release builds

## Build System Integration

### SPM Build Process

1. **Package resolution:**
   ```bash
   swift package resolve
   # Fetches dependencies (none for NiivueKit)
   # Generates .build/ directory
   ```

2. **Build:**
   ```bash
   swift build
   # Compiles Swift sources
   # Copies resources to .build/debug/NiivueKit_NiivueKit.bundle/
   ```

3. **Test:**
   ```bash
   swift test
   # Builds test target
   # Runs XCTest suite
   # Generates code coverage
   ```

### Xcode Integration

When adding NiivueKit to an Xcode project:

1. Xcode clones the package
2. Swift Package Manager builds the framework
3. Resources are embedded in `NiivueKit_NiivueKit.bundle`
4. Bundle is automatically included in app bundle
5. `Bundle.module` resolves to this bundle at runtime

**No manual build phases required!**

## Common Issues

### Issue: Resources not found at runtime

**Symptom:**
```
ERROR: Bundle resources not found
```

**Solution:**
```swift
// Verify Bundle.module exists
print("Bundle module: \(Bundle.module)")
print("Resource URL: \(Bundle.module.resourceURL?.path ?? "nil")")
```

**Possible causes:**
- Package.swift missing `.copy("Resources/dist")` or `.copy("Resources/samples")`
- Resources directory not at `Sources/NiivueKit/Resources/`
- Clean build required (Product → Clean Build Folder)

### Issue: WASM fails to load

**Symptom:**
```
Failed to load WebAssembly module
```

**Solution:**
Check MIME type in `NiivueURLSchemeHandler`:
```swift
case "wasm":
    return "application/wasm"  // MUST be this exact MIME type
```

### Issue: Asset paths incorrect

**Symptom:**
```
404 for niivue://app/assets/index-Wk_2fF5U.js
```

**Solution:**
Verify Vite build preserves hash filenames:
```bash
cd NiiVue/React
npm run build
ls -la dist/assets/
# Should show files like: index-Wk_2fF5U.js (not index.js)
```

## Future Enhancements

### Potential Structure Changes

**If package grows to include SwiftUI views:**
```
Sources/NiivueKit/
├── Core/              # Existing WebView management
├── Networking/        # Existing URL scheme handling
├── Services/          # Existing business logic
└── UI/                # NEW: SwiftUI components
    ├── NiivueView.swift
    ├── VolumeListView.swift
    └── ToolbarView.swift
```

**If DICOM processing becomes standalone:**
```
Sources/
├── NiivueKitCore/     # Core + Networking + Models
├── NiivueKitUI/       # SwiftUI views
└── NiivueKitDICOM/    # DICOM utilities (can use without WebView)
```

### Asset Optimization

**Lazy loading for large resources:**
```swift
// Future: On-demand resource download
public func downloadSampleFile(name: String) async throws {
    let url = URL(string: "https://niivue.github.io/samples/\(name)")!
    // Download to Application Support
}
```

**Asset catalog for images:**
```
Resources/
├── dist/
├── samples/
└── Assets.xcassets/       # For icons, splash screens
    └── AppIcon.appiconset/
```

## Conclusion

This directory structure provides:

1. **Clear separation of concerns** (Core, Networking, Services, Models)
2. **Testable architecture** (parallel test structure)
3. **Efficient resource bundling** (dist/ and samples/ preserved)
4. **Migration path** from Xcode project
5. **Room for growth** (UI/, DICOM/, etc.)

The structure follows Swift Package Manager best practices and iOS development conventions.
