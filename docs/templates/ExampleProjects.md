# Example Projects

This document outlines the structure and content for NiivueKit example projects.

---

## Project Structure

```
Examples/
├── MinimalSwiftUI/              # Simplest possible implementation
│   ├── BrainViewer.xcodeproj
│   ├── BrainViewer/
│   │   ├── ContentView.swift
│   │   ├── BrainViewerApp.swift
│   │   └── Assets.xcassets
│   └── README.md
│
├── UIKitIntegration/            # UIKit-based viewer
│   ├── UIKitViewer.xcodeproj
│   ├── UIKitViewer/
│   │   ├── ViewController.swift
│   │   ├── AppDelegate.swift
│   │   ├── SceneDelegate.swift
│   │   └── Main.storyboard
│   └── README.md
│
├── DicomViewer/                 # Complete DICOM workflow
│   ├── DicomViewer.xcodeproj
│   ├── DicomViewer/
│   │   ├── Views/
│   │   │   ├── ContentView.swift
│   │   │   ├── DicomImportView.swift
│   │   │   └── SeriesPickerView.swift
│   │   ├── ViewModels/
│   │   │   └── DicomViewModel.swift
│   │   └── Services/
│   │       └── DicomImportService.swift
│   └── README.md
│
└── AdvancedFeatures/            # Kitchen sink example
    ├── AdvancedViewer.xcodeproj
    ├── AdvancedViewer/
    │   ├── Views/
    │   │   ├── MainView.swift
    │   │   ├── DrawingToolsView.swift
    │   │   ├── VolumeListView.swift
    │   │   └── SettingsView.swift
    │   ├── ViewModels/
    │   │   └── ViewerViewModel.swift
    │   └── Models/
    │       ├── ViewerSettings.swift
    │       └── DrawingState.swift
    └── README.md
```

---

## Example 1: Minimal SwiftUI

**Path:** `Examples/MinimalSwiftUI/`

### BrainViewerApp.swift

```swift
import SwiftUI

@main
struct BrainViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### ContentView.swift

```swift
import SwiftUI
import NiivueKit

/// Minimal NiivueKit example - loads a single brain MRI.
struct ContentView: View {
    @StateObject private var manager = WebViewManager()

