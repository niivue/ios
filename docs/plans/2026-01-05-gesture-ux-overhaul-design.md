# iOS DICOM Viewer Gesture UX Overhaul — Analysis + Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task‑by‑task.

**Goal:** Make touch/gesture navigation feel native, discoverable, and fast for iPhone/iPad medical image review (2D + 3D) while staying consistent with Apple HIG and common DICOM viewer conventions.

**Architecture:** Keep high‑frequency gesture processing inside the embedded Niivue/React canvas (JS) to avoid Swift↔︎JS roundtrips during drags/pinches; use SwiftUI for tool affordances, accessibility fallbacks, and state display. Add an iOS-focused “interaction preset” layer that maps gestures to Niivue operations.

**Tech Stack:** SwiftUI + `WKWebView` (Swift), React/TypeScript + `@niivue/niivue` (WebGL) + custom JS↔︎iOS messaging bridge.

---

## Status (as of 2026-01-05)

Running implementation log: `05-01-26_Gesture_Redesign.md`

- **Step 1 (implemented + validated):** 1‑finger vertical “Stack Scroll” is currently implemented natively in SwiftUI (`DragGesture`) and bridges into Niivue via `WebViewManager.handleStackScrollDragChanged(...)` for reliable XCUIAutomation coverage.
- **Step 2 (implemented + validated):** 2‑finger “Pan” is implemented as `TwoFingerPanHandler` (UIKit `UIPanGestureRecognizer` with `min=2/max=2`) and bridges into Niivue via `beginTwoFingerPan()` + `pan2DFromScreenDrag(...)`.
  - **UI-test note:** iPhone XCUIAutomation can’t synthesize true 2‑finger drags, so tests use `--ui-test-simulate-two-finger-pan` to drive the same path with a 1‑finger `DragGesture` (test-only).

This plan below remains the long-term target; once the full gesture set stabilizes, high-frequency gesture processing can be migrated further into the JS layer where it improves smoothness and reduces Swift↔︎JS roundtrips.

## 1) Codebase Deep Dive (What Exists Today)

### 1.1 High-level architecture

- **SwiftUI app** embeds a `WKWebView` via `WebViewManager` and loads the bundled React app using a custom `niivue://` scheme.
  - Swift bridge: `NiiVue/NiiVue/Web/WebViewManager.swift`
  - SwiftUI root UI: `NiiVue/NiiVue/ContentView.swift`
  - React app entry: `NiiVue/React/src/App.tsx`

### 1.2 Where gestures actually live

There are *no* UIKit or SwiftUI gesture recognizers implemented in Swift for the viewer surface. Touch is handled inside the WebGL canvas by Niivue’s own touch event listeners.

The current app’s “gesture controls” are therefore mostly:

1) **Niivue’s built-in touch scheme** (inside `@niivue/niivue`):
- `touchstart`/`touchmove`/`touchend` are registered in `NiiVue/React/node_modules/@niivue/niivue/src/niivue/index.ts` via `registerInteractions()`.
- Default touch mapping is driven by:
  - `opts.dragModePrimary` (default: `DRAG_MODE.crosshair`)
  - `opts.dragMode` (default: `DRAG_MODE.contrast`)
  - `opts.doubleTouchTimeout` / `opts.longTouchTimeout`
  - optional `opts.touchEventConfig` (`setTouchEventConfig`) — **not currently used by this app**

2) **A custom app-level touch hook** added in React:
- `NiiVue/React/src/App.tsx` adds a `touchstart` listener to auto-enable clip planes when pinching inside the render tile (so pinch behaves like “scroll slices through 3D”).

3) **A SwiftUI “Settings” sheet** that changes Niivue modes:
- `ContentView.swift` exposes a “Drag action (double tap)” picker that calls:
  - `WebViewManager.setDragMode(dragMode:)` → `window.setDragMode(...)` → `nv.opts.dragMode = ...`

4) **Slice stepping buttons** in SwiftUI (not gesture-based):
- `ContentView.incrementSlice()` / `decrementSlice()` call `WebViewManager.moveCrosshairInVox(...)`, and the UI provides plus/minus buttons.

### 1.3 Niivue’s default touch UX (as shipped)

From Niivue source (`@niivue/niivue`):

- **Single-finger drag** uses **`dragModePrimary`** (default: `crosshair`) — so the first interaction most users try (one finger drag) primarily moves crosshair, not window/level.
- **Double tap** triggers a brightness/contrast reset and sets internal “doubleTouch” state.
  - Double-tap + drag then becomes “the configured drag mode” (default: `contrast`).
