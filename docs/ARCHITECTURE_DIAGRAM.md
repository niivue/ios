# NiivueKit Architecture Diagram

Visual representation of the NiivueKit package architecture and component relationships.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Consumer iOS App                        │
│  ┌───────────────────────────────────────────────────────┐  │
│  │                    SwiftUI View                       │  │
│  │  @StateObject var manager = WebViewManager()         │  │
│  └───────────────────────────┬───────────────────────────┘  │
│                              │ imports                       │
└──────────────────────────────┼───────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                         NiivueKit                            │
│                   Swift Package Manager                      │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Public API (NiivueKit.swift)           │   │
│  │  - WebViewManager                                    │   │
│  │  - FileImportService                                 │   │
│  │  - SessionStore                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                               │
│  ┌──────────┬──────────┬──────────┬──────────┬──────────┐  │
│  │   Core   │Networking│ Services │Extensions│  Models  │  │
│  └──────────┴──────────┴──────────┴──────────┴──────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────┐   │
│  │               Bundled Resources                      │   │
│  │  - dist/ (React app, 3.9MB)                         │   │
│  │  - samples/ (Demo files, 4.2MB)                     │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────┐
│                      WKWebView Runtime                       │
│  ┌───────────────────────────────────────────────────────┐  │
│  │              React Application (dist/)                │  │
│  │  - Niivue.js (WebGL rendering)                       │  │
│  │  - dcm2niix.wasm (DICOM conversion)                  │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

## Component Layer Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                              NiivueKit Layers                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                         Public API Layer                        │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │   │
│  │  │WebViewManager│  │FileImport    │  │SessionStore  │          │   │
│  │  │  @MainActor  │  │  Service     │  │              │          │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                           │
│                              ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        Core Layer                               │   │
│  │  ┌────────────────────┐  ┌────────────────────┐                │   │
│  │  │ JavaScriptEvaluating│  │ JavaScriptQuote    │                │   │
│  │  │    (Protocol)       │  │   (Utility)        │                │   │
│  │  └────────────────────┘  └────────────────────┘                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                           │
│                              ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      Networking Layer                           │   │
│  │  ┌──────────────────────┐  ┌──────────────────────┐            │   │
│  │  │NiivueURLScheme       │  │ NiivueURLRouter      │            │   │
│  │  │   Handler            │  │  (URL Routing)       │            │   │
│  │  │(WKURLSchemeHandler)  │  │                      │            │   │
│  │  └──────────────────────┘  └──────────────────────┘            │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                           │
│                              ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                       Services Layer                            │   │
│  │  ┌───────────┐  ┌──────────┐  ┌────────────┐  ┌──────────┐    │   │
│  │  │FileImport │  │ImportedF.│  │DicomSeries │  │Drawing   │    │   │
│  │  │  Service  │  │  Store   │  │   Store    │  │ Export   │    │   │
│  │  └───────────┘  └──────────┘  └────────────┘  └──────────┘    │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                              │                                           │
│                              ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                       Resource Layer                            │   │
│  │  ┌─────────────────────────────────────────────────────────┐   │   │
│  │  │ Bundle.module                                            │   │   │
│  │  │  - Resources/dist/     (React app build)                │   │   │
│  │  │  - Resources/samples/  (Demo neuroimaging files)        │   │   │
│  │  └─────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                           │
└─────────────────────────────────────────────────────────────────────────┘
```

## Data Flow: Loading a Volume

```
┌──────────────┐
│ Consumer App │
│  SwiftUI     │
└──────┬───────┘
       │
       │ 1. manager.loadImageFromUrl(url: "niivue://app/samples/T1w_DEMO.nii.gz")
       ▼
┌────────────────────────┐
│  WebViewManager        │
│  @MainActor            │
└────────┬───────────────┘
         │
         │ 2. Escape URL + fileName using JavaScriptQuote
         ▼
┌────────────────────────┐
│  JavaScriptQuote       │
│  jsonStringLiteral()   │
└────────┬───────────────┘
         │
         │ 3. Build JS: window.loadImageFromUrl("niivue://app/...", "T1w_DEMO.nii.gz")
         ▼
┌────────────────────────┐
│  WKWebView             │
│  evaluateJavaScript()  │
└────────┬───────────────┘
         │
         │ 4. Execute in WebView context
         ▼
┌──────────────────────────────────┐
│  React App (JavaScript)          │
│  window.loadImageFromUrl()       │
└────────┬─────────────────────────┘
         │
         │ 5. Fetch: niivue://app/samples/T1w_DEMO.nii.gz
         ▼
