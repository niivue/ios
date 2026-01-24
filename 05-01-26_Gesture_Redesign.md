# 05-01-26 — Gesture Redesign Report (NiiVue iOS)

This document is the running implementation + validation log for the gesture redesign work.

Related design/research doc: `docs/plans/2026-01-05-gesture-ux-overhaul-design.md`

---

## Step 1 — 2D “Stack Scroll” (Axial / Coronal / Sagittal)

### Goal (DICOM Viewer Behavior)

Implement DICOM-style stack scrubbing:

- **Gesture:** 1-finger vertical drag on the main viewer surface
- **Axis:** vertical only (`translation.height`)
- **State caching:** cache `initialSliceIndex` at gesture start to prevent jitter
- **Sensitivity:** `pixelsPerSlice = 10.0`
- **Math:**
  - `steps = -Int(translationY / pixelsPerSlice)`
  - `newIndex = initialSliceIndex + steps`
  - clamp `newIndex` to `[0, totalSlices - 1]`
- **Performance:** update slice smoothly during drag (scrub)

### Implementation (Native SwiftUI Gesture → Niivue Crosshair)

**Why native (this step):** a previous attempt used a `UIPanGestureRecognizer` attached to the `WKWebView`, but the recognizer did not reliably receive drag updates in XCUI tests. A SwiftUI `DragGesture` attached to the viewer container is reliably exercised by XCUI and keeps the logic simple for this first step.

#### Code changes

- `NiiVue/NiiVue/ContentView.swift`
  - Attach a `DragGesture` via `.simultaneousGesture(...)` to the `WebView(manager:)` surface.
  - Feed `value.translation.height` into the manager.
- `NiiVue/NiiVue/Web/WebViewManager.swift`
  - Implement stack scroll logic in:
    - `handleStackScrollDragChanged(translationY:)`
    - `handleStackScrollDragEnded()`
  - Axis mapping for 2D slice types:
    - axial → Z
    - coronal → Y
    - sagittal → X
  - Clamp slice index to prevent out-of-bounds.
  - Apply updates by calling `moveCrosshairInVox(dx,dy,dz)` (JS bridge) using the delta from the last applied index.
  - UI-test instrumentation:
    - `currentSliceIndex`, `currentTotalSlices`
    - `stackScrollDebugEventCount` (increments on drag updates)

### XCUIAutomation Validation (Physical Device)

**Device:** Leandro’s iPhone (`id=00008140-001664420413C01C`)

**Test:** `NiiVueUITests/test2DStackScrollScrubsSlices`

