# DocC Documentation Structure

This document outlines the recommended DocC documentation structure for NiivueKit.

---

## Directory Structure

```
NiivueKit/
├── Sources/
│   └── NiivueKit/
│       ├── NiivueKit.docc/
│       │   ├── NiivueKit.md                    # Landing page
│       │   ├── Resources/
│       │   │   ├── logo.png
│       │   │   ├── multiplanar-screenshot.png
│       │   │   ├── 3d-render-screenshot.png
│       │   │   └── dicom-import-flow.png
│       │   ├── Tutorials/
│       │   │   ├── GettingStarted.tutorial     # Tutorial 1
│       │   │   ├── LoadingVolumes.tutorial     # Tutorial 2
│       │   │   ├── DicomImport.tutorial        # Tutorial 3
│       │   │   └── DrawingTools.tutorial       # Tutorial 4
│       │   ├── Articles/
│       │   │   ├── Architecture.md
│       │   │   ├── PerformanceOptimization.md
│       │   │   ├── CustomURLScheme.md
│       │   │   └── ThreadingModel.md
│       │   └── Extensions/
│       │       ├── WebViewManager-Commands.md
│       │       ├── WebViewManager-State.md
│       │       └── SessionStore.md
│       └── WebViewManager.swift               # With inline docs
└── Package.swift
```

---

## Landing Page: `NiivueKit.md`

```markdown
# ``NiivueKit``

WebGL-accelerated neuroimaging visualization for iOS and visionOS.

## Overview

NiivueKit brings the power of Niivue's medical imaging visualization to native iOS applications. Built on WebGL 2.0, it provides hardware-accelerated rendering of NIfTI volumes, DICOM series, 3D meshes, and tractography data.

![Multiplanar view showing brain MRI](multiplanar-screenshot)

### Key Features

- **Medical Imaging Formats**: NIfTI, DICOM, NRRD, MGH/MGZ, AFNI
- **3D Rendering**: Multiplanar reconstruction and volume rendering
- **Drawing Tools**: Interactive segmentation with undo/redo
- **Session Management**: Save and restore viewer state
- **SwiftUI & UIKit**: Native integration with both frameworks

### Supported Platforms

- iOS 15.0+
- visionOS 1.0+
- Swift 6.0+

---

## Topics

### Essentials

- <doc:GettingStarted>
- ``WebViewManager``
- ``VolumeInfo``
- ``SliceType``

### Loading Medical Data

- <doc:LoadingVolumes>
- ``WebViewManager/loadVolumeFromURL(_:)``
- ``WebViewManager/loadVolumeFromFile(_:)``
- ``WebViewManager/loadVolumeFromBase64(_:name:)``
- ``WebViewManager/loadDicomSeriesFromManifestURL(_:)``

### Visualization Control

- ``WebViewManager/setSliceType(_:)``
- ``WebViewManager/setColormap(volumeId:colormap:)``
- ``WebViewManager/setOpacity(volumeId:opacity:)``
- ``WebViewManager/setMultiplanarLayout(_:)``
- ``WebViewManager/setCrosshairPosition(voxel:)``

### Drawing and Segmentation

- <doc:DrawingTools>
- ``WebViewManager/setPenValue(_:isFilled:)``
- ``WebViewManager/setDrawOpacity(_:)``
- ``WebViewManager/setDrawColormap(_:)``
- ``WebViewManager/saveDrawing()``
- ``WebViewManager/drawUndo()``

### DICOM Import

- <doc:DicomImport>
- ``DicomSeriesStore``
- ``DicomSeriesStore/register(files:)``
- ``DicomSeriesStore/manifestText(for:)``

### Session Management

- ``SessionStore``
- ``SessionSnapshotV1``
- ``SessionStore/save(snapshot:)``
- ``SessionStore/load()``

### Advanced Topics

- <doc:Architecture>
- <doc:PerformanceOptimization>
- <doc:CustomURLScheme>
- <doc:ThreadingModel>

### Type Reference

- ``VolumeInfo``
- ``SliceType``
- ``MultiplanarLayout``
- ``NiivueError``

---

## See Also

- [Niivue Documentation](https://niivue.github.io/niivue/)
- [GitHub Repository](https://github.com/niivue/niivue-ios-foundation)
- [Example Projects](https://github.com/niivue/niivue-ios-foundation/tree/main/Examples)
```

---

## Tutorial 1: `GettingStarted.tutorial`