- **Pinch gesture** is implemented as “scroll delta” and sent into `sliceScroll2D`.
  - In practice, pinch is used for **slice scrolling by default**, and only behaves like **zoom** when Niivue’s `dragMode === pan` (see `SliceNavigation.shouldApplyZoomScroll`).

### 1.4 Evidence in this repo

- Double-tap-centric “drag mode” UI:
  - `NiiVue/NiiVue/ContentView.swift` label: **“Drag action (double tap)”**
- Pinch-in in 3D is explicitly tested as “slice scroll via clip plane”:
  - `NiiVue/NiiVueUITests/NiiVueUITests.swift` → `testRenderPinchEnablesClipPlaneForSliceScroll()`
- React layer auto-enables clip plane on pinch start in render tile:
  - `NiiVue/React/src/App.tsx` → `enableClipPlaneOnRenderPinchStart`

---

## 2) Why This Feels “Not User-Friendly” (Root Causes)

### 2.1 Conflicts with iOS mental models (HIG mismatch)

Apple HIG explicitly lists:
- **Double tap** → “Zoom in; zoom out if already zoomed in”
- **Zoom (pinch)** → “Zoom a view; magnify content”

Current behavior deviates:
- **Pinch is (often) slice scroll**, not zoom.
- **Double tap resets window/level**, not zoom.

This violates expectation and harms “seamlessness”, because users spend time discovering the app’s rules instead of reviewing the scan.

**HIG reference (via Cupertino):**
- `Gestures|AppleDeveloperDocumentation` — `hig://general/gestures-appledeveloperdocumentation`

### 2.2 Discoverability + efficiency issues

- The primary workflow actions (scroll slices, window/level, zoom/pan) require:
  - learning a **double-tap then drag** interaction, and/or
  - opening a **Settings** sheet to change modes, and/or
  - using **step buttons** for slice navigation.
- For large CT/MR stacks, pinch-based slice scrolling is slower and fatiguing vs a dedicated scroll gesture (typically one-finger vertical swipe).

### 2.3 Missing “interaction preset” layer

Niivue ships with a generalized interaction model (neuroimaging + desktop-friendly defaults). This app currently exposes **raw Niivue dragMode** controls rather than presenting an iOS-optimized preset aligned with DICOM viewing conventions.

### 2.4 Technical constraint: Swift↔︎JS bridge isn’t suited for per-frame gestures

Even if we used UIKit/SwiftUI gesture recognizers, piping every drag delta across `evaluateJavaScript` would likely add latency and jitter. The design should keep per-frame gesture handling inside the JS side (WebGL thread/loop) and only synchronize state at “human time” boundaries (gesture end, mode change, HUD updates).

---

## 3) External Research: What “Best-in-Class” Mobile DICOM Gestures Look Like

### 3.1 3DICOM Mobile (explicit touch gesture guidance)

3DICOM Mobile’s published mapping for navigating scans:

**2D:**
- **Swipe up/down (one finger)** → scroll slices
- **Two-finger drag** → pan (move image)
- **Pinch** → zoom in/out

**3D:**
- **One-finger drag** → rotate
- **Two-finger drag** → pan
- **Pinch** → zoom in/out

Source:
- https://3dicomviewer.com/knowledgebase/3dicom-mobile-touch-gestures/

### 3.2 Inobitec DICOM Viewer (multi-touch gesture table)

Inobitec’s gesture table shows a common pattern:
- **Two-finger swipe** → move (pan)
- **Pinch** → zoom
- **Rotate gesture** → rotate image/model
- **Window width/level** → **three-finger** swipes (left/right for width; up/down for level)

Important caveat for iOS: **three-finger gestures are reserved by the system** (undo/copy/paste), and Apple HIG warns against conflicts. So while the *idea* (“windowing uses a distinct multi-finger gesture”) is useful, **the exact three-finger mapping should not be used on iOS**.

Source:
- https://inobitec.com/manual/dicomviewer/program-window-elements/gesture-control-on-the-touchscreen/

### 3.3 PostDICOM (directional window/level mapping)

Directional mapping often used for window/level:
- horizontal motion ↔ window center (brightness)
- vertical motion ↔ window width (contrast)

Source:
- https://www.postdicom.com/en/knowledge-base/application-interface/using-window-level-pan-zoom-rotation-thickness-scroll-functions

---

## 4) Recommended UX Target (iOS-first “DICOM Navigation Preset”)

### 4.1 Design principles (applied)

- **HIG-consistent defaults**: pinch and double-tap should zoom/magnify.
- **Primary task first**: fast slice scrolling must be one gesture, not a tool change or UI button mash.
- **Mode changes are explicit and local**: when a tool mode exists (measure/draw), show it clearly and provide an easy exit.
- **Always offer a fallback**: key actions must be possible without gestures (accessibility + discoverability).
- **High-frequency work stays in JS**: avoid per-frame Swift↔︎JS command traffic.