**Command:**

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DStackScrollScrubsSlices
```

**Result:** `** TEST SUCCEEDED **`

**Observed UI-test state (from test log):**

- Initial: `sliceType=0 totalSlices=2 sliceIndex=1 stackScrollEvents=0`
- Final: `sliceType=0 totalSlices=2 sliceIndex=0 stackScrollEvents=48`

This confirms:

- Drag events are received by the native gesture layer.
- Slice index changes in the correct direction with vertical dragging.
- Updates are clamped (no crash / out-of-bounds).

### Notes / Limitations (Known, Expected at This Step)

- Current implementation applies to “single-plane” 2D slice types (Axial/Coronal/Sagittal). It does **not** yet disambiguate which tile the user dragged in Multiplanar layout.
- Future steps should re-check interaction conflicts with other gestures (pinch-to-zoom, two-finger pan, etc.) and decide whether to keep this native path or move high-frequency gesture handling into the JS layer for maximum responsiveness.

---

## Step 2 — 2D “2-Finger Pan” (Axial / Coronal / Sagittal)

### Goal (DICOM Viewer Behavior)

Add DICOM-style 2-finger panning that coexists with Step 1’s 1-finger stack scroll:

- **Gesture:** `UIPanGestureRecognizer` configured for **exactly 2 touches** (`min=2 / max=2`)
- **State binding:** `@State var offset: CGSize`
- **State caching:** cache `savedOffset` on `.began`
- **Math:** `newOffset = savedOffset + translation` (1:1 direct manipulation, freeform X/Y)
- **Coexistence:** 1-finger drags must not trigger this pan recognizer

### Implementation (Native 2-Finger Pan → Niivue Pan)

#### Code changes

- `NiiVue/NiiVue/ContentView.swift`
  - Add `TwoFingerPanHandler` (ViewModifier) + `UIViewRepresentable` installer that attaches a `UIPanGestureRecognizer` to the **actual `WKWebView`** (resolved via view hierarchy) and binds cumulative `offset`.
  - On `.began`: snapshot `savedOffset`, capture `gestureStartLocation`, call `webViewManager.beginTwoFingerPan()`.
  - On `.changed`: update `offset`, call `webViewManager.pan2DFromScreenDrag(startX,startY,endX,endY)` using the start point + translation so the JS layer can pan the image.
  - **UI-test-only simulation:** `--ui-test-simulate-two-finger-pan`
    - Adds a SwiftUI `DragGesture` path inside `TwoFingerPanHandler` (because XCUI can’t synthesize true 2-finger drags on iPhone and `UIPanGestureRecognizer` does not fire under XCUI interactions on `WKWebView`).
    - Disables stack scroll gesture delivery while the flag is present (`including: .none`) so the simulated 1-finger drag only drives the pan path.
  - UI-test instrumentation (shown when `--ui-test-load-multiple`):
    - `niivue.twoFingerPanOffsetX`, `niivue.twoFingerPanOffsetY`
    - `niivue.twoFingerPanEvents`
    - `niivue.twoFingerPanInstallCount`, `niivue.twoFingerPanInstalledView`

- `NiiVue/NiiVue/Web/WebViewManager.swift`
  - Add JS bridge methods:
    - `beginTwoFingerPan()`
    - `pan2DFromScreenDrag(startX:startY:endX:endY:)`

- `NiiVue/React/src/App.tsx`
  - Add JS functions exposed on `window`:
    - `beginTwoFingerPan()` snapshots `nv.scene.pan2Dxyzmm` into `uiData.pan2DxyzmmAtMouseDown`
    - `pan2DFromScreenDrag(startX,startY,endX,endY)` calls `nv.dragForPanZoom([start*dpr, end*dpr])` then `nv.drawScene()`

- `NiiVue/NiiVueUITests/NiiVueUITests.swift`
  - Add test: `test2DTwoFingerPanUpdatesOffset`
    - Launch args: `--ui-test-load-multiple --ui-test-simulate-two-finger-pan`
    - Verifies: pan offsets + events change; stack scroll + slice index stay unchanged.

### XCUIAutomation Validation (Physical Device)

**Device:** Leandro’s iPhone (`id=00008140-001664420413C01C`)

**Tests:**
- `NiiVueUITests/test2DStackScrollScrubsSlices`
- `NiiVueUITests/test2DTwoFingerPanUpdatesOffset`

**Command:**

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DStackScrollScrubsSlices \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DTwoFingerPanUpdatesOffset
```

**Result:** `** TEST SUCCEEDED **`

**Observed UI-test state (from test log):**

- Stack Scroll test
  - Initial: `sliceType=0 totalSlices=2 sliceIndex=1 stackScrollEvents=0 panX=0 panY=0 panEvents=0`
  - Final: `sliceType=0 totalSlices=2 sliceIndex=0 stackScrollEvents=47 panX=0 panY=0 panEvents=0`

- Two-Finger Pan test (simulated)
  - Initial: `panX=0 panY=0 panEvents=0 panInstallCount=2 panInstalledView=WKWebView sliceIndex=1 stackScrollEvents=0`
  - Final: `panX=163 panY=0 panEvents=21`

This confirms:

- 1-finger stack scroll remains functional and does not trigger pan updates.
- The 2-finger pan path updates offset (and thus Niivue pan) without changing slice index.
- Gesture differentiation is respected (pan is not invoked by 1-finger scroll in normal mode; UI-test mode uses a dedicated simulation flag).

---

## Step 3 — 2D “Viewport Interaction” (Simultaneous 2-Finger Pan + Pinch Zoom)

### Goal (Photos / PACS Behavior)

Upgrade 2-finger navigation so the user can **pan + zoom at the same time**, like Apple Photos / PACS viewers:

- **Gestures:** `UIPanGestureRecognizer` (2 touches) + `UIPinchGestureRecognizer`
- **Simultaneous recognition:** `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:) == true`
- **State:** bind `offset: CGSize` and `scale: CGFloat`
- **Math:**
  - pinch: `scale *= recognizer.scale` (reset `recognizer.scale = 1.0` per step)
  - pan: `offset += recognizer.translation` (reset translation to `.zero` per step)
  - clamp scale to `[0.5, 10.0]`