┌────────────────────────────────────┐
│  WKWebView Network Stack           │
│  (intercepts niivue:// scheme)     │
└────────┬───────────────────────────┘
         │
         │ 6. webView(_:start:)
         ▼
┌────────────────────────────────────┐
│  NiivueURLSchemeHandler            │
│  WKURLSchemeHandler                │
└────────┬───────────────────────────┘
         │
         │ 7. Parse URL
         ▼
┌────────────────────────────────────┐
│  NiivueURLRouter                   │
│  route(url) → .sample(path)        │
└────────┬───────────────────────────┘
         │
         │ 8. Resolve path: Bundle.module/samples/T1w_DEMO.nii.gz
         ▼
┌────────────────────────────────────┐
│  Bundle.module                     │
│  resourceURL/samples/              │
└────────┬───────────────────────────┘
         │
         │ 9. Read file in 64KB chunks
         ▼
┌────────────────────────────────────┐
│  FileHandle (background queue)     │
│  Stream data to WKWebView          │
└────────┬───────────────────────────┘
         │
         │ 10. didReceive(Data) chunks
         ▼
┌────────────────────────────────────┐
│  WKWebView Network Stack           │
│  Assembles HTTP response           │
└────────┬───────────────────────────┘
         │
         │ 11. Blob/ArrayBuffer in JS
         ▼
┌──────────────────────────────────────┐
│  React App                           │
│  Niivue.js parses NIfTI format       │
│  WebGL renders to <canvas>           │
└────────┬─────────────────────────────┘
         │
         │ 12. window.webkit.messageHandlers.volumeLoaded.postMessage()
         ▼
┌────────────────────────────────────┐
│  WebViewManager                    │
│  handleScriptMessage()             │
│  @Published volumes updated        │
└────────┬───────────────────────────┘
         │
         │ 13. SwiftUI view updates
         ▼
┌──────────────┐
│ Consumer App │
│  UI shows    │
│  volume info │
└──────────────┘
```

## Custom URL Scheme Routing

```
niivue://app/...
       │
       └─── Handled by NiivueURLSchemeHandler
              │
              ├─── /index.html
              │    └─→ Bundle.module/Resources/dist/index.html
              │
              ├─── /assets/index-[hash].js
              │    └─→ Bundle.module/Resources/dist/assets/index-[hash].js
              │
              ├─── /assets/dcm2niix.jpeg-[hash].wasm
              │    └─→ Bundle.module/Resources/dist/assets/dcm2niix.jpeg-[hash].wasm
              │
              ├─── /samples/T1w_DEMO.nii.gz
              │    └─→ Bundle.module/Resources/samples/T1w_DEMO.nii.gz
              │
              ├─── /files/<uuid>
              │    └─→ Application Support/NiiVue/Library/<uuid>/
              │
              └─── /dicom/<seriesId>/niivue-manifest.txt
                   └─→ DicomSeriesStore (dynamic manifest)
```

## Service Dependencies

```
┌────────────────────────────────────────────────────────────┐
│                     WebViewManager                         │
│  (Main controller - depends on all services)               │
└───┬────────────────────────────────────────────────────┬───┘
    │                                                      │
    ▼                                                      ▼
┌───────────────────┐                           ┌──────────────────┐
│ URLSchemeHandler  │                           │ ImportedFileStore│
│  (internal)       │◄──────────────────────────┤  (public)        │
└─────┬─────────────┘                           └──────────────────┘
      │                                                    │
      │ uses                                               │ uses
      ▼                                                    ▼
┌───────────────────┐                           ┌──────────────────┐
│  URLRouter        │                           │ FileImportService│
│  (internal)       │                           │  (public)        │
└───────────────────┘                           └──────────────────┘
```

## Testing Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    NiivueKitTests                            │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │               Unit Tests (Core/)                      │  │
│  │  ┌─────────────────────────────────────────────┐     │  │
│  │  │  MockJavaScriptEvaluator                    │     │  │
│  │  │  (replaces WKWebView for tests)             │     │  │
│  │  └─────────────┬───────────────────────────────┘     │  │
│  │                │                                       │  │
│  │                ▼                                       │  │
│  │  ┌─────────────────────────────────────────────┐     │  │
│  │  │  WebViewManagerTests                        │     │  │
│  │  │  - No WKWebView dependency                  │     │  │
│  │  │  - Fast, deterministic                      │     │  │
│  │  └─────────────────────────────────────────────┘     │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │         Integration Tests (Commands/)                 │  │
│  │  ┌─────────────────────────────────────────────┐     │  │
│  │  │  Uses real WKWebView                        │     │  │
│  │  │  - Loads actual dist/ resources             │     │  │
│  │  │  - Tests end-to-end workflows               │     │  │
│  │  │  - Slower but realistic                     │     │  │
│  │  └─────────────────────────────────────────────┘     │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │          Test Fixtures (Resources/Fixtures/)          │  │
│  │  - ui-test-volume-1.nii (360 bytes)                  │  │
│  │  - ui-test-volume-2.nii (360 bytes)                  │  │
│  └───────────────────────────────────────────────────────┘  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Platform Support Matrix

```
┌─────────────────────────────────────────────────────────────┐
│                    Platform Support                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  iOS 16+                                                     │
│  ├─ WKWebView with WebGL 2.0                                │
│  ├─ Swift Concurrency (async/await)                         │
│  ├─ SwiftUI compatibility                                   │
│  └─ Primary target platform                                 │
│                                                               │
│  macOS 13+ (Catalyst)                                        │
│  ├─ iPad apps on Apple Silicon Macs                         │
│  ├─ Same WKWebView implementation                           │
│  ├─ No platform-specific code needed                        │
│  └─ #if targetEnvironment(macCatalyst) available            │
│                                                               │
│  visionOS 1+                                                 │
│  ├─- Future WebXR compatibility                             │
│  ├─ Spatial computing support                               │
│  ├─ Same Swift codebase                                     │
│  └─ #if os(visionOS) for platform features                  │
│                                                               │
│  NOT Supported:                                              │
│  ├─ watchOS (no WKWebView)                                  │
│  ├─ tvOS (limited WebGL, no use case)                       │
│  └─ macOS (non-Catalyst) - could be added later             │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## WebView Lifecycle

```
┌──────────────────┐
│  App Launch      │
└────────┬─────────┘
         │
         ▼
┌─────────────────────────────┐
│  WebViewManager.init()      │
│  - Create WKWebView         │
│  - Register URL handler     │
│  - Set up message handlers  │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  manager.load()             │
│  - Load niivue://app/       │
│  - Start timeout timer      │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  WKWebView loads HTML       │
│  - Fetches via URL handler  │
│  - Executes React bundle    │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  React app initializes      │
│  - Niivue.js loads          │
│  - WebGL context created    │
└────────┬────────────────────┘
         │
         │ window.webkit.messageHandlers.finishedLoading.postMessage()
         ▼
┌─────────────────────────────┐
│  WebViewManager ready       │
│  - isReady = true           │
│  - Cancel timeout           │
│  - UI shows WebView         │
└────────┬────────────────────┘
         │
         │ App continues...
         ▼
┌─────────────────────────────┐
│  Load volumes, interact     │
│  - Bidirectional Swift↔️JS  │
│  - Custom URL scheme        │
└─────────────────────────────┘
```

## Resource Loading Flow

```
Swift Package Manager Build
         │
         ▼
┌─────────────────────────────┐
│  Copy Resources             │
│  - dist/    → Bundle        │
│  - samples/ → Bundle        │
└────────┬────────────────────┘
         │
         ▼
┌─────────────────────────────┐
│  Framework Bundle           │
│  NiivueKit_NiivueKit.bundle │
│  ├─ dist/                   │
│  │  ├─ index.html           │
│  │  └─ assets/              │
│  │     ├─ *.js              │
│  │     ├─ *.wasm            │
│  │     └─ *.woff2           │
│  └─ samples/                │
│     └─ T1w_DEMO.nii.gz      │
└────────┬────────────────────┘
         │
         │ Runtime access via Bundle.module
         ▼
┌─────────────────────────────┐
│  NiivueURLSchemeHandler     │
│  - Reads from Bundle.module │
│  - Streams to WKWebView     │
└─────────────────────────────┘
```

## Security Boundaries

```
┌─────────────────────────────────────────────────────────────┐
│                      Security Layers                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  1. URL Routing Security                                     │
│     ┌──────────────────────────────────────────┐            │
│     │  NiivueURLRouter.route()                │            │
│     │  - Reject ".." (path traversal)         │            │
│     │  - Reject "." (current directory)       │            │
│     │  - Whitelist scheme (niivue://)         │            │
│     │  - Whitelist host (app)                 │            │
│     └──────────────────────────────────────────┘            │
│                                                               │
│  2. JavaScript String Escaping                               │
│     ┌──────────────────────────────────────────┐            │
│     │  JavaScriptQuote.jsonStringLiteral()    │            │
│     │  - Use JSONEncoder (safe escaping)      │            │
│     │  - Prevent JS injection                 │            │
│     │  - Handle Unicode, quotes, newlines     │            │
│     └──────────────────────────────────────────┘            │
│                                                               │
│  3. Content Security Policy (CSP)                            │
│     ┌──────────────────────────────────────────┐            │
│     │  index.html <meta> tag                  │            │
│     │  - default-src 'self' niivue:           │            │
│     │  - script-src 'self' 'unsafe-eval'      │            │
│     │  - style-src 'self' 'unsafe-inline'     │            │
│     └──────────────────────────────────────────┘            │
│                                                               │
│  4. Sandboxed File Access                                    │
│     ┌──────────────────────────────────────────┐            │
│     │  ImportedFileStore                      │            │
│     │  - UUID-based file IDs                  │            │
│     │  - Files in Application Support         │            │
│     │  - No direct path exposure              │            │
│     └──────────────────────────────────────────┘            │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Async/Await Concurrency Model

```
┌────────────────────────────────────────────────────────────┐
│                 Swift Concurrency Model                     │
├────────────────────────────────────────────────────────────┤
│                                                              │
│  WebViewManager: @MainActor                                │
│  ├─ All methods execute on main thread                     │
│  ├─ @Published properties update UI                        │
│  └─ Safe WKWebView access                                  │
│                                                              │
│  Async Methods:                                             │
│  ┌──────────────────────────────────────────────────┐     │
│  │  func loadImageFromUrl(...) async throws         │     │
│  │  - Suspends until JS completes                   │     │
│  │  - Returns to main actor                         │     │
│  │  - Propagates errors via throw                   │     │
│  └──────────────────────────────────────────────────┘     │
│                                                              │
│  Background File I/O:                                       │
│  ┌──────────────────────────────────────────────────┐     │
│  │  Task.detached(priority: .userInitiated)         │     │
│  │  - File reads on background queue                │     │
│  │  - Chunk streaming to WKWebView                  │     │
│  │  - Returns to MainActor for completion           │     │
│  └──────────────────────────────────────────────────┘     │
│                                                              │
└────────────────────────────────────────────────────────────┘
```

## Package Distribution

```
GitHub Repository: niivue/NiivueKit
         │
         ├─── main branch
         │    ├─ Sources/
         │    ├─ Tests/
         │    ├─ Package.swift
         │    └─ Documentation/
         │
         ├─── Git Tags
         │    ├─ v1.0.0 (initial release)
         │    ├─ v1.1.0 (visionOS support)
         │    └─ v2.0.0 (breaking changes)
         │
         └─── GitHub Actions CI
              ├─ Build on push/PR
              ├─ Run tests
              └─ Generate documentation
                       │
                       ▼
              ┌──────────────────────┐
              │  Consumer Apps       │
              │  Add via SPM:        │
              │  1. Xcode GUI        │
              │  2. Package.swift    │
              └──────────────────────┘
```

## Diagram Legend

```
┌────────────────────────────────────────┐
│  Symbol Key                            │
├────────────────────────────────────────┤
│  ┌─────┐   Component/Module            │
│  │     │                                │
│  └─────┘                                │
│                                         │
│  ───▶     Data/control flow            │
│                                         │
│  ◄────    Bidirectional flow           │
│                                         │
│  ├─        Parent-child relationship   │
│  └─                                     │
│                                         │
│  @MainActor  Swift concurrency marker  │
│                                         │
│  (internal)  Access control level      │
│  (public)                               │
└────────────────────────────────────────┘
```

## Summary

This architecture provides:

1. **Clear separation of concerns** - Core, Networking, Services, Models
2. **Type-safe JavaScript bridge** - Async/await with error handling
3. **Secure resource loading** - Custom URL scheme with validation
4. **Efficient file handling** - Streaming, chunked I/O
5. **Testable design** - Mock evaluator for unit tests
6. **Platform flexibility** - iOS, Catalyst, visionOS
7. **SPM best practices** - Single target, bundled resources

The architecture balances simplicity (single target) with modularity (organized directories), making it easy to use while maintaining clean code organization.
