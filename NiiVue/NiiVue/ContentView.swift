//
//  ContentView.swift
//  NiiVue
//
//  Created by Taylor Hanayik on 11/04/2024.
//

import SwiftUI
import WebKit
import Foundation
import UniformTypeIdentifiers

private func encodeFileToBase64(url: URL) -> String? {
    do {
        let fileData = try Data(contentsOf: url)
        return fileData.base64EncodedString()
    } catch {
        print("Error reading file: \(error)")
        return nil
    }
}

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
        // No need to implement anything here for the picker
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
            //            guard let url = urls.first, self.isValidFileType(url: url) else { return }
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

/// Prevent WKUserContentController from retaining its owner through the
/// script-message handler registration.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

/// Drives the NiiVue web app inside a WKWebView.
///
/// Every viewer command goes through `window.niivueBridge` (installed by
/// `React/src/bridge.ts`); the web app reports back over the script message
/// handlers registered below.
class WebViewManager: NSObject, ObservableObject, WKScriptMessageHandler {
    let webView: WKWebView

    /// True once the web app has attached NiiVue and installed `window.niivueBridge`.
    /// Nothing may be sent to the bridge before this flips.
    @Published var isViewerReady = false
    /// Latest crosshair position, as the JSON mm array NiiVue reports.
    @Published var location: String = ""

    private let contentController: WKUserContentController
    private let messageHandler: WeakScriptMessageHandler
    private let url: URL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist")! // promise that it will be there

    /// Message handler names the web app posts to.
    private static let channels = ["updateUI", "logMessage", "locationChange"]

    override init() {
        let controller = WKUserContentController()
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.allowsBackForwardNavigationGestures = false
        webView.underPageBackgroundColor = UIColor.black
        webView.isOpaque = false
        webView.backgroundColor = UIColor.clear
        webView.isInspectable = true
        // The viewer fills the web view; the native UI supplies all scrolling.
        webView.scrollView.bounces = false
        webView.scrollView.isScrollEnabled = false

        self.contentController = controller
        self.webView = webView
        self.messageHandler = WeakScriptMessageHandler()
        super.init()

        messageHandler.delegate = self
        for channel in Self.channels {
            controller.add(messageHandler, name: channel)
        }
    }

    deinit {
        for channel in Self.channels {
            contentController.removeScriptMessageHandler(forName: channel)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let body = message.body as? String ?? ""
        switch message.name {
        case "updateUI":
            isViewerReady = true
        case "logMessage":
            print("niivue: \(body)")
        case "locationChange":
            location = body
        default:
            break
        }
    }

    /// Write a base64 `.nii.gz` payload into the app's Documents folder.
    /// - Returns: the file URL on success.
    @discardableResult
    private func saveBase64StringToNifti(_ base64String: String, baseImageUrl: String) -> URL? {
        // make sure the following properties are added to Info.plist and set to YES
        // Application supports iTunes file sharing : YES
        // Supports opening documents in place : YES
        guard let data = Data(base64Encoded: base64String) else {
            print("Error: Base64 string is malformed.")
            return nil
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: Date())
        // The bridge always returns gzipped NIfTI, so name the output for what it
        // is rather than inheriting the source image's extension.
        var stem = (baseImageUrl as NSString).lastPathComponent
        for suffix in [".nii.gz", ".nii"] where stem.lowercased().hasSuffix(suffix) {
            stem = String(stem.dropLast(suffix.count))
            break
        }
        let id = UUID().uuidString.prefix(8)
        let url = URL.documentsDirectory.appendingPathComponent("drawing_\(dateString)_\(id)_\(stem).nii.gz")
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            print("Drawing written to \(url.lastPathComponent) (\(data.count) bytes)")
            return url
        } catch {
            print("Failed to write drawing:", error.localizedDescription)
            return nil
        }
    }