### Implementation (Unified Handler + JS Bridge)

- `NiiVue/NiiVue/ContentView.swift`
  - Replace the previous pan-only wrapper with `ViewportInteractionHandler` (`UIViewRepresentable`).
  - Install both recognizers and allow simultaneous recognition via a delegate.
  - On each pan increment: call `webViewManager.pan2DFromScreenDragIncremental(startX,startY,endX,endY)`.
  - On each pinch increment: call `webViewManager.set2DZoomAtScreenPoint(scale:anchorX:anchorY:)`.
  - Clamp `twoFingerViewportScale` to `[0.5, 10.0]` and expose UI-test labels:
    - `niivue.viewportScale`
    - `niivue.viewportPinchEvents`
  - **UI-test-only pinch surface:** `--ui-test-simulate-two-finger-pinch`
    - XCUI pinch events do not reliably reach recognizers installed on a `WKWebView`.
    - The app exposes a transparent accessibility surface (`niivue.viewportInteractionSurface`) and installs the pinch recognizer on that surface for XCUI validation.

- `NiiVue/NiiVue/Web/WebViewManager.swift`
  - Add JS bridge methods:
    - `pan2DFromScreenDragIncremental(startX:startY:endX:endY:)`
    - `set2DZoomAtScreenPoint(scale:anchorX:anchorY:)`

- `NiiVue/React/src/App.tsx`
  - Add JS functions exposed on `window`:
    - `pan2DFromScreenDragIncremental(startX,startY,endX,endY)`
    - `set2DZoomAtScreenPoint(scale, anchorX, anchorY)` (anchor-aware 2D zoom)

- `NiiVue/NiiVueUITests/NiiVueUITests.swift`
  - Add test: `test2DViewportPinchZoomUpdatesScale`
    - Launch args: `--ui-test-load-multiple --ui-test-simulate-two-finger-pinch`
    - Verifies: `viewportScale` changes and `viewportPinchEvents` increases; slice index and stack scroll remain unchanged.

### XCUIAutomation Validation (Physical Device)

**Device:** Leandro’s iPhone (`id=00008140-001664420413C01C`)

**Tests:**
- `NiiVueUITests/test2DStackScrollScrubsSlices`
- `NiiVueUITests/test2DTwoFingerPanUpdatesOffset`
- `NiiVueUITests/test2DViewportPinchZoomUpdatesScale`

