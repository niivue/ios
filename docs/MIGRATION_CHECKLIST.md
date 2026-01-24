# NiivueKit Migration Checklist

A step-by-step guide to convert the existing Xcode iOS app project into a Swift Package Manager (SPM) distributable SDK.

## Overview

**Current State:**
- Xcode iOS app project (`NiiVue.xcodeproj`)
- Monolithic app target with embedded React WebView
- Resources in app bundle via Xcode build phases

**Target State:**
- Swift Package Manager library (`Package.swift`)
- Reusable framework with bundled resources
- Separate example app demonstrating integration

## Prerequisites

- [x] Xcode 15.0+
- [x] Swift 5.9+
- [x] macOS 13.0+ (for Catalyst testing)
- [x] Git repository initialized
- [x] React app built (`npm run build` in React/ directory)

## Phase 1: Package Structure Setup

### Step 1.1: Create SPM Package Directory

```bash
# Navigate to repository root
cd /Users/leandroalmeida/niivue-ios-foundation

# Create new package directory
mkdir -p NiivueKit

# Initialize basic SPM structure
cd NiivueKit
swift package init --type library --name NiivueKit

# This creates:
# - Package.swift
# - Sources/NiivueKit/
# - Tests/NiivueKitTests/
```

**Verification:**
```bash
swift build
# Should succeed (builds empty library)
```

### Step 1.2: Replace Package.swift

```bash
# Copy the designed Package.swift
cp ../Package.swift ./Package.swift

# Or create manually (see SPM_PACKAGE_DESIGN.md)
```

