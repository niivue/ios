# Urology CT Stone Evaluation App - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a mobile CT viewer for urologists with AI-powered kidney stone detection, measurements, 3D visualization, and reporting.

**Architecture:** SwiftUI app with NiiVue WebGL rendering via WKWebView, Core ML for kidney segmentation (TotalSegmentator), classical algorithms for stone detection via HU thresholding, and structured reporting. Adaptive layout for iPhone 16 Pro Max and iPad Pro.

**Tech Stack:** iOS 26, SwiftUI, WKWebView, NiiVue (WebGL), Core ML, Accelerate framework, Swift Concurrency (async/await, actors)

**Reference Design:** `docs/plans/2026-01-04-urology-ct-stone-app-design.md`

---

## Phase 1: Foundation

**Objective:** Basic CT viewing with NiiVue integration on iPhone and iPad

**Duration:** ~40 granular tasks

---

### Task 1.1: Create Xcode Project

**Files:**
- Create: `UrologyViewer/UrologyViewer.xcodeproj`
- Create: `UrologyViewer/UrologyViewer/UrologyViewerApp.swift`
- Create: `UrologyViewer/UrologyViewer/ContentView.swift`

**Step 1: Create new Xcode project**

```bash
cd /Users/leandroalmeida/niivue-ios-foundation
mkdir -p UrologyViewer
cd UrologyViewer
```

Open Xcode → File → New → Project → iOS App
- Product Name: `UrologyViewer`
- Team: Your team
- Organization Identifier: `com.niivue`
- Interface: SwiftUI
- Language: Swift
- Minimum Deployment: iOS 26.0

**Step 2: Verify project builds**

```bash
xcodebuild -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' build
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: initialize UrologyViewer Xcode project (iOS 26)"
```

---

### Task 1.2: Configure Project Settings

**Files:**
- Modify: `UrologyViewer/UrologyViewer.xcodeproj/project.pbxproj`
- Create: `UrologyViewer/UrologyViewer/Info.plist` (custom entries)

**Step 1: Update deployment target and capabilities**

In Xcode:
- Set Deployment Target: iOS 26.0
- Add Capability: App Sandbox (for file access)
- Add to Info.plist:

```xml
<key>NSDocumentsFolderUsageDescription</key>
<string>Access medical imaging files for viewing</string>
<key>UISupportsDocumentBrowser</key>
<true/>
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>DICOM</string>
        <key>LSHandlerRank</key>
        <string>Default</string>
        <key>LSItemContentTypes</key>
        <array>
            <string>org.nema.dicom</string>
            <string>public.data</string>
        </array>
    </dict>
</array>
```

**Step 2: Build to verify**

```bash
xcodebuild -project UrologyViewer.xcodeproj -scheme UrologyViewer build
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add .
git commit -m "chore: configure project settings and file access permissions"
```

---

### Task 1.3: Create App Architecture Folders

**Files:**
- Create: `UrologyViewer/UrologyViewer/Views/`
- Create: `UrologyViewer/UrologyViewer/ViewModels/`
- Create: `UrologyViewer/UrologyViewer/Models/`
- Create: `UrologyViewer/UrologyViewer/Services/`
- Create: `UrologyViewer/UrologyViewer/Bridge/`
- Create: `UrologyViewer/UrologyViewerTests/`

**Step 1: Create folder structure**

```bash
cd UrologyViewer/UrologyViewer
mkdir -p Views ViewModels Models Services Bridge Resources
cd ../
mkdir -p UrologyViewerTests
```

**Step 2: Add folders to Xcode project**

In Xcode, add groups for each folder to match file system.

**Step 3: Commit**

```bash
git add .
git commit -m "chore: create app architecture folder structure"
```

---

### Task 1.4: Copy NiiVue React Build from ios-foundation

**Files:**
- Copy: `NiiVue/React/dist/*` → `UrologyViewer/UrologyViewer/Resources/dist/`

**Step 1: Copy the existing React/NiiVue build**

```bash
cp -r /Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/dist \
      /Users/leandroalmeida/niivue-ios-foundation/UrologyViewer/UrologyViewer/Resources/
```

**Step 2: Add to Xcode project as folder reference**

In Xcode: Right-click Resources → Add Files → Select `dist` folder → Create folder references

**Step 3: Verify files are included**

Build the project - dist folder should be in app bundle.

**Step 4: Commit**

```bash
git add UrologyViewer/UrologyViewer/Resources/
git commit -m "feat: add NiiVue React build bundle"
```

---

### Task 1.5: Create URL Scheme Handler (Port from ios-foundation)

**Files:**
- Create: `UrologyViewer/UrologyViewer/Bridge/NiivueURLSchemeHandler.swift`
- Create: `UrologyViewer/UrologyViewerTests/NiivueURLSchemeHandlerTests.swift`

**Step 1: Write the failing test**