```swift
@Tutorial(time: 15) {
    @Intro(title: "Getting Started with NiivueKit") {
        Build your first neuroimaging app in 15 minutes.

        @Image(source: "niivuekit-logo.png", alt: "NiivueKit logo")
    }

    @Section(title: "Create Your Project") {
        @ContentAndMedia {
            Create a new SwiftUI app and add NiivueKit as a dependency.

            @Image(source: "xcode-new-project.png", alt: "Xcode new project screen")
        }

        @Steps {
            @Step {
                Open Xcode and create a new iOS App project.

                @Code(name: "ContentView.swift", file: "getting-started-01-empty.swift")
            }

            @Step {
                Add NiivueKit package dependency via File → Add Package Dependencies.

                Enter repository URL: `https://github.com/niivue/niivue-ios-foundation.git`

                @Image(source: "add-package.png", alt: "Add package dialog")
            }

            @Step {
                Import NiivueKit and create a WebViewManager.

                @Code(name: "ContentView.swift", file: "getting-started-02-import.swift")
            }
        }
    }

    @Section(title: "Build the User Interface") {
        @ContentAndMedia {
            Create a simple viewer UI with loading state and controls.
        }

        @Steps {
            @Step {
                Add a WebView container and loading indicator.

                @Code(name: "ContentView.swift", file: "getting-started-03-ui.swift")
            }

            @Step {
                Add view mode picker to toolbar.

                @Code(name: "ContentView.swift", file: "getting-started-04-picker.swift")
            }
        }
    }

    @Section(title: "Load Medical Data") {
        @ContentAndMedia {
            Load a sample brain MRI and display it in the viewer.

            @Image(source: "brain-loaded.png", alt: "Brain MRI in multiplanar view")
        }

        @Steps {
            @Step {
                Add task to load volume when view appears.

                @Code(name: "ContentView.swift", file: "getting-started-05-load.swift")
            }

            @Step {
                Run the app and see your first volume!

                The MNI152 brain template should appear in multiplanar view.

                @Image(source: "final-result.png", alt: "Completed app showing brain MRI")
            }
        }
    }

    @Assessments {
        @MultipleChoice {
            What method loads a volume from a remote URL?

            @Choice(isCorrect: false) {
                `loadVolume(url:)`

                @Justification(isCorrect: false) {
                    This method doesn't exist. The correct method specifies the source type.
                }
            }

            @Choice(isCorrect: true) {
                `loadVolumeFromURL(_:)`

                @Justification(isCorrect: true) {
                    Correct! This method loads from a URL string.
                }
            }

            @Choice(isCorrect: false) {
                `loadVolumeFromFile(_:)`

                @Justification(isCorrect: false) {
                    This method loads from a local file URL, not a remote URL.
                }
            }
        }

        @MultipleChoice {
            Which property indicates the WebView is ready for commands?

            @Choice(isCorrect: false) {
                `webViewManager.loaded`

                @Justification(isCorrect: false) {
                    This property doesn't exist.
                }
            }

            @Choice(isCorrect: true) {
                `webViewManager.isReady`

                @Justification(isCorrect: true) {
                    Correct! Wait for `isReady = true` before calling methods.
                }
            }

            @Choice(isCorrect: false) {
                `webViewManager.initialized`

                @Justification(isCorrect: false) {
                    This property doesn't exist.
                }
            }
        }
    }
}
```

---

## Tutorial 2: `LoadingVolumes.tutorial`

```swift
@Tutorial(time: 20) {
    @Intro(title: "Loading Volumes") {
        Learn all the ways to load medical imaging data into NiivueKit.

        @Image(source: "volume-loading.png", alt: "Different volume loading methods")
    }

    @Section(title: "Loading from URLs") {
        @ContentAndMedia {
            Load volumes from remote HTTP(S) URLs.
        }

        @Steps {
            @Step {
                Use `loadVolumeFromURL(_:)` for remote files.

                @Code(name: "LoadingExample.swift", file: "loading-01-url.swift")
            }

            @Step {
                Handle errors with proper do-catch blocks.

                @Code(name: "LoadingExample.swift", file: "loading-02-error.swift")
            }
        }
    }

    @Section(title: "Loading from Local Files") {
        @ContentAndMedia {
            Import volumes from the device file system using document picker.
        }

        @Steps {
            @Step {
                Add file importer modifier.

                @Code(name: "LoadingExample.swift", file: "loading-03-picker.swift")
            }

            @Step {
                Load selected file with security-scoped access.

                @Code(name: "LoadingExample.swift", file: "loading-04-file.swift")
            }
        }
    }

    @Section(title: "Loading from Base64") {
        @ContentAndMedia {
            Load volumes from base64-encoded data (useful for embedding small volumes).
        }

        @Steps {
            @Step {
                Convert file to base64 string.

                @Code(name: "LoadingExample.swift", file: "loading-05-base64.swift")
            }
        }
    }

    @Assessments {
        @MultipleChoice {
            When loading from document picker, what must you do?

            @Choice(isCorrect: true) {
                Call `startAccessingSecurityScopedResource()` and `stopAccessingSecurityScopedResource()`

                @Justification(isCorrect: true) {
                    Correct! iOS requires security-scoped access for document picker files.
                }
            }

            @Choice(isCorrect: false) {
                Nothing special, just load the URL

                @Justification(isCorrect: false) {
                    Without security-scoped access, you'll get "file not found" errors.
                }
            }
        }
    }
}
```

---

## Tutorial 3: `DicomImport.tutorial`

```swift
@Tutorial(time: 25) {
    @Intro(title: "DICOM Import") {
        Import and convert DICOM series using WebAssembly-powered dcm2niix.

        @Image(source: "dicom-import-flow.png", alt: "DICOM import workflow")
    }

    @Section(title: "Understanding DICOM Import") {
        @ContentAndMedia {
            Learn how NiivueKit converts DICOM series to NIfTI format.

            The conversion happens in-browser using dcm2niix compiled to WebAssembly.
        }

        @Steps {
            @Step {
                DICOM files are registered with `DicomSeriesStore`.

                @Code(name: "DicomExample.swift", file: "dicom-01-store.swift")
            }

            @Step {
                A manifest URL is generated listing all files.

                @Code(name: "DicomExample.swift", file: "dicom-02-manifest.swift")
            }

            @Step {
                The JavaScript bridge converts DICOM to NIfTI.

                @Code(name: "DicomExample.swift", file: "dicom-03-load.swift")
            }
        }
    }

    @Section(title: "Build DICOM Import UI") {
        @ContentAndMedia {
            Create a file picker for DICOM series import.
        }

        @Steps {
            @Step {
                Add DICOM file picker button.

                @Code(name: "DicomExample.swift", file: "dicom-04-button.swift")
            }

            @Step {
                Handle file selection and import.

                @Code(name: "DicomExample.swift", file: "dicom-05-import.swift")
            }
        }
    }
}
```

---

## Tutorial 4: `DrawingTools.tutorial`

```swift
@Tutorial(time: 20) {
    @Intro(title: "Drawing and Segmentation") {
        Use NiivueKit's drawing tools to create segmentations and annotations.

        @Image(source: "drawing-tools.png", alt: "Drawing tools in action")
    }

    @Section(title: "Enable Drawing Mode") {
        @ContentAndMedia {
            Configure pen settings and enable drawing.
        }

        @Steps {
            @Step {
                Set pen value (color) for drawing.

                @Code(name: "DrawingExample.swift", file: "drawing-01-pen.swift")
            }

            @Step {
                Adjust drawing opacity.

                @Code(name: "DrawingExample.swift", file: "drawing-02-opacity.swift")
            }
        }
    }

    @Section(title: "Save and Export") {
        @ContentAndMedia {
            Export segmentations as NIfTI files.
        }

        @Steps {
            @Step {
                Save drawing to Data.

                @Code(name: "DrawingExample.swift", file: "drawing-03-save.swift")
            }

            @Step {
                Write to file system.

                @Code(name: "DrawingExample.swift", file: "drawing-04-export.swift")
            }
        }
    }
}
```

---

## Article: `Architecture.md`

```markdown
# NiivueKit Architecture

