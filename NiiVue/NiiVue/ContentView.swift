//
//  ContentView.swift
//  NiiVue
//
//  Created by Taylor Hanayik on 11/04/2024.
//  Task 4: Refactored to use new WebViewManager with async/await
//  Task 6: Added loading/error overlay
//

import SwiftUI
import WebKit
import Foundation
import UniformTypeIdentifiers

typealias MessageCallback = (String) -> Void

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var presented: Bool // To control the presentation state
    var onPick: (URL) -> Void // Closure to handle the picked document

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.data], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {
        // This function can be used to update the view when SwiftUI state changes.
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(_ documentPicker: DocumentPicker) {
            self.parent = documentPicker
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            parent.onPick(url) // Call the closure with the picked document URL
            parent.presented = false // Dismiss the picker
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.presented = false // Dismiss the picker when cancelled
        }

        // Helper function to check if the URL has a valid file extension
        private func isValidFileType(url: URL) -> Bool {
            let validExtensions = ["nii", "nii.gz"]
            return validExtensions.contains(where: url.lastPathComponent.lowercased().hasSuffix)
        }
    }
}

struct WebView: UIViewRepresentable {
    @ObservedObject var manager: WebViewManager

    func makeUIView(context: Context) -> WKWebView {
        return manager.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // This function can be used to update the view when SwiftUI state changes.
    }
}


struct ContentView: View {
    @EnvironmentObject var sharedData: SharedData
    @StateObject private var webViewManager = WebViewManager()

    @State private var documentPickerPresented = false
    @State private var settingsSheetPresented = false
    @State private var pickedDocumentURL: URL?
    @State private var base64EncodedString: String?
    @State private var sliceType = SliceTypes.Multiplanar.rawValue // default sliceType is multiplanar
    @State private var layout = LayoutTypes.Auto.rawValue // the default is Auto
    @State private var dragType = DragTypes.Contrast.rawValue // the default is Contrast
    @State private var show3dCrosshair = false
    @State private var show2dCrosshair = true
    @State private var penValue = PenTypes.Red.rawValue // default is red
    @State private var drawingEnabled = false // can the user draw?
    @State private var isFilled = true // is the pen filled or not?
    @State private var cornerText = false // put orientation labels in the corder or not?
    @State private var orientationCube = false // by default the 3D orientation cube is hidden
    @State private var radiological = false // use radiological convention or not in Niivue
    @State private var saveFileAlert = false
    @State private var showingSaveAlert = false
    @State private var incrementText = ""
    @State private var decrementText = ""
    @State private var sliceTypeText = ""

    /// Phase 2 Task 2: Check if we should load multiple volumes for UI testing
    private var isUITestLoadMultiple: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-test-load-multiple")
    }

    enum SliceTypes: Int, CaseIterable, Identifiable {
        case Axial = 0
        case Coronal = 1
        case Sagittal = 2
        case Multiplanar = 3
        case Render = 4
        var id: Self { self }
    }

    enum LayoutTypes: Int, CaseIterable, Identifiable {
        case Auto = 0
        case Column = 1
        case Grid = 2
        case Row = 3
        var id: Self { self }
    }

    enum DragTypes: Int, CaseIterable, Identifiable {
        case None = 0
        case Contrast = 1
        case Measure = 2
        case Pan = 3
        case Slicer3D = 4
        var id: Self { self }
    }

    enum PenTypes: Int, CaseIterable, Identifiable {
        case Erase = 0
        case Red = 1
        case Green = 2
        case Blue = 3
        case Yellow = 4
        case Cyan = 5
        case Purple = 6
        var id: Self { self }
    }

    // detect if iOS or macOS and set the drag setting text
#if os(iOS)
    let dragLabel = "Drag action (double tap)"
#elseif os(macOS)
    let dragLabel = "Drag action (right click)"