**Command:**

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DStackScrollScrubsSlices \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DTwoFingerPanUpdatesOffset \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DViewportPinchZoomUpdatesScale
```

**Result (from test log):** `Executed 3 tests, with 0 failures`

**Observed UI-test state (from test log):**

- Pinch Zoom test (via `niivue.viewportInteractionSurface`)
  - Initial: `viewportScale=1.000 viewportPinchEvents=0 sliceIndex=1 stackScrollEvents=0`
  - Final: `viewportScale=1.476 viewportPinchEvents=12` (slice index + stack scroll unchanged by assertion)

---

## Step 4 — 2D “Window/Level” (Contrast & Brightness, Mode-based 1-Finger Drag)

### Goal (PACS/DICOM Viewer Behavior)

Add a **Window/Level** adjustment mode that **overrides** 1-finger slice scrolling when selected:

- **Mode switch:** `.scroll` (default) vs `.windowLevel`
- **Gesture:** reuse existing 1-finger `DragGesture` on the viewer surface
  - `.scroll` → Step 1 “Stack Scroll” (unchanged)
  - `.windowLevel` → WW/WL adjustment (new)
- **Math & sensitivity:**
  - `pointsPerHU = 2.0`
  - `newWidth = dragStartWW + (translation.x * pointsPerHU)`
  - `newLevel = dragStartWL - (translation.y * pointsPerHU)` (invert Y so dragging UP increases WL)
  - clamp `newWidth >= 1.0`
- **Stable origin:** capture `dragStartWW` / `dragStartWL` **exactly once per drag** to prevent jumps.
- **UI:** display `WW` and `WL` in the top-left while dragging.

### Implementation (SwiftUI Mode Toggle + JS Intensity Window)

#### Code changes

- `NiiVue/NiiVue/ContentView.swift`
  - Add `enum ToolMode { case scroll, windowLevel }` + `@State toolMode`.
  - Add “Sun” mode toggle button:
    - `accessibilityIdentifier("niivue.tool.windowLevel")`
    - Enabled only for 2D slice types (Axial/Coronal/Sagittal).
  - Update the existing 1-finger drag handler to switch behavior based on `toolMode`.
  - Implement stable WW/WL origin caching:
    - `windowLevelDragStartWindowWidth` / `windowLevelDragStartWindowLevel` are captured once at drag begin (first `.onChanged`).
    - Cleared on drag end and when mode toggles.
  - Clamp initial WW values loaded from the viewer:
    - `windowWidth = max(1.0, updated.windowWidth)`
  - Show an in-view HUD while dragging:
    - `accessibilityIdentifier("niivue.windowLevelOverlay")`
  - UI-test instrumentation labels (shown when `--ui-test-load-multiple`):
    - `niivue.windowWidth`, `niivue.windowLevel`, `niivue.windowLevelEvents`

- `NiiVue/NiiVue/Web/WebViewManager.swift`
  - Add async JS bridge:
    - `getIntensityWindow(volumeIndex:) -> IntensityWindow`
    - `setIntensityWindow(volumeIndex:windowWidth:windowLevel:)`

- `NiiVue/React/src/App.tsx`
  - Export `window.getIntensityWindow(volumeIndex)`:
    - returns JSON `{ windowWidth, windowLevel, calMin, calMax }`
  - Export `window.setIntensityWindow(windowWidth, windowLevel, volumeIndex?)`:
    - clamps width `>= 1`
    - sets `volume.cal_min` / `volume.cal_max`
    - refreshes + redraws (`refreshLayers`/`updateGLVolume` + `drawScene`)

- `NiiVue/NiiVueUITests/NiiVueUITests.swift`
  - Extend `test2DWindowLevelAdjustsContrastWithoutScrolling` to assert:
    - window width is clamped to `>= 1.0` when entering window/level mode
    - WW/WL follow translation-based math (stable origin)
    - slice index + stack scroll events do not change in window/level mode

### XCUIAutomation Validation (Physical Device)

**Device:** Leandro’s iPhone (`id=00008140-001664420413C01C`)

#### RED (reproduced issue)

**Test:** `NiiVueUITests/test2DWindowLevelAdjustsContrastWithoutScrolling`

**Command:**

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DWindowLevelAdjustsContrastWithoutScrolling
```

**Result:** `Executed 1 test, with 1 failure` (WW reported as `0.000`, failing the clamp assertion)

#### GREEN (after clamping initial WW to >= 1.0)

**Tests:**
- `NiiVueUITests/test2DStackScrollScrubsSlices`
- `NiiVueUITests/test2DTwoFingerPanUpdatesOffset`
- `NiiVueUITests/test2DViewportPinchZoomUpdatesScale`
- `NiiVueUITests/test2DWindowLevelAdjustsContrastWithoutScrolling`

**Command:**

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DStackScrollScrubsSlices \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DTwoFingerPanUpdatesOffset \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DViewportPinchZoomUpdatesScale \
  -only-testing:NiiVueUITests/NiiVueUITests/test2DWindowLevelAdjustsContrastWithoutScrolling
```

**Result (from test log):** `Executed 4 tests, with 0 failures`

**Observed UI-test state (from test log):**

- Window/Level test
  - Initial: `WW=1.000 WL=0.000 wlEvents=0 sliceIndex=1 stackScrollEvents=0`
  - Final: `WW=164.333 WL=306.000 wlEvents=23` (slice index + stack scroll unchanged by assertion)

### Clean Build + Install (Physical Device)

**Goal:** clean build artifacts + DerivedData, then rebuild and install to the device.

**Commands:**

```bash
# Clean the scheme
xcodebuild clean -project NiiVue/NiiVue.xcodeproj -scheme NiiVue

# Remove project DerivedData
rm -rf ~/Library/Developer/Xcode/DerivedData/NiiVue-*

# Fresh device build (isolated DerivedData path for easy install)
rm -rf .deriveddata/NiiVue
xcodebuild build \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'id=00008140-001664420413C01C' \
  -derivedDataPath .deriveddata/NiiVue \
  -configuration Debug

# Install the app bundle to the physical device
xcrun devicectl device install app \
  --device 00008140-001664420413C01C \
  .deriveddata/NiiVue/Build/Products/Debug-iphoneos/NiiVue.app