Understand the internal architecture and data flow.

## Overview

NiivueKit bridges Swift and JavaScript, enabling native iOS apps to use Niivue's WebGL rendering engine.

## Component Diagram

```
┌─────────────────────────────────────────────────────────┐
│                    iOS App (Swift)                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────────────────┐       ┌─────────────────────┐     │
│  │  SwiftUI View    │──────▶│  WebViewManager     │     │
│  │  (ContentView)   │       │  (@MainActor)       │     │
│  └──────────────────┘       └──────────┬──────────┘     │
│                                        │                 │
│                                        ▼                 │
│                         ┌──────────────────────────┐     │
│                         │  WKWebView               │     │
│                         │  (React + Niivue)        │     │
│                         └──────────┬───────────────┘     │
│                                        │                 │
│  ┌─────────────────────────────────────┼──────────────┐  │
│  │  URL Scheme Handler                 │              │  │
│  │  (niivue://)                        │              │  │
│  └─────────────────────────────────────┼──────────────┘  │
└─────────────────────────────────────────┼────────────────┘
                                          │
                                          ▼
                              ┌──────────────────────┐
                              │  File System         │
                              │  (Imported files)    │
                              └──────────────────────┘
```

## Data Flow

### Volume Loading

1. Client calls `loadVolumeFromURL(_:)`
2. WebViewManager escapes URL using `JavaScriptQuote`
3. JavaScript command sent to WKWebView
4. React app calls `nv.loadVolumes()`
5. Niivue fetches and parses NIfTI
6. JavaScript callback fires `onVolumeLoaded`
7. Message sent to Swift via `postToIOS()`
8. WebViewManager updates `@Published var volumes`
9. SwiftUI UI auto-updates

### DICOM Import