#endif

    private let maxBase64FallbackBytes = 25 * 1024 * 1024

    func encodeFileToBase64(url: URL) -> String? {
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize <= maxBase64FallbackBytes else {
            print("Skipping base64 fallback: file too large or size unknown (\(url.lastPathComponent))")
            return nil
        }

        do {
            let fileData = try Data(contentsOf: url)
            let base64String = fileData.base64EncodedString()
            return base64String
        } catch {
            print("Error reading file: \(error)")
            return nil
        }
    }

    func incrementSlice() {
        Task {
            do {
                if sliceType == SliceTypes.Axial.rawValue {
                    try await webViewManager.moveCrosshairInVox(0, 0, 1)
                } else if sliceType == SliceTypes.Coronal.rawValue {
                    try await webViewManager.moveCrosshairInVox(0, 1, 0)
                } else if sliceType == SliceTypes.Sagittal.rawValue {
                    try await webViewManager.moveCrosshairInVox(1, 0, 0)
                }
            } catch {
                print("Error incrementing slice: \(error)")
            }
        }
    }

    func decrementSlice() {
        Task {
            do {
                if sliceType == SliceTypes.Axial.rawValue {
                    try await webViewManager.moveCrosshairInVox(0, 0, -1)
                } else if sliceType == SliceTypes.Coronal.rawValue {
                    try await webViewManager.moveCrosshairInVox(0, -1, 0)
                } else if sliceType == SliceTypes.Sagittal.rawValue {
                    try await webViewManager.moveCrosshairInVox(-1, 0, 0)
                }
            } catch {
                print("Error decrementing slice: \(error)")
            }
        }
    }

    func rotateSliceType() {
        sliceType = (sliceType + 1) % 3
    }

    var shareButton: some View {
        Button(action: {
            Task {
                do {
                    if let base64Drawing = try await webViewManager.saveDrawing() {
                        // Save the drawing to disk
                        let date = Date()
                        let dateFormatter = DateFormatter()
                        dateFormatter.dateFormat = "YYYY-MM-dd_HH-mm-ss"
                        let dateString = dateFormatter.string(from: date) + ".nii.gz"
                        let fileName = pickedDocumentURL?.lastPathComponent ?? dateString

                        // Decode and save
                        if let data = Data(base64Encoded: base64Drawing) {
                            let url = URL.documentsDirectory.appendingPathComponent("drawing_\(dateString)_\(fileName)")
                            try data.write(to: url, options: [.atomic, .completeFileProtection])
                            print("Drawing saved to: \(url.path)")
                        }
                        showingSaveAlert = true
                    }
                } catch {
                    print("Error saving drawing: \(error)")
                }
            }
        })
        {
            Image(systemName: "square.and.arrow.up")
                .padding()
                .foregroundColor(.white)
        }
        .alert("Drawing saved to app folder", isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        }
    }

    // MARK: - HUD Overlay (Phase 2 Task 1)

    @ViewBuilder
    var hudOverlay: some View {
        if let locationString = webViewManager.lastLocationString {
            VStack {
                HStack {
                    Text(locationString)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .accessibilityIdentifier("niivue.hud")
                    Spacer()
                }
                Spacer()
            }
            .padding(8)
        }
    }

    // MARK: - Loading Overlay (Task 6)

    @ViewBuilder
    var loadingOverlay: some View {
        if !webViewManager.isReady && webViewManager.lastErrorMessage == nil {
            ZStack {
                Color.black.opacity(0.7)
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundColor(.white)
                }
            }
            .accessibilityIdentifier("niivue.loadingOverlay")
        } else if let errorMessage = webViewManager.lastErrorMessage {
            ZStack {
                Color.black.opacity(0.9)
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 40))
                        .foregroundColor(.yellow)
                    Text(errorMessage)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        webViewManager.reload()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
                }
                .padding()
            }
            .accessibilityIdentifier("niivue.errorOverlay")
        }
    }

    var body: some View {
        VStack {
            HStack {
                if drawingEnabled {
                    shareButton
                }

                // show the name of the opened file if it is a truthy value
                // -------------------------------------------------------------
                if let url = pickedDocumentURL {
                    Text("\(url.lastPathComponent)")
                        .foregroundStyle(.white)
                }
                // -------------------------------------------------------------
                Spacer() // Pushes the button to the right, and text to the left
                // -------------------------------------------------------------
                Button(action: {
                    drawingEnabled = false
                    documentPickerPresented = true
                })
                {
                    Image(systemName: "plus")
                        .padding()
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("niivue.addImage")
                .sheet(isPresented: $documentPickerPresented) {
                    DocumentPicker(presented: $documentPickerPresented) { url in
                        // Task 12: URL-based loading for imported files
                        Task {
                            var importedFile: FileImportService.ImportedFile?
                            do {
                                // Create library directory if needed
                                let libraryDir = FileImportService.defaultLibraryDirectory()
                                try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)

                                // Import the file (asCopy: true already creates a temp copy)
                                let fileImportService = FileImportService()
                                let imported = try await fileImportService.importDocument(
                                    at: url,
                                    destinationDirectory: libraryDir
                                )
                                importedFile = imported

                                // Register with the store for URL lookups
                                await webViewManager.importedFileStore.register(importedFile: imported)

                                // Update UI state
                                await MainActor.run {
                                    pickedDocumentURL = imported.localURL
                                }

                                // Load via URL instead of base64 (eliminates memory overhead)
                                let niivueURL = "niivue://app/files/\(imported.id)"
                                try await webViewManager.loadImageFromUrl(url: niivueURL, fileName: imported.originalFileName)
                            } catch {
                                print("Error importing file: \(error)")

                                let fallbackURL = importedFile?.localURL ?? url
                                let encodedString = await Task.detached(priority: .userInitiated) {
                                    encodeFileToBase64(url: fallbackURL)
                                }.value

                                // Fallback to base64 loading if URL-based fails (limited by maxBase64FallbackBytes)
                                await MainActor.run {
                                    pickedDocumentURL = fallbackURL
                                    if let encodedString {
                                        base64EncodedString = encodedString
                                    } else {
                                        webViewManager.lastErrorMessage = "Failed to load file (URL-based load failed; base64 fallback skipped)."
                                    }
                                }
                            }
                        }
                    }
                } // add image (plus) sheet end
                // -------------------------------------------------------------
                // adjust settings button
                Button(action: {
                    settingsSheetPresented = true
                })
                {
                    Image(systemName: "slider.horizontal.3")
                        .padding()
                        .foregroundColor(.white)
                }
                .accessibilityIdentifier("niivue.settings")
                .sheet(isPresented: $settingsSheetPresented) {
                    ScrollView {

                        VStack(alignment: .leading) {
                            //-----------------------------------------------------
                            // dismiss button in top right corner of sheet
                            HStack {
                                Spacer() // push button to the right (ios guidelines for sheets)
                                Button("Dismiss") {
                                    settingsSheetPresented.toggle()
                                }
                                .padding()
                            }
                            .padding()
                            //-----------------------------------------------------
                            // picker for the slice type
                            HStack {
                                Text("View type")
                                    .padding()
                                Spacer()
                                Picker("View mode", selection: $sliceType) {
                                    Text("Axial").tag(SliceTypes.Axial.rawValue)
                                    Text("Coronal").tag(SliceTypes.Coronal.rawValue)
                                    Text("Sagittal").tag(SliceTypes.Sagittal.rawValue)
                                    Text("Multiplanar").tag(SliceTypes.Multiplanar.rawValue)
                                    Text("Render").tag(SliceTypes.Render.rawValue)
                                }
                                .pickerStyle(.menu)
                                .padding()
                            }
                            //------------------------------------------------------
                            // picker for the layout type of multiplanar
                            HStack {
                                Text("Multiplanar layout ")
                                    .padding()
                                Spacer()
                                Picker("layout mode", selection: $layout) {
                                    Text("Auto").tag(LayoutTypes.Auto.rawValue)
                                    Text("Column").tag(LayoutTypes.Column.rawValue)
                                    Text("Grid").tag(LayoutTypes.Grid.rawValue)
                                    Text("Row").tag(LayoutTypes.Row.rawValue)
                                }
                                .pickerStyle(.menu)
                                .padding()
                            }
                            //------------------------------------------------------
                            // picker for the drag type
                            HStack {
                                Text(dragLabel)
                                    .padding()
                                Spacer()
                                Picker("Drag mode", selection: $dragType) {
                                    Text("None").tag(DragTypes.None.rawValue)
                                    Text("Contrast").tag(DragTypes.Contrast.rawValue)
                                    Text("Measure").tag(DragTypes.Measure.rawValue)
                                    Text("Pan").tag(DragTypes.Pan.rawValue)
                                    Text("Slicer3D").tag(DragTypes.Slicer3D.rawValue)
                                }
                                .pickerStyle(.menu)
                                .padding()
                            }
                            //------------------------------------------------------
                            // picker for the pen type
                            HStack {
                                Text("Pen type")
                                    .padding()
                                Spacer()
                                Picker("Pen type", selection: $penValue) {
                                    Label("Eraser", systemImage: "eraser").tag(PenTypes.Erase.rawValue)
                                    Label("Red", systemImage: "pencil").tag(PenTypes.Red.rawValue)
                                    Label("Green", systemImage: "pencil").tag(PenTypes.Green.rawValue)
                                    Label("Blue", systemImage: "pencil").tag(PenTypes.Blue.rawValue)
                                    Label("Cyan", systemImage: "pencil").tag(PenTypes.Cyan.rawValue)
                                    Label("Yellow", systemImage: "pencil").tag(PenTypes.Yellow.rawValue)
                                    Label("Purple", systemImage: "pencil").tag(PenTypes.Purple.rawValue)
                                }
                                .pickerStyle(.menu)
                                .padding()
                            }
                            //-------------------------------------------------------
                            // drawing enabled switch
                            HStack {
                                Toggle("Drawing enabled", isOn: $drawingEnabled)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // show 3d crosshair switch
                            HStack {
                                Toggle("3D crosshair", isOn: $show3dCrosshair)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // 2d crosshair switch
                            HStack {
                                Toggle("2D crosshair", isOn: $show2dCrosshair)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // filled pen switch
                            HStack {
                                Toggle("Auto fill pen", isOn: $isFilled)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // Corner labels switch
                            HStack {
                                Toggle("Corner text", isOn: $cornerText)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // orientation cube switch
                            HStack {
                                Toggle("Orientation cube", isOn: $orientationCube)
                                    .padding()
                            }
                            //-------------------------------------------------------
                            // radiological switch
                            HStack {
                                Toggle("Radiological convention", isOn: $radiological)
                                    .padding()
                            }

                            Spacer() // push content to top to the entire sheet layout is from top to bottom (default is centered)
                        }
                        // allow both medium (half height) and large (full height) sheets
                        // iphone: sheets can be medium or large
                        // ipad: detents are ignored. Sheets can only be large
                        // macOS: sheets are more like modal views (rectangles) centered in the app window
                        .presentationDetents([.medium, .large])
                        .presentationContentInteraction(.scrolls)
                    } // Vstack in sheet
                }
            } // HStack
            .padding(.horizontal) // Adds some padding on the left and right
            .background(Color.black)
            // -------------------------------------------------------------
            // show the drawing toolbar if drawing enabled and only showing axial, sagittal, or coronal slices
            if (drawingEnabled && sliceType != SliceTypes.Multiplanar.rawValue && sliceType != SliceTypes.Render.rawValue) {
                HStack {
                    Button(action: {
                        print("rotate slice type")
                        rotateSliceType()
                    })
                    {
                        let font = Font
                            .system(size: 18)
                            .monospaced()
                        Text(sliceTypeText).bold().font(font)
                    }
                    .padding()
                    Spacer()
                    //-------------------------------------------------
                    Text(decrementText)
                        .foregroundStyle(.white)
                    Button(action: {
                        print("decrement slice")
                        decrementSlice()
                    })
                    {
                        Image(systemName: "minus.rectangle.fill")
                            .padding([.bottom, .top, .trailing], 20)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderless)
                        .controlSize(.large)
                    // --------------------------------------------------
                    Text("Slice")
                        .foregroundStyle(.white)

                    //---------------------------------------------------
                    Button(action: {
                        print("increment slice")
                        incrementSlice()
                    })
                    {
                        Image(systemName: "plus.rectangle.fill")
                            .padding([.bottom, .top, .leading], 20)
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderless)
                        .controlSize(.large)
                    Text(incrementText)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal) // Adds some padding on the left and right
                .background(Color.black)
            }
            // -------------------------------------------------------------
            // show the webview with loading overlay and HUD
            ZStack {
                WebView(manager: webViewManager)
                    .onAppear {
                        webViewManager.load()
                    }
                    .background(Color.black)

                loadingOverlay
                hudOverlay

                // Phase 2 Task 2: Volume count display (shown in UI test mode for verification)
                if isUITestLoadMultiple {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text("\(webViewManager.volumes.count)")
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(4)
                                .accessibilityIdentifier("niivue.volumeCount")
                                .padding()
                        }
                    }
                }
            }
            .padding()
        }
        // Load sample image when webview becomes ready (Task 8: event-driven, Task 12: URL-based)
        .onChange(of: webViewManager.isReady) { newValue in
            if newValue {
                Task {
                    do {
                        // Phase 2 Task 2: UI test path loads multiple volumes
                        if isUITestLoadMultiple {
                            // Load same sample twice to get 2 volumes
                            print("[ContentView] Loading 2 volumes for UI test")
                            let sample1 = (url: "niivue://app/samples/T1w_DEMO.nii.gz", name: "T1w_DEMO.nii.gz")
                            let sample2 = (url: "niivue://app/samples/T1w_DEMO.nii.gz", name: "T1w_DEMO_2.nii.gz")
                            try await webViewManager.loadVolumesFromUrls([sample1, sample2])
                            print("[ContentView] loadVolumesFromUrls returned, volumes.count = \(webViewManager.volumes.count)")
                        } else {
                            // Normal path: load single demo image
                            let sampleURL = "niivue://app/samples/T1w_DEMO.nii.gz"
                            let fileName = "T1w_DEMO.nii.gz"
                            try await webViewManager.loadImageFromUrl(url: sampleURL, fileName: fileName)

                            // Update UI state to show filename
                            await MainActor.run {
                                pickedDocumentURL = Bundle.main.url(forResource: "T1w_DEMO.nii", withExtension: "gz", subdirectory: "samples")
                            }
                        }
                    } catch {
                        print("Error loading sample image: \(error)")

                        // Fallback to base64 if URL-based fails (limited by maxBase64FallbackBytes)
                        if !isUITestLoadMultiple, let url = Bundle.main.url(forResource: "T1w_DEMO.nii", withExtension: "gz", subdirectory: "samples") {
                            let encodedString = await Task.detached(priority: .userInitiated) {
                                encodeFileToBase64(url: url)
                            }.value

                            await MainActor.run {
                                pickedDocumentURL = url
                                if let encodedString {
                                    base64EncodedString = encodedString
                                } else {
                                    webViewManager.lastErrorMessage = "Failed to load bundled sample (base64 fallback skipped)."
                                }
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: base64EncodedString) { newValue in
            // Call a function or handle the change
            print("Base64 string updated")
            if let safeBase64 = newValue, let fileName = pickedDocumentURL?.lastPathComponent {
                Task {
                    do {
                        try await webViewManager.loadBase64Image(base64: safeBase64, fileName: fileName)
                    } catch {
                        print("Error loading base64 image: \(error)")
                    }
                }
            }
        }
        .onChange(of: sliceType) { newValue in
            print("sliceType updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setSliceType(sliceType: newValue)
                } catch {
                    print("Error setting slice type: \(error)")
                }
            }
            if (newValue == SliceTypes.Axial.rawValue) {
                incrementText = "S" // superior
                decrementText = "I" // inferior
                sliceTypeText = "A"
            } else if (newValue == SliceTypes.Coronal.rawValue) {
                incrementText = "A" // anterior
                decrementText = "P" // posterior
                sliceTypeText = "C"
            } else if (newValue == SliceTypes.Sagittal.rawValue) {
                incrementText = "R" // right
                decrementText = "L" // left
                sliceTypeText = "S"
            }
        }
        .onChange(of: layout) { newValue in
            print("layout updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setLayout(layout: newValue)
                } catch {
                    print("Error setting layout: \(error)")
                }
            }
        }
        .onChange(of: dragType) { newValue in
            print("drag type updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setDragMode(dragMode: newValue)
                } catch {
                    print("Error setting drag mode: \(error)")
                }
            }
        }
        .onChange(of: show3dCrosshair) { newValue in
            print("show3dCrosshair updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.set3dCrosshairVisible(visible: newValue)
                } catch {
                    print("Error setting 3D crosshair: \(error)")
                }
            }
        }
        .onChange(of: show2dCrosshair) { newValue in
            print("show2dCrosshair updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.set2dCrosshairVisible(visible: newValue)
                } catch {
                    print("Error setting 2D crosshair: \(error)")
                }
            }
        }
        .onChange(of: isFilled) { newValue in
            print("isFilled updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setPenValue(penValue: penValue, isFilled: newValue, drawingEnabled: drawingEnabled)
                } catch {
                    print("Error setting pen value: \(error)")
                }
            }
        }
        .onChange(of: drawingEnabled) { newValue in
            print("drawingEnabled updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setPenValue(penValue: penValue, isFilled: isFilled, drawingEnabled: newValue)
                } catch {
                    print("Error setting drawing enabled: \(error)")
                }
            }
        }
        .onChange(of: cornerText) { newValue in
            print("cornerText updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setCornerText(isCorners: newValue)
                } catch {
                    print("Error setting corner text: \(error)")
                }
            }
        }
        .onChange(of: orientationCube) { newValue in
            print("orientationCube updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setOrientationCube(isOrientationCube: newValue)
                } catch {
                    print("Error setting orientation cube: \(error)")
                }
            }
        }
        .onChange(of: radiological) { newValue in
            print("radiological updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setRadiological(isRadiological: newValue)
                } catch {
                    print("Error setting radiological: \(error)")
                }
            }
        }
        .onChange(of: penValue) { newValue in
            print("penValue updated to: \(newValue)")
            Task {
                do {
                    try await webViewManager.setPenValue(penValue: newValue, isFilled: isFilled, drawingEnabled: drawingEnabled)
                } catch {
                    print("Error setting pen value: \(error)")
                }
            }
        }
        .background(Color.black)
    }
}