**Contents:**
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NiivueKit",
    platforms: [
        .iOS(.v16),
        .macCatalyst(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "NiivueKit", targets: ["NiivueKit"])
    ],
    targets: [
        .target(
            name: "NiivueKit",
            resources: [
                .copy("Resources/dist"),
                .copy("Resources/samples")
            ]
        ),
        .testTarget(
            name: "NiivueKitTests",
            dependencies: ["NiivueKit"],
            resources: [.copy("Resources/Fixtures")]
        )
    ]
)
```

**Verification:**
```bash
swift package describe
# Should show package info
```

### Step 1.3: Create Directory Structure

```bash
# Remove default files
rm -rf Sources/NiivueKit/*
rm -rf Tests/NiivueKitTests/*

# Create organized structure
mkdir -p Sources/NiivueKit/{Core,Networking,Services,Extensions,Models,Resources/{dist,samples}}
mkdir -p Tests/NiivueKitTests/{Core,Networking,Services,Commands,Mocks,Resources/Fixtures}
mkdir -p Documentation
mkdir -p Examples
```

**Verification:**
```bash
tree -L 3 -d
# Should show organized directory structure
```

## Phase 2: Copy Source Files

### Step 2.1: Copy Swift Sources

```bash
# Set source and destination paths
SRC_DIR="../NiiVue/NiiVue"
DEST_DIR="Sources/NiivueKit"

# Copy Core components (Web directory)
cp "$SRC_DIR/Web/WebViewManager.swift" "$DEST_DIR/Core/"
cp "$SRC_DIR/Web/JavaScriptEvaluating.swift" "$DEST_DIR/Core/"
cp "$SRC_DIR/Web/JavaScriptQuote.swift" "$DEST_DIR/Core/"

# Copy Networking components
cp "$SRC_DIR/Web/NiivueURLSchemeHandler.swift" "$DEST_DIR/Networking/"
cp "$SRC_DIR/Web/NiivueURLRouter.swift" "$DEST_DIR/Networking/"

# Copy Extensions
cp "$SRC_DIR/Web/WKWebView+JavaScriptEvaluating.swift" "$DEST_DIR/Extensions/"

# Copy Services
cp "$SRC_DIR/Services/"*.swift "$DEST_DIR/Services/"

# Copy Models (if any)
cp "$SRC_DIR/SharedData.swift" "$DEST_DIR/Models/" 2>/dev/null || true
```

**Verification:**
```bash
find Sources/NiivueKit -name "*.swift" | wc -l
# Should show ~16 files
```

### Step 2.2: Create Public API Entry Point

```bash
cat > Sources/NiivueKit/NiivueKit.swift << 'EOF'
/// NiivueKit - Swift SDK for neuroimaging visualization
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
public enum NiivueKit {
    /// The current version of NiivueKit.
    public static let version = "1.0.0"

    /// The bundled Niivue.js version.
    public static let niivueVersion = "0.45.0"

    /// The bundled dcm2niix WASM version.
    public static let dcm2niixVersion = "1.0.20220720"
}
EOF
```

**Verification:**
```bash
cat Sources/NiivueKit/NiivueKit.swift
# Should show public API entry point
```

### Step 2.3: Copy Resources

```bash
# Copy React dist/ directory (Vite build output)
cp -r ../NiiVue/React/dist/* Sources/NiivueKit/Resources/dist/

# Copy sample files
cp -r ../NiiVue/NiiVue/samples/* Sources/NiivueKit/Resources/samples/

# Verify resource sizes
du -sh Sources/NiivueKit/Resources/dist
du -sh Sources/NiivueKit/Resources/samples
```

**Expected output:**
```
3.9M    Sources/NiivueKit/Resources/dist
4.2M    Sources/NiivueKit/Resources/samples
```

**Verification:**
```bash
# Check dist/ has all required files
ls Sources/NiivueKit/Resources/dist/
# Should show: index.html, assets/

ls Sources/NiivueKit/Resources/dist/assets/ | grep wasm
# Should show: dcm2niix.jpeg-[hash].wasm
```

### Step 2.4: Copy Tests

```bash
SRC_TEST_DIR="../NiiVue/NiiVueTests"
DEST_TEST_DIR="Tests/NiivueKitTests"

# Copy test files (organize into subdirectories)
cp "$SRC_TEST_DIR/WebViewManagerTests.swift" "$DEST_TEST_DIR/Core/" 2>/dev/null || true
cp "$SRC_TEST_DIR/WebViewManagerStateTests.swift" "$DEST_TEST_DIR/Core/"
cp "$SRC_TEST_DIR/WebViewManagerCommandTests.swift" "$DEST_TEST_DIR/Core/"
cp "$SRC_TEST_DIR/JavaScriptEvaluatingTests.swift" "$DEST_TEST_DIR/Core/"
cp "$SRC_TEST_DIR/JavaScriptQuoteTests.swift" "$DEST_TEST_DIR/Core/"

cp "$SRC_TEST_DIR/NiivueURLRouterTests.swift" "$DEST_TEST_DIR/Networking/"

cp "$SRC_TEST_DIR/FileImportServiceTests.swift" "$DEST_TEST_DIR/Services/"
cp "$SRC_TEST_DIR/DicomSeriesStoreTests.swift" "$DEST_TEST_DIR/Services/"
cp "$SRC_TEST_DIR/DrawingExportServiceTests.swift" "$DEST_TEST_DIR/Services/"
cp "$SRC_TEST_DIR/SessionStoreTests.swift" "$DEST_TEST_DIR/Services/"
cp "$SRC_TEST_DIR/Base64FileEncoderTests.swift" "$DEST_TEST_DIR/Services/"

cp "$SRC_TEST_DIR/OverlayCommandTests.swift" "$DEST_TEST_DIR/Commands/"
cp "$SRC_TEST_DIR/TimeSeriesCommandTests.swift" "$DEST_TEST_DIR/Commands/"
cp "$SRC_TEST_DIR/SegmentationCommandTests.swift" "$DEST_TEST_DIR/Commands/"
cp "$SRC_TEST_DIR/DicomCommandTests.swift" "$DEST_TEST_DIR/Commands/"
cp "$SRC_TEST_DIR/HUDMessageParsingTests.swift" "$DEST_TEST_DIR/Commands/"

cp "$SRC_TEST_DIR/MockJavaScriptEvaluator.swift" "$DEST_TEST_DIR/Mocks/"

# Copy test fixtures
cp ../NiiVue/NiiVue/samples/ui-test-volume-*.nii "$DEST_TEST_DIR/Resources/Fixtures/" 2>/dev/null || true
```

**Verification:**
```bash
find Tests/NiivueKitTests -name "*.swift" | wc -l
# Should show ~17 test files
```

## Phase 3: Code Modifications for SPM

### Step 3.1: Update Bundle Access

**Find all Bundle.main references:**
```bash
grep -r "Bundle.main" Sources/NiivueKit/
```

**Replace with Bundle.module:**

Edit `Sources/NiivueKit/Networking/NiivueURLSchemeHandler.swift`:

```diff
- guard let resourceURL = Bundle.main.resourceURL else {
+ guard let resourceURL = Bundle.module.resourceURL else {
      task.didFailWithError(HandlerError.fileNotFound)
      return
  }
```

**Automated replacement:**
```bash
# macOS sed syntax
find Sources/NiivueKit -name "*.swift" -exec sed -i '' 's/Bundle\.main/Bundle.module/g' {} +
```

**Verification:**
```bash
grep -r "Bundle.main" Sources/NiivueKit/
# Should return no results
```

### Step 3.2: Add Access Control Modifiers

All public-facing types need explicit `public` modifier:

```bash
# List files that need public APIs
FILES_NEEDING_PUBLIC=(
    "Sources/NiivueKit/Core/WebViewManager.swift"
    "Sources/NiivueKit/Core/JavaScriptEvaluating.swift"
    "Sources/NiivueKit/Services/FileImportService.swift"
    "Sources/NiivueKit/Services/ImportedFileStore.swift"
    "Sources/NiivueKit/Services/DicomSeriesStore.swift"
    "Sources/NiivueKit/Services/SessionStore.swift"
    "Sources/NiivueKit/Services/SessionSnapshotV1.swift"
)

echo "Files requiring 'public' modifiers:"
printf '%s\n' "${FILES_NEEDING_PUBLIC[@]}"
```

**Manual edits required:**

Edit `Sources/NiivueKit/Core/WebViewManager.swift`:
```diff
- @MainActor
- final class WebViewManager: NSObject, ObservableObject {
+ @MainActor
+ public final class WebViewManager: NSObject, ObservableObject {

-     struct VolumeInfo: Codable, Equatable {
+     public struct VolumeInfo: Codable, Equatable {

-     init(
+     public init(
```

**Apply similar changes to:**
- `JavaScriptEvaluating.swift` - Make protocol `public`
- `FileImportService.swift` - Make struct and methods `public`
- `ImportedFileStore.swift` - Make struct and methods `public`
- `DicomSeriesStore.swift` - Make struct and methods `public`
- `SessionStore.swift` - Make struct and methods `public`
- `SessionSnapshotV1.swift` - Make struct and nested types `public`

**Internal types (keep package-private):**
- `JavaScriptQuote.swift`
- `NiivueURLSchemeHandler.swift`
- `NiivueURLRouter.swift`
- `Base64FileEncoder.swift`
- `DrawingExportService.swift`

### Step 3.3: Remove App-Specific Code

These files should NOT be copied to NiivueKit (they're app-specific):

```bash
# Do NOT copy:
# - NiiVueApp.swift (SwiftUI App entry point)
# - ContentView.swift (UI layer)
# - Assets.xcassets (app assets)
# - Info.plist (app configuration)
# - *.entitlements (app sandbox settings)
```

**Save these for Examples/ directory instead**

### Step 3.4: Update Import Statements

All test files need to import NiivueKit:

```bash
# Check if import exists
grep -r "import NiivueKit" Tests/NiivueKitTests/
```

If missing, add to all test files:

```bash
for file in Tests/NiivueKitTests/**/*.swift; do
    # Check if file exists and doesn't already have import
    if [ -f "$file" ] && ! grep -q "import NiivueKit" "$file"; then
        # Add import after last existing import or at top
        sed -i '' '1i\
import NiivueKit
' "$file"
    fi
