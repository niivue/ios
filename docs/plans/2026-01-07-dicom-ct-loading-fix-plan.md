# CT DICOM Loading (KiTS23) — Debug + Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task‑by‑task.

**Goal:** Make importing and viewing real-world CT DICOM series reliable (including compressed transfer syntaxes), with actionable error reporting and automated regression validation using the KiTS23 sample series.

**Architecture:** Keep the current iOS → `niivue://` custom scheme → React/NiiVue manifest pipeline, but (1) add a deterministic reproduction harness, (2) correctly await and surface DICOM conversion errors across the Swift↔JS boundary, and (3) add preflight/series validation + better UX (folder import, mixed-series detection, progress, caching). Add a fallback plan (native dcm2niix) if WKWebView/WASM proves unreliable on-device.

**Tech Stack:** SwiftUI + UIKit (`UIDocumentPickerViewController`) + Foundation (file access, security-scoped resources) + `WKWebView` custom scheme handler + React/TypeScript + `@niivue/niivue` + `@niivue/dicom-loader` (dcm2niix WASM + worker).

---

## 0) Current State Deep Dive (What Exists Today)

### iOS layer (Swift)

- DICOM import entry point:
  - `NiiVue/NiiVue/ContentView.swift` → `importDicomSeries(from:)`
  - Filters `.dcm`/`.dicom`/no-extension, then imports each file via `FileImportService.importDocument(at:destinationDirectory:)` into `Application Support/NiiVue/Library/<uuid>/<filename>`.
  - Registers the imported URLs in `DicomSeriesStore` and exposes it via `webViewManager.urlSchemeHandler.dicomSeriesStore`.
  - Loads the series via manifest:
    - `manifestURL = niivue://app/dicom/<seriesId>/niivue-manifest.txt`
    - Calls `WebViewManager.loadDicomSeriesFromManifestURL(_:)`.

- Custom scheme:
  - `NiiVue/NiiVue/Web/NiivueURLRouter.swift` routes:
    - `dicom/<seriesId>/niivue-manifest.txt`
    - `dicom/<seriesId>/<fileName>`
  - `NiiVue/NiiVue/Web/NiivueURLSchemeHandler.swift` serves:
    - Manifest via `DicomSeriesStore.manifestText(for:)` (one filename per line, **no trailing newline**)
    - Each DICOM file via streaming `FileHandle` reads.

### React/NiiVue layer (TypeScript)

- DICOM loader setup:
  - `NiiVue/React/src/App.tsx`:
    - `nv.useDicomLoader({ loader: (data) => dicomLoader(data), toExt: 'nii' })`
    - `window.loadDicomSeriesFromManifest(manifestUrl)` calls `nv.loadDicoms([{ url: manifestUrl, isManifest: true }])`
  - `NiiVue/React/src/bridge/dicomBridge.ts` is a thin wrapper around `nv.loadDicoms`.

- Niivue core behavior (from `/Users/leandroalmeida/niivue`):
  - `packages/niivue/src/niivue/index.ts`:
    - `loadDicoms(...)` fetches manifest → fetches each DICOM file into ArrayBuffers → calls registered dicomLoader → loads resulting NIfTI into NVImage.
  - `packages/niivue/src/nvimage/ImageFactory.ts`:
    - `fetchDicomData(manifestUrl)` splits by `\n` and does **not** filter empty lines → **manifest must not have trailing newline**.

---

## 1) Evidence: KiTS23 Sample CT Series Characteristics

**User-provided validation dataset:**
- `/Users/leandroalmeida/Downloads/kits23-v1/src/kits23/workspace-kits23/TC_DA_PELVE/VOLUME_MED_E_ABD_3`
- ~212 files named `IM-0001-####.dcm`

**Critical finding (Transfer Syntax):**

The series is **compressed**:
- `TransferSyntaxUID = 1.2.840.10008.1.2.4.70` (JPEG Lossless, Non-Hierarchical, Process 14)

This matters because many “DICOM loaders” fail on compressed transfer syntaxes unless a JPEG-capable decoder is present (in our case: dcm2niix WASM must successfully decode this transfer syntax).

---

## 2) Primary Hypotheses (Root Cause Candidates)

We should **not** fix by guessing — gather evidence first.

1) **WASM/Worker fails inside WKWebView custom scheme context**
   - Symptoms: worker fails to load, wasm fails to compile/instantiate, silent promise rejection.
2) **dcm2niix WASM fails decoding JPEG Lossless (Process 14)**
   - Symptoms: dcm2niix returns non-zero exit code, or throws with decoder errors.
3) **Swift↔JS DICOM load doesn’t truly await the async work**
   - Current Swift call path uses `evaluateCommand("window.loadDicomSeriesFromManifest(...)")` which does not `await` the returned Promise.
   - Symptoms: “success” UI while conversion still running; failures become console-only and never surface to Swift.