```swift
// UrologyViewerTests/NiivueURLSchemeHandlerTests.swift
import XCTest
@testable import UrologyViewer

final class NiivueURLSchemeHandlerTests: XCTestCase {

    func testDistRouteServesIndexHTML() async throws {
        let handler = NiivueURLSchemeHandler()
        let url = URL(string: "niivue://app/dist/index.html")!

        let data = try await handler.data(for: url)

        XCTAssertNotNil(data)
        XCTAssertTrue(data.count > 0)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/NiivueURLSchemeHandlerTests
```

Expected: FAIL - NiivueURLSchemeHandler not found

**Step 3: Implement URL Scheme Handler**

```swift
// UrologyViewer/Bridge/NiivueURLSchemeHandler.swift
import Foundation
import WebKit

/// Handles custom niivue:// URL scheme for serving bundled resources
final class NiivueURLSchemeHandler: NSObject, WKURLSchemeHandler {

    enum Route {
        case dist(path: String)
        case unknown
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        Task {
            do {
                let data = try await data(for: url)
                let mimeType = mimeType(for: url)
                let response = URLResponse(
                    url: url,
                    mimeType: mimeType,
                    expectedContentLength: data.count,
                    textEncodingName: mimeType.starts(with: "text") ? "utf-8" : nil
                )
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                urlSchemeTask.didFailWithError(error)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Cancellation not needed for local resources
    }

    // MARK: - Routing

    func route(for url: URL) -> Route {
        let path = url.path
        if path.hasPrefix("/dist/") {
            let distPath = String(path.dropFirst(6)) // Remove "/dist/"
            return .dist(path: distPath)
        }
        return .unknown
    }

    func data(for url: URL) async throws -> Data {
        switch route(for: url) {
        case .dist(let path):
            return try loadDistResource(path: path)
        case .unknown:
            throw URLError(.fileDoesNotExist)
        }
    }

    // MARK: - Resource Loading

    private func loadDistResource(path: String) throws -> Data {
        guard let distURL = Bundle.main.url(forResource: "dist", withExtension: nil) else {
            throw URLError(.fileDoesNotExist)
        }
        let fileURL = distURL.appendingPathComponent(path)
        return try Data(contentsOf: fileURL)
    }

    private func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html"
        case "js": return "application/javascript"
        case "css": return "text/css"
        case "json": return "application/json"
        case "wasm": return "application/wasm"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/NiivueURLSchemeHandlerTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add NiivueURLSchemeHandler for serving bundled resources"
```

---

### Task 1.6: Create WebView Manager

**Files:**
- Create: `UrologyViewer/UrologyViewer/Bridge/WebViewManager.swift`
- Create: `UrologyViewer/UrologyViewerTests/WebViewManagerTests.swift`

**Step 1: Write the failing test**

```swift
// UrologyViewerTests/WebViewManagerTests.swift
import XCTest
@testable import UrologyViewer

@MainActor
final class WebViewManagerTests: XCTestCase {

    func testWebViewManagerCreatesWebView() {
        let manager = WebViewManager()

        XCTAssertNotNil(manager.webView)
    }

    func testWebViewManagerUsesCustomScheme() {
        let manager = WebViewManager()
        let config = manager.webView.configuration

        XCTAssertTrue(config.urlSchemeHandler(forURLScheme: "niivue") != nil)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/WebViewManagerTests
```

Expected: FAIL - WebViewManager not found

**Step 3: Implement WebViewManager**

```swift
// UrologyViewer/Bridge/WebViewManager.swift
import Foundation
import WebKit
import SwiftUI

/// Manages the WKWebView instance that hosts NiiVue
@MainActor
final class WebViewManager: ObservableObject {

    let webView: WKWebView
    let urlSchemeHandler: NiivueURLSchemeHandler

    @Published var isLoaded = false
    @Published var loadError: Error?

    init() {
        self.urlSchemeHandler = NiivueURLSchemeHandler()

        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(urlSchemeHandler, forURLScheme: "niivue")

        // Enable inline media playback
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Configure preferences
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        self.webView = WKWebView(frame: .zero, configuration: config)
        self.webView.isInspectable = true // Enable Safari Web Inspector
    }

    func loadNiiVue() {
        let url = URL(string: "niivue://app/dist/index.html")!
        let request = URLRequest(url: url)
        webView.load(request)
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/WebViewManagerTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add WebViewManager for WKWebView hosting"
```

---

### Task 1.7: Create NiiVue SwiftUI View Wrapper

**Files:**
- Create: `UrologyViewer/UrologyViewer/Views/NiiVueView.swift`

**Step 1: Implement SwiftUI ViewRepresentable**