    var body: some View {
        Group {
            if manager.isReady {
                NiivueWebView(manager: manager)
            } else {
                ProgressView("Loading NiivueKit...")
            }
        }
        .task {
            // Load sample volume when ready
            try? await manager.loadVolumeFromURL(
                "https://niivue.github.io/niivue-demo-images/mni152.nii.gz"
            )
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

### README.md

```markdown
# Minimal SwiftUI Example

The simplest possible NiivueKit integration - just 30 lines of code!

## Features

- Loads MNI152 brain template from remote URL
- Displays in multiplanar view
- No controls or UI (for maximum simplicity)

## Running

1. Open `BrainViewer.xcodeproj`
2. Run on iPhone/iPad Simulator or Device (iOS 15.0+)
3. Wait 2-3 seconds for volume to load

## Code Walkthrough

1. **WebViewManager**: Manages WKWebView lifecycle
2. **task modifier**: Loads volume when view appears
3. **UIViewRepresentable**: Wraps WKWebView for SwiftUI

## Next Steps

See `UIKitIntegration` for UIKit usage, or `AdvancedFeatures` for full-featured viewer.
```

---

## Example 2: UIKit Integration

**Path:** `Examples/UIKitIntegration/`

### ViewController.swift

```swift
import UIKit
import NiivueKit

/// UIKit-based neuroimaging viewer using NiivueKit.
class ViewController: UIViewController {

    private var webViewManager: WebViewManager!
    private var loadingIndicator: UIActivityIndicatorView!
    private var toolbar: UIToolbar!
    private var statusLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Brain Viewer"
        view.backgroundColor = .systemBackground

        setupWebView()
        setupToolbar()
        setupLoadingIndicator()
        setupStatusLabel()

        loadInitialVolume()
    }

    private func setupWebView() {
        webViewManager = WebViewManager()

        let webView = webViewManager.webView
        view.addSubview(webView)

        webView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -44)
        ])

        // Observe state changes
        webViewManager.$isReady.sink { [weak self] isReady in
            if isReady {
                self?.loadingIndicator.stopAnimating()
            }
        }.store(in: &cancellables)

        webViewManager.$lastLocationString.sink { [weak self] location in
            self?.statusLabel.text = location ?? ""
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    private func setupToolbar() {
        toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: 44)
        ])

        let viewModeButton = UIBarButtonItem(
            title: "View",
            style: .plain,
            target: self,
            action: #selector(showViewModePicker)
        )

        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        toolbar.items = [viewModeButton, flexSpace]
    }

    private func setupLoadingIndicator() {
        loadingIndicator = UIActivityIndicatorView(style: .large)
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.hidesWhenStopped = true
        view.addSubview(loadingIndicator)

        NSLayoutConstraint.activate([
            loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        loadingIndicator.startAnimating()
    }

    private func setupStatusLabel() {
        statusLabel = UILabel()
        statusLabel.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        statusLabel.textColor = .secondaryLabel
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        toolbar.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 8),
            statusLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor)
        ])
    }

    private func loadInitialVolume() {
        Task { @MainActor in
            do {
                // Wait for ready
                while !webViewManager.isReady {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }

                try await webViewManager.loadVolumeFromURL(
                    "https://niivue.github.io/niivue-demo-images/mni152.nii.gz"
                )
            } catch {
                showError(error)
            }
        }
    }

    @objc private func showViewModePicker() {
        let alert = UIAlertController(
            title: "View Mode",
            message: nil,
            preferredStyle: .actionSheet
        )

        let modes: [(String, SliceType)] = [
            ("Multiplanar", .multiplanar),
            ("Axial", .axial),
            ("Coronal", .coronal),
            ("Sagittal", .sagittal),
            ("3D Render", .render)
        ]

        for (title, type) in modes {
            alert.addAction(UIAlertAction(title: title, style: .default) { [weak self] _ in
                Task {
                    try? await self?.webViewManager.setSliceType(type)
                }
            })
        }

        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        present(alert, animated: true)
    }

    private func showError(_ error: Error) {
        let alert = UIAlertController(
            title: "Error",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

import Combine
import WebKit
```

### README.md

```markdown
# UIKit Integration Example

Demonstrates NiivueKit integration with UIKit (without SwiftUI).

## Features

- Pure UIKit implementation
- Programmatic layout (no storyboards)
- Combine for state observation
- View mode picker
- Status bar with crosshair coordinates
- Loading indicator

## Key Differences from SwiftUI

1. Manual layout constraints
2. Combine publishers for state updates (`$isReady`, `$lastLocationString`)
3. UIBarButtonItem for controls
4. UIAlertController for pickers

## Running

Open `UIKitViewer.xcodeproj` and run on device/simulator.

## Target Audience

Developers maintaining existing UIKit apps who want to add neuroimaging visualization.
```

---

## Example 3: DICOM Viewer

**Path:** `Examples/DicomViewer/`

### DicomImportView.swift

```swift
import SwiftUI
import NiivueKit

struct DicomImportView: View {
    @ObservedObject var viewModel: DicomViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        viewModel.showFilePicker = true
                    } label: {
                        Label("Select DICOM Files", systemImage: "doc.badge.plus")
                    }
                    .fileImporter(
                        isPresented: $viewModel.showFilePicker,
                        allowedContentTypes: [.data],
                        allowsMultipleSelection: true
                    ) { result in
                        Task {
                            await viewModel.handleFileSelection(result)
                        }
                    }
                }

                if !viewModel.selectedFiles.isEmpty {
                    Section("Selected Files") {
                        Text("\(viewModel.selectedFiles.count) DICOM files")
                            .foregroundColor(.secondary)
                    }
                }

                if viewModel.isImporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text(viewModel.importStatus)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if !viewModel.errorMessage.isEmpty {
                    Section {
                        Text(viewModel.errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Import DICOM")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        Task {
                            await viewModel.importSeries()
                            if viewModel.errorMessage.isEmpty {
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.selectedFiles.isEmpty || viewModel.isImporting)
                }
            }
        }
    }
}
```

### DicomViewModel.swift

```swift
import Foundation
import NiivueKit
import SwiftUI

@MainActor
class DicomViewModel: ObservableObject {
    @Published var showFilePicker = false
    @Published var selectedFiles: [URL] = []
    @Published var isImporting = false
    @Published var importStatus = ""
    @Published var errorMessage = ""

    let webViewManager: WebViewManager
    let dicomStore = DicomSeriesStore()

    init(webViewManager: WebViewManager) {
        self.webViewManager = webViewManager
    }

    func handleFileSelection(_ result: Result<[URL], Error>) async {
        do {
            let urls = try result.get()
            selectedFiles = urls.filter { isDICOM($0) }

            if selectedFiles.isEmpty {
                errorMessage = "No valid DICOM files found in selection"
            } else {
                errorMessage = ""
            }
        } catch {
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }

    func importSeries() async {
        guard !selectedFiles.isEmpty else { return }

        isImporting = true
        importStatus = "Converting DICOM to NIfTI..."
        errorMessage = ""

        do {
            // Start security-scoped access
            let accessingURLs = selectedFiles.filter {
                $0.startAccessingSecurityScopedResource()
            }
            defer {
                accessingURLs.forEach {
                    $0.stopAccessingSecurityScopedResource()
                }
            }

            // Register with DicomSeriesStore
            let seriesId = await dicomStore.register(files: selectedFiles)
            let manifestURL = "niivue://app/dicom/\(seriesId)/niivue-manifest.txt"

            // Import via WebViewManager
            importStatus = "Loading series..."
            try await webViewManager.loadDicomSeriesFromManifestURL(manifestURL)

            importStatus = "Import complete"
        } catch {
            errorMessage = "Import failed: \(error.localizedDescription)"
        }

        isImporting = false
    }

    private func isDICOM(_ url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            return false
        }

        // Check for DICOM magic number "DICM" at offset 128
        guard data.count > 132 else { return false }
        let magic = data[128..<132]
        return magic == Data([0x44, 0x49, 0x43, 0x4D])
    }
}
```

### README.md

```markdown
# DICOM Viewer Example

Complete DICOM import workflow with series detection and validation.

## Features

- Multi-file DICOM selection
- DICOM header validation
- Progress indication during conversion
- Error handling with user-friendly messages
- Integration with DicomSeriesStore

## Architecture

- **DicomImportView**: SwiftUI form for file selection
- **DicomViewModel**: Business logic and state management
- **DicomSeriesStore**: Actor-based file registry

## Running

1. Open `DicomViewer.xcodeproj`
2. Run on device (simulator works but file picker is limited)
3. Tap "Import DICOM" button
4. Select DICOM files (sample data in `SampleData/`)
5. Wait for conversion (progress shown)
6. View imported series

## Sample Data

Download sample DICOM series:
- [Brain MRI](https://www.dicomlibrary.com/mri/1/)
- [CT Scan](https://www.dicomlibrary.com/ct/1/)

Extract and import via Files app.
```

---

## Example 4: Advanced Features

**Path:** `Examples/AdvancedFeatures/`

### Features Demonstrated

1. **Multi-Volume Overlay**
   - Load multiple volumes
   - Adjust individual opacities
   - Reorder overlay stack

2. **Drawing Tools**
   - Pen color/value selection
   - Opacity control
   - Undo/redo
   - Export as NIfTI

3. **Session Persistence**
   - Save current state
   - Restore on launch
   - Clear session

4. **Settings**
   - Colormap selection
   - View mode presets
   - Crosshair customization

### MainView.swift (Excerpt)

```swift
import SwiftUI
import NiivueKit

struct MainView: View {
    @StateObject private var viewModel = ViewerViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                NiivueWebView(manager: viewModel.webViewManager)

                if !viewModel.webViewManager.isReady {
                    LoadingOverlay()
                }
            }
            .navigationTitle("Advanced Viewer")
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarLeading) {
                    Menu {
                        Button("Open Volume...") {
                            viewModel.showFilePicker = true
                        }
                        Button("Import DICOM...") {
                            viewModel.showDicomImport = true
                        }
                        Divider()
                        Button("Save Session") {
                            Task { await viewModel.saveSession() }
                        }
                        Button("Load Session") {
                            Task { await viewModel.loadSession() }
                        }
                    } label: {
                        Label("File", systemImage: "folder")
                    }
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.showVolumeList = true
                    } label: {
                        Label("Volumes", systemImage: "square.stack.3d.up")
                            .badge(viewModel.webViewManager.volumes.count)
                    }

                    Button {
                        viewModel.showDrawingTools = true
                    } label: {
                        Label("Draw", systemImage: "pencil.tip.crop.circle")
                    }

                    Button {
                        viewModel.showSettings = true
                    } label: {
                        Label("Settings", systemImage: "gear")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showVolumeList) {
                VolumeListView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showDrawingTools) {
                DrawingToolsView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showSettings) {
                SettingsView(viewModel: viewModel)
            }
        }
    }
}
```

### README.md

```markdown
# Advanced Features Example

Kitchen sink example demonstrating all NiivueKit capabilities.

## Features

### Volume Management
- Load multiple volumes (URL, file, base64)
- Volume list with opacity sliders
- Reorder overlays via drag-and-drop
- Remove individual volumes

### Drawing & Segmentation
- Pen color picker (0-255 values)
- Opacity control
- Undo/redo support
- Export as NIfTI
- Clear all drawings

### Visualization
- Colormap selection (250+ options)
- View mode presets
- Multiplanar layout options
- Crosshair customization

### Session Management
- Save viewer state
- Auto-restore on launch
- Clear session

### DICOM Import
- Series detection
- Progress reporting
- Validation

## Running

Open `AdvancedViewer.xcodeproj` and run.

## Code Organization

- `Views/`: SwiftUI views
- `ViewModels/`: Business logic and state
- `Models/`: Data structures
- `Services/`: Shared services

## Educational Value

This example demonstrates:
- MVVM architecture with SwiftUI
- Combine for state management
- Async/await patterns
- Actor isolation for thread safety
- Error handling best practices
```

---

## Testing Example Projects

### Automated Tests

Each example project includes basic tests:

```swift
// MinimalSwiftUITests.swift
import XCTest
@testable import BrainViewer

final class MinimalSwiftUITests: XCTestCase {
    func testWebViewManagerInitialization() async {
        let manager = WebViewManager()
        XCTAssertNotNil(manager.webView)
        XCTAssertFalse(manager.isReady)
    }

    func testVolumeLoading() async throws {
        let manager = WebViewManager()

        // Wait for ready
        for _ in 0..<100 {
            if manager.isReady { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertTrue(manager.isReady, "WebView should be ready within 10s")

        // Load volume
        try await manager.loadVolumeFromURL(
            "https://niivue.github.io/niivue-demo-images/mni152.nii.gz"
        )

        // Wait for volume to appear
        for _ in 0..<50 {
            if !manager.volumes.isEmpty { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(manager.volumes.count, 1)
        XCTAssertEqual(manager.volumes.first?.name, "mni152.nii.gz")
    }
}
```

---

## Distribution

### GitHub Structure

```
niivue-ios-foundation/
├── Examples/
│   ├── README.md                 # Index of all examples
│   ├── MinimalSwiftUI/
│   ├── UIKitIntegration/
│   ├── DicomViewer/
│   └── AdvancedFeatures/
└── SampleData/                   # Sample NIfTI/DICOM files
    ├── brain-mri.nii.gz
    ├── dicom-series/
    │   ├── slice001.dcm
    │   ├── slice002.dcm
    │   └── ...
    └── README.md
```

### Examples README.md

```markdown
# NiivueKit Examples

## Quick Start

Choose an example based on your needs:

| Example | Use Case | Complexity | Time |
|---------|----------|------------|------|
| **MinimalSwiftUI** | First-time users | ⭐ Basic | 5 min |
| **UIKitIntegration** | UIKit apps | ⭐⭐ Intermediate | 15 min |
| **DicomViewer** | DICOM workflows | ⭐⭐⭐ Advanced | 30 min |
| **AdvancedFeatures** | Full feature reference | ⭐⭐⭐⭐ Expert | 1 hour |

## Running Examples

1. Clone repository:
   ```bash
   git clone https://github.com/niivue/niivue-ios-foundation.git
   cd niivue-ios-foundation/Examples
   ```

2. Open desired example project:
   ```bash
   open MinimalSwiftUI/BrainViewer.xcodeproj
   ```

3. Build and run (⌘R)

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 16.0+
- iOS 15.0+ device or simulator

## Sample Data

Sample NIfTI and DICOM files are provided in `SampleData/`.
See [SampleData/README.md](SampleData/README.md) for descriptions.
```

---

**Last Updated:** January 4, 2026