4) **Input selection issues**
   - Mixed series, inclusion of non-image objects, missing slices, duplicate filenames, etc.

We will design the plan so it **forces evidence**:
- deterministic reproduction,
- captures the actual error string coming from the JS side,
- and adds a regression test.

---

## 3) Approaches (Choose a Path)

### Approach A (Recommended): Strengthen the existing Niivue manifest pipeline

**Pros**
- Minimal architecture change.
- Reuses Niivue’s intended DICOM path (`loadDicoms` + dcm2niix).
- Keeps DICOM logic in the web layer (closest to Niivue source of truth).

**Cons**
- Still dependent on WKWebView + WASM + Worker constraints.

### Approach B: Native dcm2niix conversion fallback (if A isn’t robust enough)

Ship a native (Swift/C/C++) dcm2niix conversion pipeline for iOS:
- Convert DICOM → NIfTI in Swift (background thread), write `.nii.gz` to Caches/App Support.
- Load NIfTI into Niivue via existing `loadVolumesFromUrls(...)`.

**Pros**
- Eliminates WKWebView worker/wasm fragility.
- Better memory and performance control; easier progress + cancellation.

**Cons**
- Bigger binary, more build complexity, C/C++ integration effort.

### Approach C: Full native DICOM rendering (not recommended)

Decode DICOM pixel data directly in Swift and render in Metal/SwiftUI.

**Pros**
- Complete control.

**Cons**
- Huge scope; duplicates Niivue’s role; not aligned with this project.

**Recommendation:** Start with **Approach A** + add the hooks to later enable **Approach B** if needed.

---

## 4) Plan (Bite-sized TDD Tasks)

### Task 1: Create a deterministic on-device reproduction harness (no DocumentPicker)

**Purpose:** Reproduce the issue without manual picker interaction and capture the exact error.

**Files:**
- Modify: `NiiVue/NiiVue/ContentView.swift`
- Modify: `NiiVue/NiiVueUITests/NiiVueUITests.swift`
- (Optional) Add: `scripts/dicom-fixture-to-device.sh`

**Step 1: Add a UI-test-only launch argument**

In `ContentView`, detect something like:
- `--ui-test-dicom-dir <relativePathInDocuments>`

And run:
- enumerate `.dcm` files from `Documents/<relativePath>`
- register them in `dicomSeriesStore`
- call `webViewManager.loadDicomSeriesFromManifestURL(...)`
- expose status via a debug label (e.g. `niivue.dicomImportStatusGlobal`).

**Step 2: Write the failing XCUI test**

Add a new test:
- `testDicomImportKiTS23SeriesLoadsVolume()`

Expectations:
- status label becomes “Loaded … DICOM file(s).” **or** a failure label contains the JS error string.
- volume count increases (or `volumeLoaded` callback fires).

**Step 3: Device fixture copy command**

Use `devicectl` to copy the sample series folder into the app container:

```bash
xcrun devicectl device copy to \
  --device 00008140-001664420413C01C \
  --source /Users/leandroalmeida/Downloads/kits23-v1/src/kits23/workspace-kits23/TC_DA_PELVE/VOLUME_MED_E_ABD_3 \
  --domain-type appDataContainer \
  --domain-identifier com.niivue.mobile \
  --destination Documents/dicom-fixtures/VOLUME_MED_E_ABD_3 \
  --remove-existing-content true
```

