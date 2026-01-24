# Native Preprocessing (Explicit Swift Trigger) — Hybrid Segmentation

**Goal:** For cache misses, run native preprocessing *before* instructing Niivue (React/WKWebView) to load a preprocessed volume URL. This guarantees `PreprocessedVolumeCache` is populated before any `niivue://app/preprocessed/...` request is made.

## Why Explicit Swift (Not `WKURLSchemeHandler` On-Demand)

`WKURLSchemeHandler` is request-driven and called on the main actor. Apple’s docs describe it as a resource loading mechanism: WebKit creates a `WKURLSchemeTask`, the handler delivers bytes via `didReceive(_:)`, then calls `didFinish()` (or `didFailWithError(_:)`).

- `WKURLSchemeHandler`: `apple-docs://webkit/documentation_webkit_wkurlschemehandler`
- `WKURLSchemeTask`: `apple-docs://webkit/documentation_webkit_wkurlschemetask`

Running multi-second preprocessing inside `webView(_:start:)` would:
- Block resource requests on `@MainActor` unless everything is immediately offloaded.
- Make progress reporting/cancellation/error handling awkward (you’re inside a scheme task).
- Create brittle behavior when Niivue retries/aborts loads (WebKit may call `stop` at any time).

Instead, keep the scheme handler “dumb and fast”: serve bytes from disk only. All expensive work happens explicitly in Swift, where we can surface progress, dedupe requests, and handle cancellation.

## End-to-End Data Flow

1. **User imports a DICOM series**
   - We collect local sandbox URLs for the selected DICOM files.
2. **Swift triggers preprocessing**
   - `PreprocessingService.preprocessDicomSeries(...)`:
     - Checks `PreprocessedVolumeCache` for `studyID/itemID/parametersHash`.
     - If cache miss: loads DICOM, runs normalization + resampling, writes `preprocessed.nii`, and stores it in the cache directory **without an extra copy**.
3. **Swift instructs Niivue to load the preprocessed URL**
   - `WebViewManager` calls `window.loadImageFromUrl("niivue://app/preprocessed/<study>/<item>/<hash>/preprocessed.nii", "preprocessed.nii")`.
4. **WebView requests bytes**
   - `NiivueURLSchemeHandler` receives the `niivue://app/preprocessed/...` request and serves the cached file from disk.

## Key Contracts

- Preprocessed URL format:
  - `niivue://app/preprocessed/<studyID>/<itemID>/<parametersHash>/preprocessed.nii(.gz)`
- Scheme handler allowlist:
  - Only `preprocessed.nii` and `preprocessed.nii.gz` are served.
- Cache population:
  - Preprocessing must complete and cache must contain the file before calling `loadImageFromUrl(...)`.

## Testing Strategy (Unit + Integration)

The suite focuses on the explicit-Swift contract:
- `PreprocessedVolumeCache.storeGenerated(...)` stores outputs without a double copy.
- `NiftiWriter` writes correct `dim`, `pixdim`, and `sform` (including LPS→RAS conversion).
- `PreprocessingService`:
  - cache-hit returns immediately (no processing),
  - cache-miss produces and caches `preprocessed.nii`.
- `WebViewManager` builds the correct `niivue://app/preprocessed/...` URL and updates `volumeSources`.

## How to Run (once tests are added)

- iOS unit tests (device or simulator):
  - `xcodebuild test -project NiiVue/NiiVue.xcodeproj -scheme NiiVue -destination "platform=iOS Simulator,name=iPhone 17" -only-testing:NiiVueTests`
- Device-specific runs should continue to use:
  - `-collect-test-diagnostics never`