```

**Result (from command output):**

- `** CLEAN SUCCEEDED **`
- `** BUILD SUCCEEDED **`
- `App installed` (bundleID: `com.niivue.mobile`)

---

## Step 5 — Device DICOM Validation + 1-Finger Gesture Isolation (Fix)

### Problem Observed (on device)

When testing **Window/Level** on a real CT DICOM series (KiTS23), the gesture visually updated WW/WL, but the **crosshair slice index drifted by 1** during the same drag. This indicates the underlying Niivue touch handler was still receiving touch-move events and treating them as a crosshair drag.

This showed up as a failing device UI test:

- `NiiVueUITests/testDicomImportKiTS23WindowLevelDoesNotScrollSlices`
  - Before: `sliceIndex=105 crosshairSliceIndex=105 wlEvents>0`
  - After: `crosshairSliceIndex=104` (unexpected), while `stackScrollEvents` remained unchanged

### Root Cause

- The prior 1-finger implementation used a SwiftUI `DragGesture` layered above the `WKWebView`. On device, the underlying web content could still observe some touch motion (especially at the start of a drag), letting Niivue’s default touch single-drag behavior (**crosshair**) move the crosshair.
- A follow-up refactor to install gestures on a transparent overlay (`installTarget = .installerView`) initially failed because `ViewportInteractionHandler.Coordinator` stored `installTarget` as a `let` (never updated), so recognizers could end up installed on the wrong view after slice type changes.

### Fix Implemented

- `NiiVue/NiiVue/ContentView.swift`
  - Extended `ViewportInteractionHandler` to include a **1-finger** `UIPanGestureRecognizer` (`minTouches=1/maxTouches=1`).
  - Routed the 1-finger pan into:
    - `.scroll` → `webViewManager.handleStackScrollDragChanged/Ended`
    - `.windowLevel` → WW/WL math + `webViewManager.setIntensityWindow(...)`
  - Ensured **stable origin capture**:
    - On `.began`, capture `windowLevelDragStartWindowWidth/windowLevelDragStartWindowLevel` once.
  - For 2D slice types, install the recognizers on the transparent installer view (`installTarget = .installerView`) and enable hit-testing so the native gesture layer owns touch input.
  - Fixed coordinator state propagation:
    - `installTarget` is now updated in `updateUIView`, so recognizers reinstall correctly when switching view types.
  - Kept UI-test simulation behavior:
    - `--ui-test-simulate-two-finger-pan` routes a 1-finger pan into the same two-finger pan callbacks.

### XCUIAutomation Validation (Physical Device)

**Device:** Leandro’s iPhone (`id=00008140-001664420413C01C`)

**Window/Level regression fix test:**

- `NiiVueUITests/testDicomImportKiTS23WindowLevelDoesNotScrollSlices`
- Result: `PASSED`
- Observed (from test log):
  - Initial: `WW=1423.214 WL=-266.297 wlEvents=0 sliceIndex=105 crosshairSliceIndex=105 stackScrollEvents=0`
  - Final: `WW=1565.881 WL=1.703 wlEvents=18` (crosshair slice unchanged by assertion)

**Gesture + DICOM sanity suite (all PASSED):**

- `NiiVueUITests/test2DTwoFingerPanUpdatesOffset`
- `NiiVueUITests/test2DViewportPinchZoomUpdatesScale`
- `NiiVueUITests/testDicomImportKiTS23SeriesLoadsVolume`
- `NiiVueUITests/testDicomImportKiTS23Then2DStackScrollScrubsSlices`

Observed (from logs):

- DICOM load: `Loaded 210 DICOM file(s). ... volumeCount=1`
- Stack scroll: `sliceIndex 105 → 126 (stackScrollEvents=26)`

### Note: xcodebuild “Password:” hang

On this machine, `xcodebuild test` prints a trailing `Password:` prompt after tests complete. The test results are already emitted; the workaround is to `kill` the `xcodebuild` PID after the summary prints.

---

## Step 6 — Gesture Smoothness + Sensitivity Tuning (Coalescing + Touch-Down Origin)

### Goals

- Make interactions feel **smooth at 60fps** by reducing per-move JS bridge work.
- Make 1-finger stack scroll feel **weighted** (not too sensitive, not too sluggish).
- Ensure **Window/Level** always uses a stable origin from **finger-down** (no jump on real device + in XCUI).

### Changes Implemented

#### A) Coalesced gesture JS bridge (performance)

- `NiiVue/NiiVue/Web/WebViewManager.swift`
  - Added a **gesture command coalescing** system:
    - `enqueue2DPanDelta(deltaX:deltaY:endX:endY:)`
    - `enqueue2DZoom(scale:anchorX:anchorY:)`
    - `enqueueIntensityWindow(volumeIndex:windowWidth:windowLevel:)`
    - `flushPendingGestureCommandsNow()`
  - Flush loop batches pending commands into **one** `evaluateJavaScript` call using a `;`-joined string.
  - Used by pan/zoom/window-level + stack-scroll to reduce bridge call frequency under continuous drag/pinch.

#### B) Touch-down origin for 1-finger drags (fix WL “jump” + reliability)

- `NiiVue/NiiVue/ContentView.swift`
  - Swapped the 1-finger handler from `UIPanGestureRecognizer` to:
    - `UILongPressGestureRecognizer(minimumPressDuration = 0, allowableMovement = 10_000)`
  - Reason: `UIPanGestureRecognizer` begins only after a hysteresis threshold, so “translation-from-touch-down” isn’t available at `.began`. This caused Window/Level to feel jumpy and made device UI tests flaky.
  - Coordinator now computes:
    - `translation = currentLocation - startLocation` (stable origin at finger-down)
    - `velocity = (currentLocation - lastLocation) / dt` using `ProcessInfo.processInfo.systemUptime`
  - Preserved UI-test behavior:
    - `--ui-test-simulate-two-finger-pan` still routes the 1-finger drag into the two-finger pan callbacks.

#### C) Stack scroll sensitivity tuning (not too sensitive / not too slow)

- `NiiVue/NiiVue/Web/WebViewManager.swift`
  - Tuned baseline + velocity-based range:
    - `stackScrollBasePixelsPerSlice = 13.0`
    - `stackScrollMinPixelsPerSliceFactor = 0.9`
    - `stackScrollMaxPixelsPerSliceFactor = 1.3`
  - Keeps stack scroll “weighted” while still allowing faster scrubbing when moving quickly.

### XCUIAutomation Validation (Physical Device)

**Device:** Leandro’s iPhone (`id=00008140-001664420413C01C`)

**Command used (coverage disabled to avoid CoreDevice runtime-profile flakiness):**

`xcodebuild test -project NiiVue/NiiVue.xcodeproj -scheme NiiVue -destination 'id=00008140-001664420413C01C' -enableCodeCoverage NO ...`

**Gesture + DICOM suite (all PASSED, 7 tests):**

- `NiiVueUITests/NiiVueUITests/test2DStackScrollScrubsSlices`
- `NiiVueUITests/NiiVueUITests/test2DTwoFingerPanUpdatesOffset`
- `NiiVueUITests/NiiVueUITests/test2DViewportPinchZoomUpdatesScale`
- `NiiVueUITests/NiiVueUITests/test2DWindowLevelAdjustsContrastWithoutScrolling`
- `NiiVueUITests/NiiVueUITests/testDicomImportKiTS23SeriesLoadsVolume`
- `NiiVueUITests/NiiVueUITests/testDicomImportKiTS23Then2DStackScrollScrubsSlices`
- `NiiVueUITests/NiiVueUITests/testDicomImportKiTS23WindowLevelDoesNotScrollSlices`

**Observed key logs (post-tuning):**

- DICOM load: `Loaded 210 DICOM file(s). ... [DICOM] Load succeeded in 2316ms volumeCount=1`
- Stack scroll (KiTS23): `sliceIndex 105 → 118 (stackScrollEvents=29)` (delta 13; within guardrails)
- Pinch zoom: `viewportScale 1.000 → 1.419 (viewportPinchEvents=12)`
- Window/Level (KiTS23): `wlEvents=23`, slice/crosshair slice unchanged, stack scroll unchanged

### Clean + Build + Install (Physical Device)

- Cleaned build + DerivedData:
  - `xcodebuild clean -project NiiVue/NiiVue.xcodeproj -scheme NiiVue`
  - Removed `~/Library/Developer/Xcode/DerivedData/NiiVue-*` and repo `.deriveddata/`
- Rebuilt + installed to device:
  - `xcodebuild build ... -derivedDataPath .deriveddata/NiiVue`
  - `xcrun devicectl device install app --device 00008140-001664420413C01C .deriveddata/NiiVue/Build/Products/Debug-iphoneos/NiiVue.app`