Then run:

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests/NiiVueUITests/testDicomImportKiTS23SeriesLoadsVolume
```

**Expected (RED initially):** test fails and prints the captured error message (root cause evidence).

---

### Task 2: Make Swift↔JS DICOM load truly awaitable (surface Promise rejection)

**Files:**
- Modify: `NiiVue/NiiVue/Web/WebViewManager.swift`
- Test: `NiiVue/NiiVueTests/DicomCommandTests.swift`

**Step 1: Write failing unit test**

Update the existing test to expect the new JS string:
- `return await window.loadDicomSeriesFromManifest(...)`

**Step 2: Run test to verify it fails**

Run:
```bash
xcodebuild test -project NiiVue/NiiVue.xcodeproj -scheme NiiVue -only-testing:NiiVueTests/DicomCommandTests
```

**Expected:** FAIL because code still uses `evaluateCommand(...)`.

**Step 3: Implement minimal fix**

Change:
```swift
try await evaluator.evaluateCommand("window.loadDicomSeriesFromManifest(\(urlEscaped))")
```
to:
```swift
_ = try await evaluator.callAsyncString("return await window.loadDicomSeriesFromManifest(\(urlEscaped))")
```

**Step 4: Re-run tests**
Expected: PASS.

**Outcome:** Any JS-side rejection becomes a Swift `throw`, enabling user-facing error messages and reliable automation.

---

### Task 3: Add first-class JS → Swift error propagation for DICOM

**Files:**
- Modify: `NiiVue/React/src/App.tsx`
- Modify: `NiiVue/React/src/bridge/iosMessaging.ts`
- Modify: `NiiVue/NiiVue/Web/WebViewManager.swift`

**Step 1: Register a `logMessage` handler in Swift**

Per Apple docs, the web-to-native bridge relies on `WKScriptMessageHandler` names.
Add:
- `config.userContentController.add(scriptMessageHandler, name: "logMessage")`

Then handle it in `handleScriptMessage(...)`:
- on `level == "error"`, set `lastErrorMessage` (and optionally a dedicated `dicomLastErrorMessage`)

**Step 2: Wrap `loadDicomSeriesFromManifest` in try/catch (JS)**

In `App.tsx`:
- catch and `postToIOS('logMessage', { level: 'error', message: '...', ... })`
- rethrow so Swift gets the failure too (now that it `await`s).

**Step 3: Verify via Task 1 XCUI harness**

Expected: error visible in Swift UI label + captured in test logs.

---

### Task 4: DICOM preflight validation (transfer syntax + basic sanity checks)

**Files:**
- Create: `NiiVue/NiiVue/Services/DicomMetaHeaderReader.swift`
- Modify: `NiiVue/NiiVue/ContentView.swift`
- Test: `NiiVue/NiiVueTests/DicomMetaHeaderReaderTests.swift`

**Step 1: Write failing unit test**

Test that `DicomMetaHeaderReader` can extract TransferSyntaxUID from the KiTS23 sample file (copy a single file into test tmp dir):
- expects `1.2.840.10008.1.2.4.70`

**Step 2: Implement minimal meta-header parser**

Parse:
- 128-byte preamble + `DICM`
- explicit VR little-endian group `0002`, find tag `(0002,0010)` TransferSyntaxUID

**Step 3: Use it during import**

Before calling Niivue:
- sample 1–3 files, show transfer syntax in status
- if unknown/unsupported, show actionable message (and offer fallback strategy)

---

### Task 5: “Folder import” UX (make DICOM import usable)

**Files:**
- Modify: `NiiVue/NiiVue/ContentView.swift`
- Modify: `NiiVue/NiiVue/Services/FileImportService.swift`

**Apple-doc grounding (Cupertino):**
- `UIDocumentPickerViewController` (open vs export; external docs can be security-scoped): `apple-docs://uikit/documentation_uikit_uidocumentpickerviewcontroller`
- `URL.startAccessingSecurityScopedResource()` (must balance stop calls): `apple-docs://foundation/documentation_foundation_nsurl_startaccessingsecurityscopedresource_e06b2803`
- File coordination overview (when operating on external directories): `apple-docs://foundation/documentation_foundation_file-system`

**Implementation outline:**
- Add “Import DICOM Folder” button.
- Use `UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])`.
- For the returned directory URL:
  - call `startAccessingSecurityScopedResource()`
  - enumerate files (`FileManager.enumerator`) and copy `.dcm` files into app sandbox
  - stop accessing as soon as copy completes

---

### Task 6: Robustness upgrades (series selection, caching, performance)

**Series selection (mixed series detection):**
- Parse minimal tags required for grouping:
  - SeriesInstanceUID (0020,000E)
  - Modality (0008,0060)
  - SeriesDescription (0008,103E)
  - InstanceNumber (0020,0013)
- If multiple series detected, present a series picker before conversion.

**Caching converted NIfTI:**
- Hash series inputs (filenames + file sizes + maybe SOPInstanceUIDs)
- Store `.nii.gz` in `Caches/` keyed by hash
- On subsequent loads, skip DICOM conversion and load NIfTI directly.

**Performance:**
- Add progress UI (files copied / total).
- Consider parallel fetch in JS if Niivue’s sequential `fetchDicomData` becomes a bottleneck (only if proven by profiling).

---

## 5) Success Criteria

- KiTS23 sample series loads without errors and renders interactively on iPhone 16 Pro Max.
- Failures surface as actionable messages (transfer syntax, missing slices, worker/wasm load errors).
- Automated regression exists:
  - `devicectl copy to` fixture → `xcodebuild test` passes
- Folder-based import works (no manual 200+ file selection).

---

## 6) Open Questions (One Decision Needed Before Implementation)

Do we want to **always** use the dcm2niix “jpeg” build (larger WASM but more compatible), or only fall back to it when a compressed transfer syntax is detected?

I recommend **always using the most compatible build** unless app size or startup time becomes a proven problem.