1. User selects DICOM files via document picker
2. Files registered with `DicomSeriesStore` actor
3. Unique series ID generated
4. Manifest URL created: `niivue://app/dicom/{seriesId}/niivue-manifest.txt`
5. JavaScript fetches manifest (intercepted by URL scheme handler)
6. For each file, JavaScript fetches: `niivue://app/dicom/{seriesId}/{filename}`
7. WASM dcm2niix converts DICOM → NIfTI
8. NIfTI loaded into Niivue
9. Callback updates Swift state

## Threading Model

- **Main Thread**: WebViewManager, all WKWebView calls, @Published updates
- **Actor Isolation**: DicomSeriesStore, SessionStore (serialized access)
- **Background**: JavaScript execution (WKWebView internal thread)

## See Also

- ``WebViewManager``
- ``DicomSeriesStore``
- <doc:ThreadingModel>
```

---

## Symbol Documentation Example

In `WebViewManager.swift`:

```swift
/// Manages the WKWebView and provides a type-safe bridge to the Niivue JavaScript application.
///
/// `WebViewManager` is the primary interface for controlling neuroimaging visualization in NiivueKit.
/// It handles WebView lifecycle, JavaScript bridge communication, and state synchronization.
///
/// ## Topics
///
/// ### Initialization
/// - ``init(evaluator:initializationTimeoutNanoseconds:)``
///
/// ### WebView Access
/// - ``webView``
///
/// ### State Properties
/// - ``isReady``
/// - ``volumes``
/// - ``volumeSources``
/// - ``lastLocationString``
/// - ``lastErrorMessage``
///
/// ### Loading Volumes
/// - ``loadVolumeFromURL(_:)``
/// - ``loadVolumeFromFile(_:)``
/// - ``loadVolumeFromBase64(_:name:)``
/// - ``loadDicomSeriesFromManifestURL(_:)``
///
/// ### Visualization Control
/// - ``setSliceType(_:)``
/// - ``setColormap(volumeId:colormap:)``
/// - ``setOpacity(volumeId:opacity:)``
///
/// Example:
/// ```swift
/// @StateObject private var manager = WebViewManager()
///
/// var body: some View {
///     VStack {
///         if manager.isReady {
///             WebView(manager: manager)
///         }
///     }
///     .task {
///         try? await manager.loadVolumeFromURL(
///             "https://niivue.github.io/niivue-demo-images/mni152.nii.gz"
///         )
///     }
/// }
/// ```
@MainActor
final class WebViewManager: ObservableObject {
    // ...

    /// Loads a NIfTI volume from a remote URL.
    ///
    /// The volume is fetched asynchronously and rendered in the current view mode.
    /// The method returns after the JavaScript load command is sent, but before
    /// the volume is fully loaded. Monitor ``volumes`` property for completion.
    ///
    /// - Parameter url: The URL of the NIfTI file (.nii or .nii.gz format)
    /// - Throws: ``NiivueError/notReady`` if the WebView is not initialized
    /// - Throws: ``NiivueError/javascriptEvaluationFailed(underlying:)`` if the JavaScript execution fails
    ///
    /// Example:
    /// ```swift
    /// do {
    ///     try await webViewManager.loadVolumeFromURL(
    ///         "https://example.com/brain.nii.gz"
    ///     )
    ///     print("Volume loading started")
    /// } catch NiivueError.notReady {
    ///     print("WebView not ready yet")
    /// } catch {
    ///     print("Failed to load: \(error)")
    /// }
    /// ```
    ///
    /// - Note: Supports compressed (.nii.gz) and uncompressed (.nii) formats.
    /// - Important: Ensure ``isReady`` is `true` before calling this method.
    public func loadVolumeFromURL(_ url: String) async throws {
        // Implementation
    }
}
```

---

## Building Documentation

### Command Line

```bash
# Build documentation bundle
xcodebuild docbuild -scheme NiivueKit \
    -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
    -derivedDataPath .docbuild

# Convert to static site
xcrun docc process-archive transform-for-static-hosting \
    .docbuild/Build/Products/Debug-iphonesimulator/NiivueKit.doccarchive \
    --output-path docs \
    --hosting-base-path /niivue-ios-foundation
```

### Xcode

1. **Product → Build Documentation** (⌃⇧⌘D)
2. Documentation window opens with browseable docs
3. Share icon → Export for Website

### GitHub Pages Deployment

```yaml
# .github/workflows/docs.yml
name: Deploy Documentation

on:
  push:
    branches: [main]

jobs:
  deploy-docs:
    runs-on: macos-14
    steps:
      - uses: actions/checkout@v4

      - name: Build documentation
        run: |
          xcodebuild docbuild -scheme NiivueKit \
            -destination 'platform=iOS Simulator,name=iPhone 15 Pro'

      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./docs
```

---

**Result:** Documentation hosted at `https://niivue.github.io/niivue-ios-foundation/documentation/niivuekit/`