    // load the default page from the react app
    func load() {
        isViewerReady = false
        // Grant read access to the whole build directory, not just index.html —
        // the page pulls its JS/CSS bundles from ./assets.
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    /// Run a `window.niivueBridge` call, logging any JS-side failure.
    private func call(_ expression: String) {
        guard isViewerReady else {
            print("niivueBridge not ready; dropped \(expression)")
            return
        }
        webView.evaluateJavaScript("window.niivueBridge.\(expression)") { _, error in
            if let error {
                print("niivueBridge.\(expression) failed: \(error.localizedDescription)")
            }
        }
    }

    /// Hand the image to NiiVue. The payload is passed as a JS argument rather
    /// than interpolated into source — base64 volumes run to tens of megabytes.
    func loadBase64Image(base64: String, fileName: String, completion: ((Bool) -> Void)? = nil) {
        guard isViewerReady else {
            print("niivueBridge not ready; could not load \(fileName)")
            completion?(false)
            return
        }
        webView.callAsyncJavaScript(
            "await window.niivueBridge.loadBase64Image(base64, fileName); return true;",
            arguments: ["base64": base64, "fileName": fileName],
            in: nil,
            in: .page
        ) { result in
            switch result {
            case .success:
                completion?(true)
            case .failure(let error):
                print("loadBase64Image failed: \(error.localizedDescription)")
                completion?(false)
            }
        }
    }

    /// Export the drawing layer and write it to Documents.
    /// `saveVolume` is asynchronous in NiiVue 1.0, so this awaits the JS promise.
    func saveDrawing(baseImageUrl: String, completion: @escaping (Bool) -> Void) {
        guard isViewerReady else {
            completion(false)
            return
        }
        webView.callAsyncJavaScript(
            "return await window.niivueBridge.saveDrawing();",
            in: nil,
            in: .page
        ) { [weak self] result in
            switch result {
            case .success(let value):
                guard let base64 = value as? String, !base64.isEmpty else {
                    print("saveDrawing: nothing to save")
                    completion(false)
                    return
                }
                completion(self?.saveBase64StringToNifti(base64, baseImageUrl: baseImageUrl) != nil)
            case .failure(let error):
                print("saveDrawing failed: \(error.localizedDescription)")
                completion(false)
            }
        }
    }

    func setCrosshairColor() {
        call("setCrosshairColor()")
    }

    // set multiplanar layout in Niivue
    // 0 = auto
    // 1 = column
    // 2 = grid
    // 3 = row
    func setLayout(layout: Int) {
        call("setLayout(\(layout))")
    }

    // show the 3D crosshair or not in Niivue
    func set3dCrosshairVisible(visible: Bool) {
        call("set3dCrosshairVisible(\(visible))")
    }

    // show the 2D crosshair or not in Niivue
    func set2dCrosshairVisible(visible: Bool) {
        call("set2dCrosshairVisible(\(visible))")
    }

    // set sliceType in Niivue
    func setSliceType(sliceType: Int) {
        call("setSliceType(\(sliceType))")
    }

    // set drag mode in Niivue
    func setDragMode(dragMode: Int) {
        call("setDragMode(\(dragMode))")
    }

    // set pen value for drawing in Niivue
    func setPenValue(penValue: Int, isFilled: Bool, drawingEnabled: Bool) {
        call("setPenValue(\(penValue), \(isFilled), \(drawingEnabled))")
    }

    // show the L/R/A/P/S/I orientation labels or not.
    // NiiVue 1.0 dropped the corner-vs-edge placement option, so this is a
    // straight visibility toggle.
    func setOrientationText(visible: Bool) {
        call("setOrientationText(\(visible))")
    }

    // set orientation cube
    func setOrientationCube(isOrientationCube: Bool) {
        call("setOrientationCube(\(isOrientationCube))")
    }

    // set radiological or not
    func setRadiological(isRadiological: Bool) {
        call("setRadiological(\(isRadiological))")
    }

    // move slice by one vox in any plane
    func moveCrosshairInVox(_ x: Int, _ y: Int, _ z: Int) {
        call("moveCrosshairInVox(\(x),\(y),\(z))")
    }

}

struct WebView: UIViewRepresentable {
    let manager: WebViewManager