done
```

**Verification:**
```bash
# All test files should import NiivueKit
grep -r "import NiivueKit" Tests/NiivueKitTests/ | wc -l
# Should match number of test files
```

## Phase 4: Build and Test

### Step 4.1: Initial Build

```bash
# Clean build
rm -rf .build

# Build package
swift build

# Expected errors on first try:
# - Missing public modifiers
# - Bundle.main references
# - Import statements
```

**Common build errors:**

| Error | Solution |
|-------|----------|
| `'WebViewManager' is inaccessible due to 'internal' protection level` | Add `public` modifier |
| `Cannot find 'Bundle' in scope` | Add `import Foundation` |
| `Use of unresolved identifier 'Bundle'` | Add `import Foundation` |
| `No such module 'NiivueKit'` | Add `import NiivueKit` to test files |

### Step 4.2: Fix Build Errors

Iterate on build errors:

```bash
# Build and capture errors
swift build 2>&1 | tee build-errors.log

# Fix errors (see DIRECTORY_STRUCTURE.md for patterns)
# Repeat until clean build
```

**Target: Zero errors, zero warnings**

### Step 4.3: Run Tests

```bash
# Run all tests
swift test

# Run with verbose output
swift test --verbose

# Run specific test
swift test --filter WebViewManagerTests
```

**Expected test results:**
- All tests should pass (if properly ported)
- Some tests may need adjustment for SPM environment

### Step 4.4: Generate Code Coverage

```bash
swift test --enable-code-coverage