### 4.2 Gesture map (proposal)

This is the proposed “seamless” mapping for the main viewer surface.

#### 2D viewing (Axial/Coronal/Sagittal, single-tile or within MPR)

- **One-finger swipe up/down**: scroll slices (stack navigation)
- **Pinch**: zoom in/out (centered on gesture centroid)
- **Two-finger drag**: pan
- **Double tap**: zoom toggle (fit ↔︎ last zoom, or fit ↔︎ 1:1)
- **Single tap**: move crosshair to tapped location (and update HUD values)
- **Long press**: “probe” (show HU/intensity at point) + optional haptic

Window/level (W/L):
- Prefer **explicit UI control** (window presets + “W/L tool toggle”), because multi-finger W/L conflicts with iOS system gestures.
- When W/L tool is active: **one-finger drag** adjusts window/level (horizontal = center; vertical = width) using Niivue’s `DRAG_MODE.windowing` behavior.

#### 3D render viewing

- **One-finger drag**: rotate (azimuth/elevation)
- **Pinch**: zoom
- **Two-finger drag**: pan
- **Two-finger vertical swipe** (optional “Clip Mode” enabled): adjust clip plane depth (acts like “scroll through”)
- **Double tap**: reset 3D view (orientation + zoom)

### 4.3 How this maps onto Niivue (important constraint)

Niivue already provides:
- `DRAG_MODE.windowing` (continuous W/L) for mouse/touch moves
- `setTouchEventConfig({ singleTouch, doubleTouch })`
- `sliceScroll2D(...)` (used internally for pinch / wheel)

But Niivue **does not implement** “two-finger drag pan” for touch out of the box; its two-touch handler focuses on pinch distance, not centroid translation. Therefore:

**The app should add a small JS “gesture adapter” layer** on the canvas for iOS that:
- translates **two-finger centroid movement** into Niivue pan (2D) and/or model pan (3D)
- translates **pinch scale** into Niivue zoom (2D/3D)
- translates **one-finger vertical swipe** into `sliceScroll2D` (stack scroll)
- keeps Niivue’s built-in interactions available for specialized modes (measurement/drawing) when appropriate

---

## 5) Implementation Plan (Bite-Sized, with Files)

> **Note:** This plan is written to minimize risk: introduce an *opt-in* “iOS DICOM preset” first, then make it default once validated.

### Task 1: Document current gesture behavior (baseline)

**Files:**
- Create: `docs/reports/gesture-baseline.md`

**Steps:**
1. Write a short baseline doc describing the current mapping (single touch = crosshair, pinch = slice scroll, double tap = reset/windowing workflow).
2. Link to the exact code locations:
   - `NiiVue/React/node_modules/@niivue/niivue/src/niivue/index.ts` touch handlers
   - `NiiVue/React/src/App.tsx` clip-plane pinch hook
   - `NiiVue/NiiVue/ContentView.swift` drag mode picker + slice buttons

### Task 2: Add an “interaction preset” switch in React (no behavior change yet)

**Files:**
- Modify: `NiiVue/React/src/App.tsx`
- Create: `NiiVue/React/src/interaction/presets.ts`

**Steps:**
1. Add a `setInteractionPreset(presetName)` function on `window`.
2. Implement `presets.ts` with:
   - `applyDefaultPreset(nv)`
   - `applyIOSDicomPreset(nv)` (initially identical to default)
3. Call `applyDefaultPreset(nv)` after `attachToCanvas`.

### Task 3: Make pinch behave like zoom (HIG alignment)

**Files:**
- Modify: `NiiVue/React/src/interaction/presets.ts`
- Modify: `NiiVue/React/src/App.tsx`

**Steps:**
1. In `applyIOSDicomPreset(nv)`, set Niivue touch configuration:
   - `nv.setTouchEventConfig({ singleTouch: DRAG_MODE.crosshair, doubleTouch: DRAG_MODE.pan })` *(temporary, so we don’t break existing behavior during rollout)*
2. Add a capture-phase `touchmove` listener on the canvas that:
   - detects `touches.length === 2`
   - prevents Niivue’s default pinch-to-slice-scroll behavior
   - converts pinch scale into 2D zoom updates (`nv.setPan2Dxyzmm([... , zoom])`) and 3D zoom (`nv.setScale(...)`) depending on whether the gesture is inside a render tile
3. Ensure meta viewport and CSS prevent page zoom:
   - Update `NiiVue/React/index.html` and ensure build includes `maximum-scale=1, user-scalable=no`
   - Add `touch-action: none;` to the canvas (or its container) in `NiiVue/React/src/App.css`