    func makeUIView(context: Context) -> WKWebView {
        return manager.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // This function can be used to update the view when SwiftUI state changes.
        // However, with the WebViewManager handling WebView actions, this may not be needed.
    }
}


struct ContentView: View {
    @EnvironmentObject var sharedData: SharedData
    @StateObject private var webViewManager = WebViewManager()
    @State private var documentPickerPresented = false
    @State private var settingsSheetPresented = false
    @State private var pickedDocumentURL: URL?
    @State private var pendingImageURL: URL?
    @State private var base64EncodedString: String?
    @State private var imageLoadRequest = 0
    @State private var sliceType = SliceTypes.Multiplanar.rawValue // default sliceType is multiplanar
    @State private var layout = LayoutTypes.Auto.rawValue // the default is Auto
    @State private var dragType = DragTypes.Contrast.rawValue // the default is Contrast
    @State private var show3dCrosshair = false
    @State private var show2dCrosshair = true
    @State private var penValue = PenTypes.Red.rawValue // default is red
    @State private var drawingEnabled = false // can the user draw?
    @State private var isFilled = true // is the pen filled or not?
    @State private var orientationText = true // show the L/R/A/P/S/I labels?
    @State private var orientationCube = false // by default the 3D orientation cube is hidden
    @State private var radiological = false // use radiological convention or not in Niivue
    @State private var showingSaveAlert = false
    @State private var saveAlertMessage = ""
    @State private var incrementText = ""
    @State private var decrementText = ""
    @State private var sliceTypeText = ""
    
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
    
    
    /// Read large volumes away from the main thread. Newer requests supersede
    /// older ones so a slow file read cannot replace a later selection.
    func loadImage(from url: URL) {
        imageLoadRequest += 1
        let request = imageLoadRequest
        pendingImageURL = url
        DispatchQueue.global(qos: .userInitiated).async {
            let base64 = encodeFileToBase64(url: url)
            DispatchQueue.main.async {
                guard request == imageLoadRequest, let base64 else { return }
                pendingImageURL = nil
                pickedDocumentURL = url
                base64EncodedString = base64
            }
        }
    }
    
    func incrementSlice() {
        if (sliceType == SliceTypes.Axial.rawValue) {
            webViewManager.moveCrosshairInVox(0, 0, 1)
        } else if (sliceType == SliceTypes.Coronal.rawValue) {
            webViewManager.moveCrosshairInVox(0, 1, 0)
        } else if (sliceType == SliceTypes.Sagittal.rawValue) {
            webViewManager.moveCrosshairInVox(1, 0, 0)
        }
    }
    
    func decrementSlice() {
        if (sliceType == SliceTypes.Axial.rawValue) {
            webViewManager.moveCrosshairInVox(0, 0, -1)
        } else if (sliceType == SliceTypes.Coronal.rawValue) {
            webViewManager.moveCrosshairInVox(0, -1, 0)
        } else if (sliceType == SliceTypes.Sagittal.rawValue) {
            webViewManager.moveCrosshairInVox(-1, 0, 0)
        }
    }
    
    func rotateSliceType() {
        sliceType = (sliceType + 1) % 3
    }
    
    var shareButton: some View {
        Button(action: {
            webViewManager.saveDrawing(baseImageUrl: pickedDocumentURL?.lastPathComponent ?? "image.nii.gz") { ok in
                saveAlertMessage = ok
                    ? "Drawing saved to the app folder."
                    : "Nothing was saved — draw something first."
                showingSaveAlert = true
            }
        })
        {
            Image(systemName: "square.and.arrow.up")
                .padding()
                .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
        }
    }

    /// Read the sample volume shipped in the bundle and hand it to the viewer.
    func loadDemoImage() {
        guard pickedDocumentURL == nil, pendingImageURL == nil else { return }
        guard let url = Bundle.main.url(forResource: "T1w_DEMO.nii", withExtension: "gz", subdirectory: "samples") else {
            print("bundled sample image is missing")
            return
        }
        // Setting pickedDocumentURL also puts the name in the top-left of the UI.
        loadImage(from: url)
    }