# View coverage report
xcrun llvm-cov report \
    .build/debug/NiivueKitPackageTests.xctest/Contents/MacOS/NiivueKitPackageTests \
    -instr-profile .build/debug/codecov/default.profdata

# Target: 80%+ coverage for public APIs
```

## Phase 5: Documentation

### Step 5.1: Add DocC Comments

Add documentation comments to all public APIs:

```swift
/// Manages the WKWebView and provides a type-safe bridge to the Niivue JS app.
///
/// `WebViewManager` is the main entry point for integrating Niivue into your app.
/// It handles WebView lifecycle, JavaScript evaluation, and volume loading.
///
/// ## Topics
/// ### Initialization
/// - ``init(evaluator:initializationTimeoutNanoseconds:)``
///
/// ### Loading
/// - ``load()``
/// - ``reload()``
///
/// ### Volume Management
/// - ``loadImageFromUrl(url:fileName:)``
/// - ``loadVolumesFromUrls(_:)``
/// - ``addVolumesFromUrls(_:)``
///
/// ### State
/// - ``isReady``
/// - ``volumes``
/// - ``lastErrorMessage``
@MainActor
public final class WebViewManager: NSObject, ObservableObject {
    // ...
}
```

### Step 5.2: Generate Documentation

```bash
# Generate DocC archive
swift package generate-documentation \
    --target NiivueKit \
    --output-path ./docs

# Preview documentation
swift package --disable-sandbox preview-documentation \
    --target NiivueKit

# Opens browser at http://localhost:8080/documentation/niivuekit
```

**Verification:**
- Browse to http://localhost:8080/documentation/niivuekit
- Check all public types are documented
- Verify code examples render correctly

### Step 5.3: Create README.md

```bash
cat > README.md << 'EOF'
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

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/niivue/NiivueKit.git", from: "1.0.0")
]
```

Or via Xcode: File → Add Package Dependencies

## Quick Start

```swift
import SwiftUI
import NiivueKit

struct ContentView: View {
    @StateObject private var manager = WebViewManager()

    var body: some View {
        WebViewRepresentable(webView: manager.webView)
            .onAppear {
                manager.load()
            }
    }
}
```

## Documentation

[Full API Documentation](https://niivue.github.io/NiivueKit)

## License

MIT
EOF
```

### Step 5.4: Create CHANGELOG.md

```bash
cat > CHANGELOG.md << 'EOF'
# Changelog

All notable changes to NiivueKit will be documented in this file.

## [Unreleased]

## [1.0.0] - 2026-01-15

### Added
- Initial public release
- Swift Package Manager distribution
- iOS 16+ and macOS Catalyst support
- React app bundling (Vite build)
- WebAssembly DICOM converter (dcm2niix)
- Custom niivue:// URL scheme
- Comprehensive test suite
EOF
```

## Phase 6: Example App

### Step 6.1: Create Example Project

```bash
# Create example app directory
mkdir -p Examples/NiivueKitExample

# Create Xcode project (manual - use Xcode GUI)
# 1. Open Xcode
# 2. File → New → Project
# 3. iOS → App
# 4. Name: NiivueKitExample
# 5. Save in: Examples/NiivueKitExample/
```