```swift
// UrologyViewer/Views/NiiVueView.swift
import SwiftUI
import WebKit

/// SwiftUI wrapper for the NiiVue WebView
struct NiiVueView: UIViewRepresentable {

    @ObservedObject var manager: WebViewManager

    func makeUIView(context: Context) -> WKWebView {
        manager.loadNiiVue()
        return manager.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Updates handled by WebViewManager
    }
}

#Preview {
    NiiVueView(manager: WebViewManager())
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add NiiVueView SwiftUI wrapper"
```

---

### Task 1.8: Create Main Content View with NiiVue

**Files:**
- Modify: `UrologyViewer/UrologyViewer/ContentView.swift`

**Step 1: Update ContentView to show NiiVue**

```swift
// UrologyViewer/ContentView.swift
import SwiftUI

struct ContentView: View {

    @StateObject private var webViewManager = WebViewManager()

    var body: some View {
        NiiVueView(manager: webViewManager)
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Run on simulator to verify NiiVue loads**

```bash
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Then run in Xcode - should see NiiVue canvas.

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: integrate NiiVue into main ContentView"
```

---

### Task 1.9: Create Study Model

**Files:**
- Create: `UrologyViewer/UrologyViewer/Models/Study.swift`
- Create: `UrologyViewer/UrologyViewerTests/StudyTests.swift`

**Step 1: Write the failing test**

```swift
// UrologyViewerTests/StudyTests.swift
import XCTest
@testable import UrologyViewer

final class StudyTests: XCTestCase {

    func testStudyInitialization() {
        let study = Study(
            id: UUID(),
            patientName: "John Doe",
            studyDate: Date(),
            modality: "CT",
            seriesCount: 1,
            fileURLs: []
        )

        XCTAssertEqual(study.patientName, "John Doe")
        XCTAssertEqual(study.modality, "CT")
    }

