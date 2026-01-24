# Migration Guide

This guide helps you migrate existing neuroimaging apps to NiivueKit.

---

## Table of Contents

1. [Migrating from Direct WKWebView Usage](#migrating-from-direct-wkwebview-usage)
2. [Migrating from Other iOS Imaging Libraries](#migrating-from-other-ios-imaging-libraries)
3. [Version Upgrade Guides](#version-upgrade-guides)
4. [API Compatibility](#api-compatibility)

---

## Migrating from Direct WKWebView Usage

If you were previously using Niivue directly in a WKWebView without NiivueKit, this section shows how to migrate to the structured SDK.

### Before: Manual WKWebView Setup

```swift
import WebKit

class OldViewController: UIViewController {
    var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()

        // Manual configuration
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: view.bounds, configuration: config)
        view.addSubview(webView)

        // Load local HTML
        let htmlPath = Bundle.main.path(forResource: "index", ofType: "html")!
        let htmlURL = URL(fileURLWithPath: htmlPath)
        webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())

        // Manual JavaScript calls
        webView.evaluateJavaScript("""
            window.addEventListener('DOMContentLoaded', function() {
                const nv = new Niivue();
                nv.attachToCanvas(document.getElementById('canvas'));
                nv.loadVolumes([{url: '\(volumeURL)'}]);
            });
        """) { result, error in
            if let error = error {
                print("Error: \(error)")
            }
        }
    }

    func changeColormap(to colormap: String) {
        // Raw JavaScript string manipulation
        let js = "nv.setColormap(nv.volumes[0].id, '\(colormap)');"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
```

### After: NiivueKit

```swift
import SwiftUI
import NiivueKit

struct NewContentView: View {
    @StateObject private var webViewManager = WebViewManager()
    @State private var currentColormap = "gray"

    var body: some View {
        VStack {
            if webViewManager.isReady {
                NiivueWebView(manager: webViewManager)
            } else {
                ProgressView("Loading...")
            }
        }
        .task {
            await loadInitialData()
        }
    }

    private func loadInitialData() async {
        do {
            // Type-safe, async/await API
            try await webViewManager.loadVolumeFromURL(volumeURL)
        } catch {
            print("Error: \(error)")
        }
    }

    func changeColormap(to colormap: String) async {
        guard let volumeId = webViewManager.volumes.first?.id else { return }

        do {
            // Type-safe method with proper error handling
            try await webViewManager.setColormap(
                volumeId: volumeId,
                colormap: colormap
            )
        } catch {
            print("Error: \(error)")
        }
    }
}

struct NiivueWebView: UIViewRepresentable {
    let manager: WebViewManager

    func makeUIView(context: Context) -> WKWebView {
        manager.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
```

### Key Improvements

| Old Approach | NiivueKit | Benefit |
|--------------|-----------|---------|
| Manual JavaScript strings | Type-safe Swift methods | Compile-time safety |
| String interpolation | JSON-safe escaping | Security |
| Callback-based | Async/await | Modern Swift |
| Manual error handling | Structured errors | Better debugging |
| No state management | Published properties | SwiftUI integration |
| Manual lifecycle | Automatic initialization | Simplicity |

---

### Migration Checklist

- [ ] Replace `WKWebView` initialization with `WebViewManager`
- [ ] Convert `evaluateJavaScript` calls to typed methods
- [ ] Replace callbacks with async/await
- [ ] Use published state (`@Published`) instead of manual observers
- [ ] Replace string-based volume IDs with `VolumeInfo` structs
- [ ] Migrate file loading to `loadVolumeFromFile()` with security-scoped access
- [ ] Replace manual script message handlers with WebViewManager's built-in handlers

---

### Step-by-Step Migration

#### Step 1: Add NiivueKit Dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/niivue/niivue-ios-foundation.git", from: "1.0.0")
]
```

#### Step 2: Replace WKWebView with WebViewManager

**Before:**
```swift
class MyViewController: UIViewController {
    var webView: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
    }

    func setupWebView() {
        let config = WKWebViewConfiguration()
        // ... manual setup
        webView = WKWebView(frame: view.bounds, configuration: config)
    }
}
```

**After:**
```swift
class MyViewController: UIViewController {
    let webViewManager = WebViewManager()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
    }

    func setupWebView() {
        // WebViewManager handles all configuration
        let webView = webViewManager.webView
        view.addSubview(webView)
        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
```

#### Step 3: Convert JavaScript Calls to Typed Methods

**Before:**
```swift
func loadVolume(url: String) {
    let js = """
        nv.loadVolumes([{url: '\(url)'}]).then(() => {
            console.log('Loaded');
        });
    """
    webView.evaluateJavaScript(js) { result, error in
        if let error = error {
            self.handleError(error)
        }
    }
}
```

**After:**
```swift
func loadVolume(url: String) async {
    do {
        try await webViewManager.loadVolumeFromURL(url)
        print("Loaded")
    } catch {
        handleError(error)
    }
}
```

#### Step 4: Use Published State for UI Updates

**Before:**
```swift
// Manual message handler
class ScriptHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "volumeLoaded" {
            DispatchQueue.main.async {
                self.updateUI()
            }
        }
    }
}
```

**After:**
```swift
// Automatic via Combine
struct MyView: View {
    @ObservedObject var manager: WebViewManager

    var body: some View {
        VStack {
            // UI automatically updates when manager.volumes changes
            Text("Volumes loaded: \(manager.volumes.count)")
        }
    }
}
```

---

## Migrating from Other iOS Imaging Libraries

### From Custom Metal Renderer

If you have a custom Metal-based NIfTI viewer:

**Advantages of NiivueKit:**
- No need to maintain Metal shaders
- Automatic multiplanar reconstruction
- 250+ scientific colormaps included
- Cross-platform consistency (matches web version)

**Trade-offs:**
- WebGL overhead vs direct Metal
- Less control over rendering pipeline
- Requires WKWebView (additional memory)

**When to Use NiivueKit:**
- Need rapid prototyping
- Want web/iOS feature parity
- Don't need real-time performance critical features
- Benefit from Niivue's active development

**When to Keep Metal:**
- Extreme performance requirements (AR/VR)
- Tight memory constraints
- Need visionOS spatial rendering optimizations
- Require custom rendering algorithms

### Migration Path

1. **Start with overlay mode**: Keep Metal renderer, add NiivueKit as optional viewer
2. **Feature parity check**: Ensure NiivueKit supports all your use cases
3. **Performance testing**: Compare with realistic datasets
4. **Gradual transition**: Replace Metal views one screen at a time

---

## Version Upgrade Guides

### Upgrading from 0.9.0-beta to 1.0.0

#### Breaking Changes

1. **WebViewManager initialization**

   **Before (0.9.x):**
   ```swift
   let manager = WebViewManager(htmlURL: customURL)
   ```

   **After (1.0.0):**
   ```swift
   // Custom URL no longer supported; uses bundled React app
   let manager = WebViewManager()
   ```

   **Reason:** Standardized on bundled React app for reliability.

2. **Volume loading signature**

   **Before (0.9.x):**
   ```swift
   func loadVolume(url: String, name: String?) async throws
   ```

   **After (1.0.0):**
   ```swift
   func loadVolumeFromURL(_ url: String) async throws
   ```

   **Migration:**
   ```swift
   // Old
   try await manager.loadVolume(url: volumeURL, name: "scan")

   // New
   try await manager.loadVolumeFromURL(volumeURL)
   // Name is auto-extracted from URL
   ```

3. **VolumeInfo structure**

   **Before (0.9.x):**
   ```swift
   struct VolumeInfo {
       let id: String
       let url: String
   }
   ```

   **After (1.0.0):**
   ```swift
   struct VolumeInfo: Codable, Equatable {
       let id: String
       let name: String
       let nFrame4D: Int
   }
   ```

   **Migration:**
   Use `.name` instead of `.url` for display purposes.

4. **Session persistence format**

   **Before (0.9.x):**
   Sessions were not versioned.

   **After (1.0.0):**
   `SessionSnapshotV1` with explicit versioning.

   **Migration:**
   Delete old sessions or manually migrate:
   ```swift
   // Clear old sessions
   try? await sessionStore.delete()
   ```

#### New Features

- DICOM import with `DicomSeriesStore`
- Drawing tools with undo/redo
- Custom URL scheme (`niivue://`)
- Comprehensive test coverage

#### Deprecated APIs

None in 1.0.0 (first stable release).

---

### Upgrading to Future Versions

#### 1.x.x to 2.0.0 (Hypothetical)

**Potential Breaking Changes:**

1. **iOS version requirement**
   - 1.x: iOS 15.0+
   - 2.0: iOS 16.0+ (for new SwiftUI features)

2. **Volume source enumeration**
   ```swift
   // 1.x
   func loadVolumeFromURL(_ url: String) async throws
   func loadVolumeFromFile(_ fileURL: URL) async throws
   func loadVolumeFromBase64(_ base64: String, name: String) async throws

   // 2.0 - Unified API
   enum VolumeSource {
       case url(String)
       case file(URL)
       case base64(String, name: String)
       case dicomSeries(String)
   }

   func loadVolume(from source: VolumeSource) async throws
   ```

   **Migration:**
   ```swift
   // Old
   try await manager.loadVolumeFromURL(url)

   // New
   try await manager.loadVolume(from: .url(url))
   ```

3. **Actor isolation**
   ```swift
   // 1.x
   @MainActor
   class WebViewManager: ObservableObject { }

   // 2.0 - Isolated actor
   actor WebViewManager {
       @MainActor
       func publishedState() -> ViewState { }
   }
   ```

---

## API Compatibility

### Semantic Versioning Guarantees

NiivueKit follows [Semantic Versioning 2.0.0](https://semver.org/):

- **Patch (1.0.x)**: Bug fixes, no API changes
- **Minor (1.x.0)**: New features, backwards compatible
- **Major (x.0.0)**: Breaking changes

### Stability Levels

| Component | Stability | Breaking Changes |
|-----------|-----------|------------------|
| WebViewManager public API | Stable | Only in major versions |
| VolumeInfo struct | Stable | Only in major versions |
| SliceType enum | Stable | Only in major versions |
| DicomSeriesStore | Stable | Only in major versions |
| SessionSnapshotV1 | Stable (versioned) | New struct in next version |
| Internal helpers | Unstable | May change in minor versions |

### Deprecation Policy

1. **Announcement**: Deprecated APIs marked with `@available(*, deprecated, message: "...")` in version N
2. **Grace Period**: At least one minor version (N.1) before removal
3. **Removal**: Only in next major version (N+1.0)

**Example:**

```swift
// Version 1.5.0 - Deprecation
@available(*, deprecated, message: "Use loadVolume(from:) instead. Will be removed in 2.0.")
func loadVolumeFromURL(_ url: String) async throws {
    try await loadVolume(from: .url(url))
}

// Version 1.6.0 - Still present
// Version 1.7.0 - Still present

// Version 2.0.0 - Removed
// Method no longer exists
```

---

## Migration Tools

### Automated Migration Script

For large codebases, use this script to identify deprecated APIs:

```bash
#!/bin/bash
# find-deprecated-apis.sh

echo "Searching for deprecated NiivueKit APIs..."

# Find loadVolumeFromURL calls
grep -rn "loadVolumeFromURL" --include="*.swift" .

# Find old VolumeInfo usage
grep -rn "VolumeInfo.*url" --include="*.swift" .

# Find direct WKWebView usage
grep -rn "WKWebView(frame:" --include="*.swift" .

echo "Done. Review results above."
```

### Xcode Fix-Its

NiivueKit provides compiler warnings with fix-it suggestions:

```swift
// Compiler warning with fix-it
try await manager.loadVolumeFromURL(url)
//           ~~~~~~~~~~~~~~~~~~~ Replace with 'loadVolume(from: .url(url))'
```

---

## Testing Your Migration

### Unit Test Migration

**Before:**
```swift
func testVolumeLoading() {
    let expectation = XCTestExpectation(description: "Load volume")

    webView.evaluateJavaScript("nv.loadVolumes([{url: 'test.nii'}])") { result, error in
        XCTAssertNil(error)
        expectation.fulfill()
    }

    wait(for: [expectation], timeout: 5.0)
}
```

**After:**
```swift
func testVolumeLoading() async throws {
    try await webViewManager.loadVolumeFromURL("test.nii")
    XCTAssertEqual(webViewManager.volumes.count, 1)
}
```

### Integration Test Checklist

After migration, verify:

- [ ] All volumes load correctly
- [ ] View mode changes work (axial, coronal, sagittal, 3D)
- [ ] Colormap changes apply
- [ ] Drawing tools function
- [ ] DICOM import works (if used)
- [ ] Session save/restore works
- [ ] No memory leaks (use Instruments)
- [ ] Performance is acceptable

---

## Getting Help

### Migration Support

- **GitHub Discussions**: [Ask migration questions](https://github.com/niivue/niivue-ios-foundation/discussions/categories/migration)
- **Migration Issues**: [Report migration blockers](https://github.com/niivue/niivue-ios-foundation/issues/new?template=migration.md)
- **Example Migrations**: See `Examples/MigrationExamples/` in repository

### Professional Services

For large-scale migrations, consider:
- Code review of migration plan
- Custom migration scripts
- Performance optimization consulting

Contact: support@niivue.com

---

**Last Updated:** January 4, 2026
**NiivueKit Version:** 1.0.0
