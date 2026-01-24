# Getting Started with NiivueKit

This tutorial will guide you through creating your first neuroimaging visualization app using NiivueKit. By the end, you'll have a functional brain MRI viewer running on iOS.

**Time to Complete:** ~15 minutes
**Prerequisites:**
- Xcode 16.0+
- iOS 15.0+ deployment target
- Basic Swift and SwiftUI knowledge

---

## Tutorial Overview

1. [Create a New Project](#step-1-create-a-new-project)
2. [Add NiivueKit Dependency](#step-2-add-niivuekit-dependency)
3. [Build the UI](#step-3-build-the-ui)
4. [Load Your First Volume](#step-4-load-your-first-volume)
5. [Add View Controls](#step-5-add-view-controls)
6. [Run on Device/Simulator](#step-6-run-on-devicesimulator)

---

## Step 1: Create a New Project

1. Open Xcode and select **File → New → Project**
2. Choose **iOS → App** template
3. Configure your project:
   - **Product Name:** BrainViewer
   - **Interface:** SwiftUI
   - **Language:** Swift
   - **Minimum Deployment:** iOS 15.0

4. Click **Next** and choose a save location

---

## Step 2: Add NiivueKit Dependency

### Option A: Swift Package Manager (Recommended)

1. In Xcode, select **File → Add Package Dependencies**
2. Enter the repository URL:
   ```
   https://github.com/niivue/niivue-ios-foundation.git
   ```
3. Select **Dependency Rule:** "Up to Next Major Version" with `1.0.0`
4. Click **Add Package**
5. Ensure **NiivueKit** is checked and click **Add Package** again

### Option B: Manual Integration

If you have the source code locally:

1. Drag the `NiiVue` folder into your Xcode project
2. Ensure "Copy items if needed" is checked
3. Add to your app target

---

## Step 3: Build the UI

Replace the contents of `ContentView.swift` with:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var webViewManager = WebViewManager()
    @State private var selectedView: SliceType = .multiplanar
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main Viewer
                if webViewManager.isReady {
                    GeometryReader { geometry in
                        NiivueWebViewRepresentable(manager: webViewManager)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                } else {
                    LoadingView()
                }

                // Bottom Toolbar
                Divider()
                bottomToolbar
            }
            .navigationTitle("Brain Viewer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    viewModePicker
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: - Subviews

    private var bottomToolbar: some View {
        HStack {
            if let location = webViewManager.lastLocationString {
                Text(location)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)
            }
            Spacer()
            if isLoading {
                ProgressView()
                    .padding(.trailing)
            }
        }
        .frame(height: 44)
        .background(Color(.systemGroupedBackground))
    }

    private var viewModePicker: some View {
        Menu {
            Picker("View Mode", selection: $selectedView) {
                Text("Multiplanar").tag(SliceType.multiplanar)
                Text("Axial").tag(SliceType.axial)
                Text("Coronal").tag(SliceType.coronal)
                Text("Sagittal").tag(SliceType.sagittal)
                Text("3D Render").tag(SliceType.render)
            }
        } label: {
            Label("View", systemImage: "cube")
        }
        .onChange(of: selectedView) { oldValue, newValue in
            Task {
                try? await webViewManager.setSliceType(newValue)
            }
        }
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Initializing NiivueKit...")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - WebView Representable

struct NiivueWebViewRepresentable: UIViewRepresentable {
    let manager: WebViewManager

    func makeUIView(context: Context) -> WKWebView {
        manager.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed
    }
}

#Preview {
    ContentView()
}
```

### Supporting Types

Create a new file `SliceType.swift`:

```swift
import Foundation

enum SliceType: Int {
    case axial = 0
    case coronal = 1
    case sagittal = 2
    case multiplanar = 3
    case render = 4
}
```

---

## Step 4: Load Your First Volume

Add this method to `ContentView`:

```swift
struct ContentView: View {
    // ... existing properties ...

    var body: some View {
        NavigationStack {
            // ... existing UI ...
        }
        .task {
            await loadInitialVolume()
        }
    }

    // MARK: - Data Loading

    private func loadInitialVolume() async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Wait for WebView to be ready
            while !webViewManager.isReady {
                try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }

            // Load a sample brain MRI from Niivue demo repository
            try await webViewManager.loadVolumeFromURL(
                "https://niivue.github.io/niivue-demo-images/mni152.nii.gz"
            )

            print("✅ Successfully loaded MNI152 brain template")

        } catch {
            errorMessage = "Failed to load volume: \(error.localizedDescription)"
            print("❌ Error loading volume: \(error)")
        }
    }
}
```

### What This Does

1. **Waits for initialization**: The WebView needs time to load the Niivue JavaScript library
2. **Loads a sample volume**: We use the MNI152 brain template, a standard reference brain
3. **Error handling**: Displays alerts if loading fails

---

## Step 5: Add View Controls

Let's add colormap selection and volume opacity controls.

Update `ContentView` with these new properties and UI:

```swift
struct ContentView: View {
    // ... existing properties ...
    @State private var selectedColormap = "gray"
    @State private var volumeOpacity: Double = 1.0

    var body: some View {
        NavigationStack {
            // ... existing VStack ...
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    colormapButton
                    viewModePicker
                }
            }
            .sheet(isPresented: $showingColormapPicker) {
                ColormapPickerView(
                    selectedColormap: $selectedColormap,
                    opacity: $volumeOpacity,
                    onApply: applyVisualizationSettings
                )
            }
        }
    }

    // MARK: - Controls

    @State private var showingColormapPicker = false

    private var colormapButton: some View {
        Button {
            showingColormapPicker = true
        } label: {
            Label("Colormap", systemImage: "paintpalette")
        }
    }

    private func applyVisualizationSettings() {
        Task {
            guard let volumeId = webViewManager.volumes.first?.id else { return }

            do {
                try await webViewManager.setColormap(
                    volumeId: volumeId,
                    colormap: selectedColormap
                )
                try await webViewManager.setOpacity(
                    volumeId: volumeId,
                    opacity: volumeOpacity
                )
            } catch {
                errorMessage = "Failed to apply settings: \(error.localizedDescription)"
            }
        }
    }
}
```

Create `ColormapPickerView.swift`:

```swift
import SwiftUI

struct ColormapPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedColormap: String
    @Binding var opacity: Double
    let onApply: () -> Void

    private let colormaps = [
        "gray", "hot", "cool", "winter", "bone",
        "jet", "viridis", "plasma", "inferno", "magma"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Colormap") {
                    Picker("Colormap", selection: $selectedColormap) {
                        ForEach(colormaps, id: \.self) { cmap in
                            Text(cmap.capitalized).tag(cmap)
                        }
                    }
                    .pickerStyle(.inline)
                }

                Section("Opacity") {
                    VStack(alignment: .leading) {
                        Text("Opacity: \(Int(opacity * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Slider(value: $opacity, in: 0...1)
                    }
                }
            }
            .navigationTitle("Visualization Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
```

---

## Step 6: Run on Device/Simulator

### Simulator

1. Select an iOS simulator (iPhone 15 Pro recommended)
2. Click **Run** (⌘R)
3. Wait for the app to launch
4. You should see the MNI152 brain template load in multiplanar view

### Physical Device

1. Connect your iPhone/iPad via USB
2. Select your device from the device menu
3. Click **Run**
4. If prompted, trust the developer certificate on your device:
   - **Settings → General → VPN & Device Management → [Your Developer Name] → Trust**
5. Launch the app

**Note**: WebGL rendering performs significantly better on physical devices than simulators.

---

## Testing Your App

### Expected Behavior

✅ **On Launch:**
- "Initializing NiivueKit..." loading screen appears
- After 1-2 seconds, brain MRI appears in multiplanar view
- Bottom toolbar shows crosshair coordinates

✅ **Interaction:**
- Tap and drag to move crosshair
- Pinch to zoom (on device)
- Use toolbar buttons to change view mode
- Colormap picker updates visualization

### Troubleshooting

❌ **"Failed to load volume" error**
- Check internet connection (sample is loaded from remote URL)
- Verify iOS 15.0+ (WebGL 2.0 required)
- Check console for detailed error messages

❌ **Black screen after loading**
- Try changing view mode using toolbar picker
- Check if `webViewManager.isReady` is true
- Verify WebView loaded successfully in console logs

❌ **App crashes on launch**
- Ensure deployment target is iOS 15.0+
- Check that all required files are included in build
- Verify Swift 6.0 toolchain

---

## Next Steps

### 1. Load Local Files

Add document picker to load NIfTI files from device:

```swift
@State private var showingFilePicker = false

Button("Open File") {
    showingFilePicker = true
}
.fileImporter(
    isPresented: $showingFilePicker,
    allowedContentTypes: [.data]
) { result in
    Task {
        do {
            let fileURL = try result.get()
            try await webViewManager.loadVolumeFromFile(fileURL)
        } catch {
            errorMessage = "Failed to load file: \(error.localizedDescription)"
        }
    }
}
```

### 2. Enable Drawing Tools

Add segmentation capabilities:

```swift
@State private var isDrawing = false
@State private var penValue: UInt8 = 1

Button(isDrawing ? "Stop Drawing" : "Start Drawing") {
    isDrawing.toggle()
    Task {
        if isDrawing {
            try? await webViewManager.setPenValue(penValue, isFilled: false)
        }
    }
}
```

### 3. Save Sessions

Persist viewer state across app launches:

```swift
private let sessionStore = SessionStore()

// On app close
func saveSession() async {
    let snapshot = SessionSnapshotV1(
        volumeSources: webViewManager.volumeSources,
        sliceType: selectedView,
        multiplanarLayout: .auto
    )
    try? await sessionStore.save(snapshot: snapshot)
}

// On app launch
func restoreSession() async {
    if let snapshot = try? await sessionStore.load() {
        // Restore volumes and settings
    }
}
```

---

## Advanced Tutorials

- [**Loading Volumes**](LoadingVolumes.md) - All volume loading methods
- [**DICOM Import**](DicomImport.md) - Working with DICOM series
- [**Drawing Tools**](DrawingTools.md) - Segmentation and annotations
- [**Multi-Volume Overlay**](MultiVolumeOverlay.md) - Blending multiple scans

---

## Complete Example Project

The full source code for this tutorial is available at:
```
Examples/MinimalSwiftUI/
```

Download and run:
```bash
git clone https://github.com/niivue/niivue-ios-foundation.git
cd niivue-ios-foundation/Examples/MinimalSwiftUI
open BrainViewer.xcodeproj
```

---

## API Reference

For detailed API documentation, see:
- [WebViewManager API](https://niivue.github.io/niivue-ios-foundation/documentation/niivuekit/webviewmanager)
- [SliceType Enumeration](https://niivue.github.io/niivue-ios-foundation/documentation/niivuekit/slicetype)
- [Full API Index](https://niivue.github.io/niivue-ios-foundation/documentation/niivuekit/)

---

## Need Help?

- **Troubleshooting Guide**: [Troubleshooting.md](Troubleshooting.md)
- **FAQ**: [FAQ.md](FAQ.md)
- **GitHub Issues**: [Report a bug](https://github.com/niivue/niivue-ios-foundation/issues)
- **Discussions**: [Ask questions](https://github.com/niivue/niivue-ios-foundation/discussions)

---

**Congratulations!** 🎉 You've built your first neuroimaging app with NiivueKit.