### Task 4: Implement one-finger slice scrolling (stack navigation)

**Files:**
- Create: `NiiVue/React/src/interaction/stackScroll.ts`
- Modify: `NiiVue/React/src/App.tsx`

**Steps:**
1. Add a capture-phase `touchmove` listener for `touches.length === 1` that:
   - interprets vertical delta as slice scroll
   - calls `nv.sliceScroll2D(delta, x, y)` in controlled increments (thresholded per N pixels, not per raw pixel)
2. Add inertial “fling” option (P1): if the user swipes fast and lifts, continue stepping slices briefly with deceleration (implement in JS with `requestAnimationFrame`).
3. Keep existing plus/minus buttons in SwiftUI as fallback (accessibility), but consider hiding them by default once gestures are validated.

### Task 5: Implement two-finger pan (centroid translation)

**Files:**
- Create: `NiiVue/React/src/interaction/twoFingerPan.ts`
- Modify: `NiiVue/React/src/App.tsx`

**Steps:**
1. Track the centroid of the two touches over time.
2. Apply centroid deltas as pan:
   - 2D: update `pan2Dxyzmm` (via `nv.setPan2Dxyzmm`) using a calibrated pixel→mm scale (derive from Niivue’s existing projection values if available; otherwise start with a conservative factor and tune on-device).
   - 3D: pan the model/camera if Niivue exposes a stable API; otherwise limit to 2D first.
3. Allow pinch+pan simultaneously (common expectation): process both distance change (zoom) and centroid translation (pan) in the same gesture update.

### Task 6: Make double tap a zoom toggle (HIG)

**Files:**
- Modify: `NiiVue/React/src/App.tsx`
- Modify: `NiiVue/React/src/interaction/presets.ts`

**Steps:**
1. Add a capture-phase double-tap recognizer on canvas (timestamp + distance threshold).
2. On double tap:
   - 2D: toggle zoom (`pan2Dxyzmm[3]`) between fit and last zoom (store last non-1 zoom)
   - 3D: toggle `nv.volScaleMultiplier`/`nv.setScale(...)`
3. Prevent Niivue’s internal “double tap resets contrast” behavior when the iOS DICOM preset is enabled.

### Task 7: Expose a minimal in-app “Tool Bar” (SwiftUI) for W/L, Measure, Draw

**Files:**
- Modify: `NiiVue/NiiVue/ContentView.swift`
- Modify: `NiiVue/NiiVue/Web/WebViewManager.swift`

**Steps:**
1. Add a bottom toolbar (or floating control) with 3–5 primary tools:
   - Navigate (default)
   - Window/Level (W/L)
   - Measure
   - Draw/Segment
2. Tool selection updates a single JS-side state variable (no per-frame bridging).
3. When W/L tool is active:
   - configure Niivue touch mapping to make one-finger drag do `DRAG_MODE.windowing`
4. Ensure all tools have non-gesture alternatives (buttons/sliders) for accessibility.

### Task 8: Instrumentation + UI tests for gestures (prevent regressions)

**Files:**
- Modify: `NiiVue/React/src/App.tsx`
- Modify: `NiiVue/NiiVue/Web/WebViewManager.swift`
- Modify: `NiiVue/NiiVueUITests/NiiVueUITests.swift`

**Steps:**
1. Add lightweight JS→Swift messages for:
   - current zoom
   - current slice index (or crosshair voxel index)
   - current interaction preset + tool
2. Update UI tests to validate:
   - pinch changes zoom (not slice index)
   - one-finger swipe changes slice index
   - double tap toggles zoom
3. Keep the existing clip-plane pinch test behind a feature flag if clip mode remains supported.

---

## 6) Validation Checklist (What “Seamless” Means)

- Pinch zoom works everywhere and never zooms the web page.
- One-finger swipe scrolls slices smoothly (no stutter, no accidental tool triggers).
- Two-finger pan and pinch can be combined naturally.
- Double tap zoom toggle is reliable and matches expectation.
- Tool switching is discoverable and reversible.
- Apple Pencil doesn’t fight finger gestures (Pencil draws; fingers navigate).
- UI tests assert the above via instrumentation labels/messages.

---

## 7) Notes / Next Questions (to confirm before implementation)

1. Primary persona: radiologist-grade viewer vs “clinician quick review”? This affects whether W/L must be gesture-first or preset-first.
2. Should slice scroll be vertical (standard) or horizontal (matches existing CT plan doc that says L/R)? Recommend **vertical** to align with most viewers and avoid conflict with common horizontal swipe navigation.
3. Do we want clip-plane “slice scroll” in 3D? If yes, it should be an explicit “Clip Mode” rather than overriding pinch (pinch should zoom).