### Step 6.2: Add NiivueKit Dependency

In Xcode:
1. Select project in navigator
2. Select app target
3. General → Frameworks, Libraries, and Embedded Content
4. Click "+" → Add Package Dependency
5. Enter local path: `../../` (points to NiivueKit root)
6. Add NiivueKit library

### Step 6.3: Create Example UI

Copy simplified version of original ContentView:

```bash
# Copy app entry point
cat > Examples/NiivueKitExample/App.swift << 'EOF'
import SwiftUI
import NiivueKit

@main
struct NiivueKitExampleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
EOF

# Copy content view (simplified)
cat > Examples/NiivueKitExample/ContentView.swift << 'EOF'
import SwiftUI
import NiivueKit
import WebKit

struct ContentView: View {
    @StateObject private var manager = WebViewManager()

    var body: some View {
        VStack {
            if manager.isReady {
                WebViewRepresentable(webView: manager.webView)
            } else if let error = manager.lastErrorMessage {
                ErrorView(message: error)
            } else {
                LoadingView()
            }
        }
        .onAppear {
            manager.load()
        }
        .task {
            // Load demo sample
            try? await manager.loadImageFromUrl(
                url: "niivue://app/samples/T1w_DEMO.nii.gz",
                fileName: "T1w_DEMO.nii.gz"
            )
        }
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

struct LoadingView: View {
    var body: some View {
        ProgressView("Loading Niivue...")
    }
}

struct ErrorView: View {
    let message: String

    var body: some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("Error: \(message)")
        }
    }
}
EOF
```

### Step 6.4: Test Example App

```bash
# Build and run in Xcode
# Or use command line:
cd Examples/NiivueKitExample
xcodebuild -scheme NiivueKitExample -destination 'platform=iOS Simulator,name=iPhone 15'
```

**Verification:**
- App launches
- WebView loads
- Sample brain scan displays
- No console errors

## Phase 7: Version Control

### Step 7.1: Create .gitignore

```bash
cat > .gitignore << 'EOF'
# Swift Package Manager
.build/
.swiftpm/
Package.resolved

# Xcode
*.xcodeproj/xcuserdata/
*.xcworkspace/xcuserdata/
DerivedData/
*.xcodeproj/project.xcworkspace/

# macOS
.DS_Store

# Coverage
*.profdata
*.coverage.txt
EOF
```

### Step 7.2: Initial Commit

```bash
git init
git add .
git commit -m "Initial commit - NiivueKit v1.0.0

- Swift Package Manager structure
- iOS 16+ / macOS Catalyst / visionOS support
- Bundled React app (Vite dist/)
- WebAssembly DICOM converter
- Custom niivue:// URL scheme
- Comprehensive test suite
- Example app"
```

### Step 7.3: Create Tag

```bash
git tag -a v1.0.0 -m "Release 1.0.0 - Initial public release"
```

### Step 7.4: Push to GitHub

```bash
# Create GitHub repo (use gh CLI or web UI)
gh repo create niivue/NiivueKit --public

# Push code
git remote add origin https://github.com/niivue/NiivueKit.git
git branch -M main
git push -u origin main
git push origin v1.0.0
```

## Phase 8: CI/CD Setup

### Step 8.1: Create GitHub Actions Workflow

```bash
mkdir -p .github/workflows

cat > .github/workflows/ci.yml << 'EOF'
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
EOF
```

### Step 8.2: Create Release Workflow

```bash
cat > .github/workflows/release.yml << 'EOF'
name: Release

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Build and test
        run: |
          swift build
          swift test

      - name: Create GitHub Release
        uses: softprops/action-gh-release@v1
        with:
          generate_release_notes: true
EOF
```

### Step 8.3: Verify CI/CD

```bash
# Push to trigger CI
git push origin main

# Check GitHub Actions
# https://github.com/niivue/NiivueKit/actions
```

## Phase 9: Final Verification

### Checklist

- [ ] `swift build` succeeds with zero warnings
- [ ] `swift test` passes all tests
- [ ] Code coverage > 80%
- [ ] Documentation generates without errors
- [ ] Example app builds and runs
- [ ] Resources load correctly (dist/, samples/)
- [ ] WASM modules load and execute
- [ ] Custom niivue:// URLs resolve
- [ ] All public APIs have DocC comments
- [ ] README.md is complete
- [ ] CHANGELOG.md is up to date
- [ ] Git tags are created (v1.0.0)
- [ ] GitHub Actions CI passes
- [ ] Package is installable via SPM

