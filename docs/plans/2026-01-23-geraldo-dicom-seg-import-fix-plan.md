# Geraldo CT DICOM + NIfTI Segmentation Import Fix — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task‑by‑task.

**Goal:** On iPhone 16 Pro Max, reliably load the Geraldo CT DICOM series (`VOLUME_VENOSO_MED_E_ABD_9`) and overlay `.nii.gz` segmentations from `Geraldo_FULL_Segmentations`, with deterministic on-device XCUITest coverage and clear, actionable user-facing errors.

**Architecture:** Keep the current iOS → `niivue://` scheme → React/Niivue pipeline, but add (1) a deterministic “fixture” harness for the Geraldo dataset, (2) segmentation directory recursion + safe loading limits (to avoid trying to load dozens of 512×512×484 masks at once), and (3) scripts to copy fixtures into the app container via `devicectl` for repeatable on-device validation.

**Tech Stack:** SwiftUI + UIKit (`UIDocumentPickerViewController`) + `WKWebView` custom scheme handler + React/TypeScript + `@niivue/niivue`.

---

## Task 1: Add deterministic fixture harness (DICOM + segmentation)

**Files:**
- Modify: `NiiVue/NiiVue/ContentView.swift`
- Modify: `NiiVue/NiiVueUITests/NiiVueUITests.swift`

**Step 1: Write a failing on-device UI test (RED)**

Add `testDicomImportGeraldoSeriesLoadsVolume()`:
- Launch args:
  - `--ui-test-dicom-dir dicom-fixtures/GERALDO_TRINDADE_FIRMINO/VOLUME_VENOSO_MED_E_ABD_9`
- Assert:
  - `niivue.isReady` becomes `ready`
  - `niivue.dicomImportStatusGlobal` contains `Loaded`
  - `niivue.volumeCount` becomes `> 0`

Run:
```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'platform=iOS,id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests/NiiVueUITests/testDicomImportGeraldoSeriesLoadsVolume \
  -derivedDataPath /tmp/NiiVueDerivedData-Geraldo-DICOM \
  -allowProvisioningUpdates \
  -collect-test-diagnostics never
```
Expected: FAIL until the fixture exists on-device and errors are actionable.

**Step 2: Add a segmentation fixture launch argument**

In `ContentView.handleWebViewReadyChanged(isReady:)`:
- Add optional args:
  - `--ui-test-seg-dir <relativePathInDocuments>`
  - `--ui-test-seg-limit <N>` (default 1)
- After the base load completes, scan `Documents/<segDir>` for `.nii`/`.nii.gz`, then call `webViewManager.addVolumesFromUrls(...)` for the first `N`.

**Step 3: Add a combined DICOM + segmentation UI test**

Add `testDicomImportGeraldoThenLoadsOneSegmentationOverlay()`:
- Launch args:
  - `--ui-test-dicom-dir …/VOLUME_VENOSO_MED_E_ABD_9`
  - `--ui-test-seg-dir segmentation-fixtures/Geraldo_FULL_Segmentations`
  - `--ui-test-seg-limit 1`
- Assert:
  - Volume count reaches at least `2`
  - `niivue.lastError` stays empty / does not contain `Failed`

---

## Task 2: Harden segmentation import (folder recursion + safe load limits)

**Files:**
- Modify: `NiiVue/NiiVue/ContentView.swift`

**Step 1: Write a unit test for recursive collection (RED)**

Add new test file `NiiVue/NiiVueTests/Segmentation/SegmentationAssetCollectionTests.swift` that verifies:
- Given a temp directory containing nested `.nii.gz`, `collectSegmentationAssets(from:)` returns all files and filters out unsupported.

Run:
```bash
xcodebuild test -project NiiVue/NiiVue.xcodeproj -scheme NiiVue -only-testing:NiiVueTests/SegmentationAssetCollectionTests
```

**Step 2: Implement recursive collection**

In `ContentView`:
- Add `collectSegmentationAssetFiles(from:)` similar to `collectDicomFiles(from:)`.
- Update `importSegmentationAssets(from:)` to expand folders before importing.

**Step 3: Avoid loading “too many” huge masks at once**

In `SegmentationAssetImportPlanner.plan(...)`:
- Add a cap for automatic volume loading (default 1; configurable later).
- Put skipped filenames into the status message (imported but not loaded).

---

## Task 3: Add scripts to copy fixtures to device container

**Files:**
- Create: `scripts/copy-geraldo-fixtures-to-device.sh`
- (Optional) Create: `scripts/copy-fixtures-to-device.sh` (generic helper)

**Step 1: Script to copy both directories**

Use `devicectl` to copy:
- DICOM series:
  - Source: `/Users/leandroalmeida/niivue-ios-foundation/Test_CT_DICOM_volumes/GERALDO_TRINDADE_FIRMINO/VOLUME_VENOSO_MED_E_ABD_9`
  - Destination: `Documents/dicom-fixtures/GERALDO_TRINDADE_FIRMINO/VOLUME_VENOSO_MED_E_ABD_9`
- Segmentations:
  - Source: `/Users/leandroalmeida/niivue-ios-foundation/Test_CT_DICOM_volumes/Geraldo_FULL_Segmentations`
  - Destination: `Documents/segmentation-fixtures/Geraldo_FULL_Segmentations`

---

## Task 4: Verification (device + local)

**Step 1: Copy fixtures**

Run:
```bash
scripts/copy-geraldo-fixtures-to-device.sh 00008140-001664420413C01C
```

**Step 2: Run UI tests on-device**

Run:
```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'platform=iOS,id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests \
  -derivedDataPath /tmp/NiiVueDerivedData-NiiVueUITests-Device-Geraldo \
  -allowProvisioningUpdates \
  -collect-test-diagnostics never
```

Expected:
- DICOM Geraldo tests pass
- Seg overlay test passes with `--ui-test-seg-limit 1`