    func loadSelectedImage() {
        guard webViewManager.isViewerReady,
              let base64 = base64EncodedString,
              let url = pickedDocumentURL else { return }
        webViewManager.loadBase64Image(base64: base64, fileName: url.lastPathComponent) { success in
            if success && drawingEnabled {
                webViewManager.setPenValue(penValue: penValue, isFilled: isFilled, drawingEnabled: true)
            }
        }
    }

    func applyViewerSettings() {
        webViewManager.setSliceType(sliceType: sliceType)
        webViewManager.setLayout(layout: layout)
        webViewManager.setDragMode(dragMode: dragType)
        webViewManager.set3dCrosshairVisible(visible: show3dCrosshair)
        webViewManager.set2dCrosshairVisible(visible: show2dCrosshair)
        webViewManager.setPenValue(penValue: penValue, isFilled: isFilled, drawingEnabled: drawingEnabled)
        webViewManager.setOrientationText(visible: orientationText)
        webViewManager.setOrientationCube(isOrientationCube: orientationCube)
        webViewManager.setRadiological(isRadiological: radiological)
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
                    
//                    Text("\(sharedData.location)") TODO: implement
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
                        .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
                }
                .sheet(isPresented: $documentPickerPresented) {
                    DocumentPicker(presented: $documentPickerPresented) { url in
                        // Handle the picked document URL
                        loadImage(from: url)
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
                        .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
                }
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
                                Toggle("Orientation labels", isOn: $orientationText)
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
                            .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
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
                            .foregroundColor(.white) // Ensure the "+" icon is visible on a black background
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
            // show the webview
            WebView(manager: webViewManager)
                .onAppear {
                    webViewManager.load()
                } // onAppear
                .background(Color.black)
                .padding()
        }
        // The web app posts "updateUI" once NiiVue is attached and the bridge is
        // installed; that replaces the old fixed delay before the first load.
        .onChange(of: webViewManager.isViewerReady) { ready in
            if ready {
                loadDemoImage()
                loadSelectedImage()
                applyViewerSettings()
            }
        }
        .onChange(of: base64EncodedString) { _ in
            loadSelectedImage()
        }
        .onChange(of: sliceType) { newValue in
            print("sliceType updated to: \(newValue)")
            webViewManager.setSliceType(sliceType: newValue)
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
            webViewManager.setLayout(layout: newValue)
        }
        .onChange(of: dragType) { newValue in
            print("drag type updated to: \(newValue)")
            webViewManager.setDragMode(dragMode: newValue)
        }
        .onChange(of: show3dCrosshair) { newValue in
            print("show3dCrosshair updated to: \(newValue)")
            webViewManager.set3dCrosshairVisible(visible: newValue)
        }
        .onChange(of: show2dCrosshair) { newValue in
            print("show2dCrosshair updated to: \(newValue)")
            webViewManager.set2dCrosshairVisible(visible: newValue)
        }
        .onChange(of: isFilled) { newValue in
            print("isFilled updated to: \(newValue)")
            webViewManager.setPenValue(penValue: penValue, isFilled: newValue, drawingEnabled: drawingEnabled)
        }
        .onChange(of: drawingEnabled) { newValue in
            print("drawingEnabled updated to: \(newValue)")
            webViewManager.setPenValue(penValue: penValue, isFilled: isFilled, drawingEnabled: newValue)
        }
        .onChange(of: orientationText) { newValue in
            print("orientationText updated to: \(newValue)")
            webViewManager.setOrientationText(visible: newValue)
        }
        .onChange(of: orientationCube) { newValue in
            print("orientationCube updated to: \(newValue)")
            webViewManager.setOrientationCube(isOrientationCube: newValue)
        }
        .onChange(of: radiological) { newValue in
            print("radiological updated to: \(newValue)")
            webViewManager.setRadiological(isRadiological: newValue)
        }
        .onChange(of: penValue) { newValue in
            print("penValue updated to: \(newValue)")
            webViewManager.setPenValue(penValue: newValue, isFilled: isFilled, drawingEnabled: drawingEnabled)
        }
        .alert(saveAlertMessage, isPresented: $showingSaveAlert) {
            Button("OK", role: .cancel) { }
        }
        .background(Color.black)
    }
}