### Integration Test

Create a fresh test project:

```bash
# Create test app
mkdir /tmp/TestNiivueKit
cd /tmp/TestNiivueKit

# Initialize SPM package
swift package init --type executable

# Add NiivueKit dependency
cat > Package.swift << 'EOF'
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TestNiivueKit",
    platforms: [.iOS(.v16)],
    dependencies: [
        .package(url: "https://github.com/niivue/NiivueKit.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "TestNiivueKit",
            dependencies: ["NiivueKit"]
        )
    ]
)
EOF

# Build
swift build

# Should succeed
```

## Troubleshooting

### Build fails with "resources not found"

**Check:**
```bash
# Verify resources exist
ls -la Sources/NiivueKit/Resources/dist/
ls -la Sources/NiivueKit/Resources/samples/

# Verify Package.swift includes resources
grep -A 5 "resources:" Package.swift
```

**Fix:**
Ensure `.copy()` directives in Package.swift

### Tests fail with "Module not found"

**Check:**
```bash
# Verify import statements
grep "import NiivueKit" Tests/NiivueKitTests/**/*.swift
```

**Fix:**
Add `import NiivueKit` to all test files

### WebView shows blank screen in example app

**Check:**
```bash
# Verify Bundle.module references
grep "Bundle.module" Sources/NiivueKit/Networking/*.swift
```

**Fix:**
Replace `Bundle.main` with `Bundle.module`

### WASM fails to load

**Check MIME type:**
```swift
// In NiivueURLSchemeHandler.swift
case "wasm":
    return "application/wasm"  // Must be exact
```

### Access control errors

**Check public modifiers:**
```bash
# Find types that should be public
grep -r "final class\|struct\|protocol" Sources/NiivueKit/ | grep -v "private\|internal\|public"
```

**Fix:**
Add `public` modifier to all public-facing types

## Post-Migration Tasks

### Optional Enhancements

1. **Add SwiftUI views:**
   ```bash
   mkdir Sources/NiivueKit/UI
   # Create reusable SwiftUI components
   ```

2. **Add more samples:**
   ```bash
   # Download additional demo files
   curl -o Sources/NiivueKit/Resources/samples/CT_DEMO.nii.gz \
       https://niivue.github.io/niivue-demo-images/CT_DEMO.nii.gz
   ```

3. **Create DocC tutorial:**
   ```bash
   mkdir Documentation.docc
   # Add step-by-step tutorials
   ```

4. **Add GitHub templates:**
   ```bash
   mkdir -p .github/ISSUE_TEMPLATE
   # Create bug report template
   # Create feature request template
   ```

## Success Criteria

Migration is complete when:

1. Package builds cleanly (`swift build`)
2. All tests pass (`swift test`)
3. Documentation generates (`swift package generate-documentation`)
4. Example app runs and displays sample brain scan
5. Package installable via SPM in external project
6. CI/CD pipeline passes on GitHub Actions
7. Tagged release (v1.0.0) created

## Rollback Plan

If migration fails, the original Xcode project remains intact at:
```
/Users/leandroalmeida/niivue-ios-foundation/NiiVue/
```

No destructive operations are performed during migration - all steps are additive.

## Support

For issues during migration:
1. Check build errors log
2. Verify directory structure matches DIRECTORY_STRUCTURE.md
3. Compare against reference implementation in SPM_PACKAGE_DESIGN.md
4. Review Swift Package Manager documentation: https://swift.org/package-manager/

## Next Steps

After successful migration:
1. Announce release on niivue/niivue repository
2. Update main Niivue.js README to link to NiivueKit
3. Create blog post or tutorial
4. Submit to Swift Package Index
5. Consider CocoaPods/Carthage distribution (optional)

---

**Estimated Time:** 4-6 hours for complete migration
**Complexity:** Medium (mostly mechanical, some Swift knowledge required)
**Risk:** Low (non-destructive, original project untouched)