    func testStudyDisplayName() {
        let study = Study(
            id: UUID(),
            patientName: "Jane Smith",
            studyDate: Date(),
            modality: "CT",
            seriesCount: 2,
            fileURLs: []
        )

        XCTAssertTrue(study.displayName.contains("Jane Smith"))
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/StudyTests
```

Expected: FAIL - Study not found

**Step 3: Implement Study model**

```swift
// UrologyViewer/Models/Study.swift
import Foundation

/// Represents an imported imaging study
struct Study: Identifiable, Codable, Hashable {
    let id: UUID
    let patientName: String
    let studyDate: Date
    let modality: String
    let seriesCount: Int
    let fileURLs: [URL]

    var displayName: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return "\(patientName) - \(modality) - \(formatter.string(from: studyDate))"
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/StudyTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add Study model"
```

---

### Task 1.10: Create DICOM Importer Service

**Files:**
- Create: `UrologyViewer/UrologyViewer/Services/DICOMImporter.swift`
- Create: `UrologyViewer/UrologyViewerTests/DICOMImporterTests.swift`

**Step 1: Write the failing test**

```swift
// UrologyViewerTests/DICOMImporterTests.swift
import XCTest
@testable import UrologyViewer

final class DICOMImporterTests: XCTestCase {

    func testImporterDetectsDICOMFiles() async throws {
        let importer = DICOMImporter()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create fake DICOM file with magic bytes
        let dicomFile = tempDir.appendingPathComponent("test.dcm")
        var dicomData = Data(count: 132)
        dicomData.replaceSubrange(128..<132, with: "DICM".data(using: .ascii)!)
        try dicomData.write(to: dicomFile)

        let isDICOM = try await importer.isDICOMFile(at: dicomFile)

        XCTAssertTrue(isDICOM)

        // Cleanup
        try FileManager.default.removeItem(at: tempDir)
    }

    func testImporterRejectsNonDICOM() async throws {
        let importer = DICOMImporter()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create non-DICOM file
        let textFile = tempDir.appendingPathComponent("test.txt")
        try "Hello World".write(to: textFile, atomically: true, encoding: .utf8)

        let isDICOM = try await importer.isDICOMFile(at: textFile)

        XCTAssertFalse(isDICOM)

        // Cleanup
        try FileManager.default.removeItem(at: tempDir)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/DICOMImporterTests
```

Expected: FAIL - DICOMImporter not found

**Step 3: Implement DICOMImporter**

```swift
// UrologyViewer/Services/DICOMImporter.swift
import Foundation

/// Service for importing and validating DICOM files
actor DICOMImporter {

    /// Check if a file is a valid DICOM file by checking magic bytes
    func isDICOMFile(at url: URL) async throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        // DICOM files have "DICM" at byte offset 128
        guard let data = try handle.read(upToCount: 132) else {
            return false
        }

        guard data.count >= 132 else {
            return false
        }

        let magic = data.subdata(in: 128..<132)
        return magic == "DICM".data(using: .ascii)
    }

    /// Import DICOM files from a directory
    func importFromDirectory(at url: URL) async throws -> [URL] {
        let fileManager = FileManager.default

        guard url.startAccessingSecurityScopedResource() else {
            throw ImportError.accessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        let contents = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var dicomFiles: [URL] = []

        for fileURL in contents {
            if try await isDICOMFile(at: fileURL) {
                dicomFiles.append(fileURL)
            }
        }

        return dicomFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    enum ImportError: LocalizedError {
        case accessDenied
        case noDICOMFilesFound

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Could not access the selected folder"
            case .noDICOMFilesFound:
                return "No DICOM files found in the selected folder"
            }
        }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/DICOMImporterTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add DICOMImporter service with file validation"
```

---

### Task 1.11: Create Study Import View

**Files:**
- Create: `UrologyViewer/UrologyViewer/Views/StudyImportView.swift`

**Step 1: Implement file picker view**

```swift
// UrologyViewer/Views/StudyImportView.swift
import SwiftUI
import UniformTypeIdentifiers

struct StudyImportView: View {

    @Environment(\.dismiss) private var dismiss
    @Binding var importedStudyURL: URL?

    @State private var isImporting = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "doc.viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(.secondary)

                Text("Import CT Study")
                    .font(.title)
                    .fontWeight(.semibold)

                Text("Select a folder containing DICOM files")
                    .foregroundStyle(.secondary)

                Button {
                    isImporting = true
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                if let error = importError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .padding()
            .navigationTitle("Import Study")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $isImporting,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        importedStudyURL = url
                        dismiss()
                    }
                case .failure(let error):
                    importError = error.localizedDescription
                }
            }
        }
    }
}

#Preview {
    StudyImportView(importedStudyURL: .constant(nil))
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add StudyImportView with folder picker"
```

---

### Task 1.12: Create Window Preset Enum

**Files:**
- Create: `UrologyViewer/UrologyViewer/Models/WindowPreset.swift`
- Create: `UrologyViewer/UrologyViewerTests/WindowPresetTests.swift`

**Step 1: Write the failing test**

```swift
// UrologyViewerTests/WindowPresetTests.swift
import XCTest
@testable import UrologyViewer

final class WindowPresetTests: XCTestCase {

    func testSoftTissuePreset() {
        let preset = WindowPreset.softTissue

        XCTAssertEqual(preset.windowWidth, 400)
        XCTAssertEqual(preset.windowLevel, 40)
    }

    func testBonePreset() {
        let preset = WindowPreset.bone

        XCTAssertEqual(preset.windowWidth, 2000)
        XCTAssertEqual(preset.windowLevel, 500)
    }

    func testUrographicPreset() {
        let preset = WindowPreset.urographic

        XCTAssertEqual(preset.windowWidth, 300)
        XCTAssertEqual(preset.windowLevel, 50)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/WindowPresetTests
```

Expected: FAIL - WindowPreset not found

**Step 3: Implement WindowPreset**

```swift
// UrologyViewer/Models/WindowPreset.swift
import Foundation

/// CT window/level presets for different tissue types
enum WindowPreset: String, CaseIterable, Identifiable {
    case softTissue = "Soft Tissue"
    case bone = "Bone"
    case urographic = "Urographic"
    case lung = "Lung"

    var id: String { rawValue }

    /// Window width in Hounsfield Units
    var windowWidth: Int {
        switch self {
        case .softTissue: return 400
        case .bone: return 2000
        case .urographic: return 300
        case .lung: return 1500
        }
    }

    /// Window level (center) in Hounsfield Units
    var windowLevel: Int {
        switch self {
        case .softTissue: return 40
        case .bone: return 500
        case .urographic: return 50
        case .lung: return -600
        }
    }

    /// System image name for the preset
    var iconName: String {
        switch self {
        case .softTissue: return "figure.stand"
        case .bone: return "figure.wave"
        case .urographic: return "drop.fill"
        case .lung: return "lungs.fill"
        }
    }

    /// Calculate cal_min and cal_max for NiiVue
    var calMinMax: (min: Int, max: Int) {
        let min = windowLevel - windowWidth / 2
        let max = windowLevel + windowWidth / 2
        return (min, max)
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/WindowPresetTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add WindowPreset enum for CT window/level"
```

---

### Task 1.13: Create SliceType Enum

**Files:**
- Create: `UrologyViewer/UrologyViewer/Models/SliceType.swift`

**Step 1: Implement SliceType**

```swift
// UrologyViewer/Models/SliceType.swift
import Foundation

/// Slice orientation types for 2D viewing
enum SliceType: Int, CaseIterable, Identifiable {
    case axial = 0
    case coronal = 1
    case sagittal = 2
    case multiplanar = 3
    case render3D = 4

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .axial: return "Axial"
        case .coronal: return "Coronal"
        case .sagittal: return "Sagittal"
        case .multiplanar: return "MPR"
        case .render3D: return "3D"
        }
    }

    var iconName: String {
        switch self {
        case .axial: return "square.split.1x2"
        case .coronal: return "square.split.2x1"
        case .sagittal: return "square.lefthalf.filled"
        case .multiplanar: return "square.grid.2x2"
        case .render3D: return "cube"
        }
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add SliceType enum for view orientations"
```

---

### Task 1.14: Add JavaScript Bridge Commands to WebViewManager

**Files:**
- Modify: `UrologyViewer/UrologyViewer/Bridge/WebViewManager.swift`
- Create: `UrologyViewer/UrologyViewerTests/WebViewManagerCommandTests.swift`

**Step 1: Write the failing test**

```swift
// UrologyViewerTests/WebViewManagerCommandTests.swift
import XCTest
@testable import UrologyViewer

@MainActor
final class WebViewManagerCommandTests: XCTestCase {

    func testSetSliceTypeGeneratesCorrectJS() async throws {
        let manager = WebViewManager()

        // Test that the command is formatted correctly
        let command = manager.jsCommand(for: .setSliceType(.axial))

        XCTAssertEqual(command, "nv.setSliceType(0)")
    }

    func testSetWindowPresetGeneratesCorrectJS() async throws {
        let manager = WebViewManager()
        let preset = WindowPreset.bone

        let command = manager.jsCommand(for: .setWindowPreset(preset))

        XCTAssertTrue(command.contains("-500"))  // cal_min
        XCTAssertTrue(command.contains("1500"))  // cal_max
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/WebViewManagerCommandTests
```

Expected: FAIL - jsCommand not found

**Step 3: Add JS command generation to WebViewManager**

```swift
// Add to WebViewManager.swift

// MARK: - JavaScript Commands

enum NiiVueCommand {
    case setSliceType(SliceType)
    case setWindowPreset(WindowPreset)
    case loadVolume(url: String)
    case setZoom(Double)
}

extension WebViewManager {

    func jsCommand(for command: NiiVueCommand) -> String {
        switch command {
        case .setSliceType(let sliceType):
            return "nv.setSliceType(\(sliceType.rawValue))"

        case .setWindowPreset(let preset):
            let (min, max) = preset.calMinMax
            return "if(nv.volumes.length > 0) { nv.volumes[0].cal_min = \(min); nv.volumes[0].cal_max = \(max); nv.updateGLVolume(); }"

        case .loadVolume(let url):
            let escapedURL = url.replacingOccurrences(of: "\"", with: "\\\"")
            return "nv.loadVolumes([{url: \"\(escapedURL)\"}])"

        case .setZoom(let zoom):
            return "nv.scene.volScaleMultiplier = \(zoom); nv.drawScene();"
        }
    }

    func execute(_ command: NiiVueCommand) async throws {
        let js = jsCommand(for: command)
        try await webView.evaluateJavaScript(js)
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/WebViewManagerCommandTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add JavaScript command generation to WebViewManager"
```

---

### Task 1.15: Create Viewer Toolbar

**Files:**
- Create: `UrologyViewer/UrologyViewer/Views/ViewerToolbar.swift`

**Step 1: Implement toolbar view**

```swift
// UrologyViewer/Views/ViewerToolbar.swift
import SwiftUI

struct ViewerToolbar: View {

    @Binding var selectedSliceType: SliceType
    @Binding var selectedWindowPreset: WindowPreset

    var body: some View {
        HStack(spacing: 16) {
            // Slice type picker
            Menu {
                ForEach(SliceType.allCases) { sliceType in
                    Button {
                        selectedSliceType = sliceType
                    } label: {
                        Label(sliceType.displayName, systemImage: sliceType.iconName)
                    }
                }
            } label: {
                Label(selectedSliceType.displayName, systemImage: selectedSliceType.iconName)
                    .labelStyle(.titleAndIcon)
            }

            Divider()
                .frame(height: 24)

            // Window preset picker
            Menu {
                ForEach(WindowPreset.allCases) { preset in
                    Button {
                        selectedWindowPreset = preset
                    } label: {
                        Label(preset.rawValue, systemImage: preset.iconName)
                    }
                }
            } label: {
                Label(selectedWindowPreset.rawValue, systemImage: selectedWindowPreset.iconName)
                    .labelStyle(.titleAndIcon)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

#Preview {
    ViewerToolbar(
        selectedSliceType: .constant(.axial),
        selectedWindowPreset: .constant(.softTissue)
    )
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add ViewerToolbar with slice type and window preset pickers"
```

---

### Task 1.16: Create Main Viewer Screen

**Files:**
- Create: `UrologyViewer/UrologyViewer/Views/ViewerScreen.swift`

**Step 1: Implement main viewer screen**

```swift
// UrologyViewer/Views/ViewerScreen.swift
import SwiftUI

struct ViewerScreen: View {

    @StateObject private var webViewManager = WebViewManager()
    @State private var selectedSliceType: SliceType = .axial
    @State private var selectedWindowPreset: WindowPreset = .softTissue
    @State private var showingImport = false

    let studyURL: URL?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // NiiVue viewer
                NiiVueView(manager: webViewManager)
                    .ignoresSafeArea()

                // Toolbar overlay
                VStack {
                    Spacer()
                    ViewerToolbar(
                        selectedSliceType: $selectedSliceType,
                        selectedWindowPreset: $selectedWindowPreset
                    )
                }
            }
        }
        .onChange(of: selectedSliceType) { _, newValue in
            Task {
                try? await webViewManager.execute(.setSliceType(newValue))
            }
        }
        .onChange(of: selectedWindowPreset) { _, newValue in
            Task {
                try? await webViewManager.execute(.setWindowPreset(newValue))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingImport = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            StudyImportView(importedStudyURL: .constant(nil))
        }
    }
}

#Preview {
    NavigationStack {
        ViewerScreen(studyURL: nil)
    }
}
```

**Step 2: Build to verify**

```bash
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add ViewerScreen with toolbar integration"
```

---

### Task 1.17: Update ContentView with Navigation

**Files:**
- Modify: `UrologyViewer/UrologyViewer/ContentView.swift`

**Step 1: Update ContentView**

```swift
// UrologyViewer/ContentView.swift
import SwiftUI

struct ContentView: View {

    @State private var selectedStudyURL: URL?
    @State private var showingImport = true

    var body: some View {
        NavigationStack {
            Group {
                if let studyURL = selectedStudyURL {
                    ViewerScreen(studyURL: studyURL)
                        .navigationTitle("CT Viewer")
                        .navigationBarTitleDisplayMode(.inline)
                } else {
                    WelcomeView(showingImport: $showingImport)
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            StudyImportView(importedStudyURL: $selectedStudyURL)
        }
    }
}

struct WelcomeView: View {
    @Binding var showingImport: Bool

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 80))
                .foregroundStyle(.blue)

            Text("Urology CT Viewer")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("AI-powered kidney stone detection\nand surgical planning")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                showingImport = true
            } label: {
                Label("Import CT Study", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
```

**Step 2: Build and run to verify**

```bash
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add welcome screen and navigation flow"
```

---

### Task 1.18: Add Adaptive Layout for iPad

**Files:**
- Modify: `UrologyViewer/UrologyViewer/Views/ViewerScreen.swift`

**Step 1: Update ViewerScreen for iPad**

```swift
// Replace ViewerScreen.swift content
import SwiftUI

struct ViewerScreen: View {

    @StateObject private var webViewManager = WebViewManager()
    @State private var selectedSliceType: SliceType = .axial
    @State private var selectedWindowPreset: WindowPreset = .softTissue
    @State private var showingImport = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    let studyURL: URL?

    var body: some View {
        GeometryReader { geometry in
            if horizontalSizeClass == .regular {
                // iPad layout - side panel
                HStack(spacing: 0) {
                    // Main viewer
                    ZStack {
                        NiiVueView(manager: webViewManager)

                        VStack {
                            Spacer()
                            ViewerToolbar(
                                selectedSliceType: $selectedSliceType,
                                selectedWindowPreset: $selectedWindowPreset
                            )
                        }
                    }
                    .frame(width: geometry.size.width * 0.7)

                    Divider()

                    // Side panel
                    SidePanel()
                        .frame(width: geometry.size.width * 0.3)
                }
            } else {
                // iPhone layout - stacked
                ZStack {
                    NiiVueView(manager: webViewManager)
                        .ignoresSafeArea()

                    VStack {
                        Spacer()
                        ViewerToolbar(
                            selectedSliceType: $selectedSliceType,
                            selectedWindowPreset: $selectedWindowPreset
                        )
                    }
                }
            }
        }
        .onChange(of: selectedSliceType) { _, newValue in
            Task {
                try? await webViewManager.execute(.setSliceType(newValue))
            }
        }
        .onChange(of: selectedWindowPreset) { _, newValue in
            Task {
                try? await webViewManager.execute(.setWindowPreset(newValue))
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingImport = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
            }
        }
        .sheet(isPresented: $showingImport) {
            StudyImportView(importedStudyURL: .constant(nil))
        }
    }
}

struct SidePanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Stone Analysis")
                .font(.headline)
                .padding(.horizontal)

            Text("No stones detected yet.\nLoad a CT study to begin analysis.")
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            Spacer()
        }
        .padding(.top)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview("iPhone") {
    NavigationStack {
        ViewerScreen(studyURL: nil)
    }
}

#Preview("iPad") {
    NavigationStack {
        ViewerScreen(studyURL: nil)
    }
    .previewDevice("iPad Pro (12.9-inch)")
}
```

**Step 2: Build for both devices**

```bash
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
xcodebuild build -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPad Pro (12.9-inch)'
```

Expected: BUILD SUCCEEDED for both

**Step 3: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add adaptive layout for iPad with side panel"
```

---

### Task 1.19: Create DICOM Series Store (Port from ios-foundation)

**Files:**
- Create: `UrologyViewer/UrologyViewer/Services/DicomSeriesStore.swift`
- Create: `UrologyViewer/UrologyViewerTests/DicomSeriesStoreTests.swift`

**Step 1: Write the failing test**

```swift
// UrologyViewerTests/DicomSeriesStoreTests.swift
import XCTest
@testable import UrologyViewer

final class DicomSeriesStoreTests: XCTestCase {

    func testRegisterReturnsSeriesId() async throws {
        let store = DicomSeriesStore()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file = tempDir.appendingPathComponent("test.dcm")
        try Data("test".utf8).write(to: file)

        let seriesId = await store.register(files: [file])

        XCTAssertFalse(seriesId.isEmpty)

        try FileManager.default.removeItem(at: tempDir)
    }

    func testManifestListsFiles() async throws {
        let store = DicomSeriesStore()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let file1 = tempDir.appendingPathComponent("slice001.dcm")
        let file2 = tempDir.appendingPathComponent("slice002.dcm")
        try Data("test1".utf8).write(to: file1)
        try Data("test2".utf8).write(to: file2)

        let seriesId = await store.register(files: [file1, file2])
        let manifest = await store.manifestText(for: seriesId)

        XCTAssertEqual(manifest, "slice001.dcm\nslice002.dcm")

        try FileManager.default.removeItem(at: tempDir)
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/DicomSeriesStoreTests
```

Expected: FAIL - DicomSeriesStore not found

**Step 3: Implement DicomSeriesStore**

```swift
// UrologyViewer/Services/DicomSeriesStore.swift
import Foundation

/// Actor-based store for DICOM series registration and manifest generation
actor DicomSeriesStore {

    /// Maps seriesId -> (fileName -> original file URL)
    private var series: [String: [String: URL]] = [:]

    /// Register a set of DICOM files and return a unique series ID
    func register(files: [URL]) -> String {
        let seriesId = UUID().uuidString
        var fileMap: [String: URL] = [:]
        for file in files {
            fileMap[file.lastPathComponent] = file
        }
        series[seriesId] = fileMap
        return seriesId
    }

    /// Generate manifest text listing all filenames (sorted, newline-separated)
    func manifestText(for seriesId: String) -> String {
        guard let fileMap = series[seriesId] else { return "" }
        return fileMap.keys.sorted().joined(separator: "\n")
    }

    /// Resolve a filename within a series to its original file URL
    func url(for seriesId: String, fileName: String) -> URL? {
        return series[seriesId]?[fileName]
    }

    /// Get all file URLs for a series
    func files(for seriesId: String) -> [URL] {
        guard let fileMap = series[seriesId] else { return [] }
        return fileMap.values.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/DicomSeriesStoreTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add DicomSeriesStore actor for manifest-based loading"
```

---

### Task 1.20: Add DICOM Route to URL Scheme Handler

**Files:**
- Modify: `UrologyViewer/UrologyViewer/Bridge/NiivueURLSchemeHandler.swift`
- Modify: `UrologyViewer/UrologyViewerTests/NiivueURLSchemeHandlerTests.swift`

**Step 1: Add test for DICOM routes**

```swift
// Add to NiivueURLSchemeHandlerTests.swift

func testDicomManifestRoute() {
    let handler = NiivueURLSchemeHandler()
    let url = URL(string: "niivue://app/dicom/series123/niivue-manifest.txt")!

    let route = handler.route(for: url)

    if case .dicomManifest(let seriesId) = route {
        XCTAssertEqual(seriesId, "series123")
    } else {
        XCTFail("Expected dicomManifest route")
    }
}

func testDicomFileRoute() {
    let handler = NiivueURLSchemeHandler()
    let url = URL(string: "niivue://app/dicom/series123/slice001.dcm")!

    let route = handler.route(for: url)

    if case .dicomFile(let seriesId, let fileName) = route {
        XCTAssertEqual(seriesId, "series123")
        XCTAssertEqual(fileName, "slice001.dcm")
    } else {
        XCTFail("Expected dicomFile route")
    }
}
```

**Step 2: Run test to verify it fails**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/NiivueURLSchemeHandlerTests
```

Expected: FAIL - dicomManifest case not found

**Step 3: Update NiivueURLSchemeHandler with DICOM routes**

```swift
// Update NiivueURLSchemeHandler.swift

enum Route {
    case dist(path: String)
    case dicomManifest(seriesId: String)
    case dicomFile(seriesId: String, fileName: String)
    case unknown
}

// Update route(for:) method
func route(for url: URL) -> Route {
    let path = url.path
    let components = path.split(separator: "/").map(String.init)

    if path.hasPrefix("/dist/") {
        let distPath = String(path.dropFirst(6))
        return .dist(path: distPath)
    }

    // DICOM routes: /dicom/<seriesId>/niivue-manifest.txt or /dicom/<seriesId>/<filename>
    if components.count >= 3, components[0] == "dicom" {
        let seriesId = components[1]
        if components.count >= 3 {
            let fileName = components[2]
            if fileName == "niivue-manifest.txt" {
                return .dicomManifest(seriesId: seriesId)
            } else {
                return .dicomFile(seriesId: seriesId, fileName: fileName)
            }
        }
    }

    return .unknown
}
```

**Step 4: Run test to verify it passes**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:UrologyViewerTests/NiivueURLSchemeHandlerTests
```

Expected: PASS

**Step 5: Commit**

```bash
git add UrologyViewer/
git commit -m "feat: add DICOM manifest and file routes to URL scheme handler"
```

---

## Phase 1 Completion Checkpoint

At this point, Phase 1 Foundation should be complete with:

- [x] Xcode project configured for iOS 26
- [x] NiiVue React build integrated
- [x] URL scheme handler for serving resources
- [x] WebViewManager with JavaScript bridge
- [x] SwiftUI views (NiiVueView, ViewerScreen, ViewerToolbar)
- [x] Adaptive layout for iPhone/iPad
- [x] Study and WindowPreset models
- [x] DICOM importer service
- [x] DICOM series store for manifest loading
- [x] Study import UI

**Run full test suite:**

```bash
xcodebuild test -project UrologyViewer.xcodeproj -scheme UrologyViewer -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

Expected: All tests pass

---

## Phase 2: AI Pipeline (Tasks 2.1 - 2.20)

> Detailed tasks for Phase 2 will be expanded when Phase 1 is complete.

**High-Level Tasks:**

| Task | Description |
|------|-------------|
| 2.1 | Download and convert TotalSegmentator model to Core ML |
| 2.2 | Create VolumePreprocessor for CT normalization |
| 2.3 | Create PatchExtractor for 128³ tiles |
| 2.4 | Create KidneySegmentationService with Core ML inference |
| 2.5 | Create StoneDetector with HU thresholding |
| 2.6 | Create ConnectedComponentsAnalyzer |
| 2.7 | Create StoneMeasurement model |
| 2.8 | Create StoneLocationClassifier |
| 2.9 | Create SegmentationOverlayRenderer |
| 2.10 | Create StoneSummaryView |
| 2.11 | Integrate AI pipeline into ViewerScreen |
| 2.12 | Add progress indicator during analysis |
| 2.13 | Performance optimization and testing |
| 2.14-2.20 | Edge cases, error handling, UI refinement |

---

## Phase 3: Clinical Tools (Tasks 3.1 - 3.15)

**High-Level Tasks:**

| Task | Description |
|------|-------------|
| 3.1 | Create DistanceMeasurementTool |
| 3.2 | Create HUProbeTool |
| 3.3 | Add 3D volume rendering controls |
| 3.4 | Create ClipPlaneController |
| 3.5 | Create StoneListView with navigation |
| 3.6 | Add manual stone addition |
| 3.7 | Add stone deletion/refinement |
| 3.8 | Add Apple Pencil annotation (iPad) |
| 3.9 | Create UndoManager for measurements |
| 3.10-3.15 | Gesture handling, performance, testing |

---

## Phase 4: Polish & Scale (Tasks 4.1 - 4.15)

**High-Level Tasks:**

| Task | Description |
|------|-------------|
| 4.1 | Create ReportGenerator |
| 4.2 | Create PDFExporter |
| 4.3 | Add clipboard copy |
| 4.4 | Add share sheet integration |
| 4.5 | Create OnboardingView |
| 4.6 | Create SettingsView |
| 4.7 | Add error alerts and recovery |
| 4.8 | Add analytics/feedback collection |
| 4.9 | Create App Store screenshots |
| 4.10 | Configure TestFlight |
| 4.11-4.15 | Final testing, documentation, release |

---

## Appendix: Test Data

**Sample DICOM datasets for testing:**

1. **TCIA Cancer Imaging Archive** - Public kidney CT datasets
2. **Visible Human Project** - Public CT data
3. **Custom test fixtures** - Synthetic DICOM files for unit tests

**Create test fixture script:**

```bash
# scripts/create-test-fixtures.sh
mkdir -p UrologyViewerTests/Fixtures

# Create minimal DICOM-like test file
python3 -c "
import struct
# 128 byte preamble + DICM magic
data = b'\x00' * 128 + b'DICM'
with open('UrologyViewerTests/Fixtures/test.dcm', 'wb') as f:
    f.write(data)
"
```

---

*Implementation Plan generated by Claude Code (Opus 4.5) on January 4, 2026*
