# CT Adaptive Engine (CT Urinary Presets) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Implement the CT Urinary Tract Adaptive Preset Engine end-to-end (TypeScript engine + Swift bridge + SwiftUI controls), using strict TDD and Option **B** auto-apply (`nv.onImageLoaded` gated by `window.autoApplyCTPreset` set from Swift).

**Architecture:** The adaptive engine runs inside the React/TypeScript Niivue layer and exposes a small, stable `window.*` API. Swift configures `window.autoApplyCTPreset` (and can call preset APIs for manual control) via a testable service layer (`CTPresetService`) and `WebViewManager` forwarding methods.

**Tech Stack:** React/TypeScript (Vitest), SwiftUI + WebKit (XCTest), NiiVue v0.66.0.

**Specs to follow:**
- Canonical spec: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md`
- Derived docs: `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`, `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`, `docs/CT_ADAPTIVE_ENGINE_INDEX.md`

**Note on commits:** This plan includes `git commit` steps for hygiene; skip commits unless explicitly requested.

---

## Task 1: TypeScript — RED tests for `HistogramAnalyzer.compute`

**Files:**
- Create: `NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`

**Step 1: Write failing tests**
- Cover:
  - NIfTI scaling via `hdr.scl_slope/scl_inter`
  - Percentiles `p2/p50/p98` computed via bin cumulative sum
  - Constant-volume edge case (`globalMin == globalMax`) returns finite percentiles + safe histogram

**Step 2: Run test to verify it fails**
- Run: `cd NiiVue/React && npm test -- src/bridge/ctAdaptiveEngine.test.ts`
- Expected: FAIL (module missing).

---

## Task 2: TypeScript — GREEN `HistogramAnalyzer` implementation

**Files:**
- Create: `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`

**Step 1: Implement minimal `HistogramAnalyzer.compute(volume)`**
- Implement per guide Section **4.1**.
- Use `for` loops (TypedArray perf).

**Step 2: Run tests**
- Run: `cd NiiVue/React && npm test -- src/bridge/ctAdaptiveEngine.test.ts`
- Expected: PASS (histogram tests).

---

## Task 3: TypeScript — RED tests for phase detection + window calculation

**Files:**
- Modify: `NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`

**Step 1: Add failing tests**
- `PhaseDetector.classify(...)`:
  - corticomedullary: peak >211 HU with sufficient fraction
  - excretory: peak 200–400 HU with sufficient fraction
  - nephrographic: peak 80–150 HU + median 60–120 HU
  - unenhanced: median <80 HU and no peaks >150 HU
- `AdaptiveWindowCalculator.compute(...)`:
  - clamps to CT HU domain `[-1024, 3071]`
  - enforces min width (>=50 HU)
  - safe fallback for invalid windows

**Step 2: Run tests to verify RED**
- Run: `cd NiiVue/React && npm test -- src/bridge/ctAdaptiveEngine.test.ts`
- Expected: FAIL (missing classes/methods).

---

## Task 4: TypeScript — GREEN `PhaseDetector` + `AdaptiveWindowCalculator`

**Files:**
- Modify: `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`

**Step 1: Implement minimal code per guide Sections 4.2–4.3**
**Step 2: Run tests (must be green)**

---

## Task 5: TypeScript — RED tests for colormap generation + apply pipeline

**Files:**
- Modify: `NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`

**Step 1: Add failing tests**
- `ColormapGenerator.generate(window, phase)` returns 256-entry RGBA arrays and correct `min/max`.
- `CTAdaptiveEngine.applyAdaptivePreset(nv, volumeIndex)`:
  - registers custom colormap via `nv.addColormap`
  - sets volume `cal_min/cal_max`
  - calls `nv.setColormap(volume.id, cmapName)`

**Step 2: Run tests to verify RED**

---

## Task 6: TypeScript — GREEN `ColormapGenerator` + `CTAdaptiveEngine`

**Files:**
- Modify: `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`

**Step 1: Implement minimal code per guide Section 4.4 + Section 5 reference file**
**Step 2: Run tests**

---

## Task 7: TypeScript — RED tests for preset library + window bindings

**Files:**
- Create: `NiiVue/React/src/bridge/ctUrinaryPresets.test.ts`

**Step 1: Add failing tests**
- `listCTUrinaryPresets()` returns stable list.
- `applyCTUrinaryPreset(...)` routes to correct fixed/adaptive behavior.

**Step 2: Run tests to verify RED**

---

## Task 8: TypeScript — GREEN preset library

**Files:**
- Create: `NiiVue/React/src/bridge/ctUrinaryPresets.ts`

**Step 1: Implement per guide Section 5 (File 2)**
**Step 2: Run tests**

---

## Task 9: TypeScript — RED test for Option B auto-apply gating

**Files:**
- Create: `NiiVue/React/src/bridge/ctAutoApply.test.ts`

**Step 1: Write failing test**
- Given a `onImageLoaded` handler:
  - if `window.autoApplyCTPreset === true`, it calls `window.applyAdaptiveCTUrinaryPreset(0)`
  - otherwise, it does nothing

**Step 2: Run test to verify RED**

---

## Task 10: TypeScript — GREEN Option B integration + window API

**Files:**
- Create: `NiiVue/React/src/bridge/ctAutoApply.ts`
- Modify: `NiiVue/React/src/App.tsx`

**Step 1: Implement `makeOnImageLoadedHandler(...)` in `ctAutoApply.ts`**
**Step 2: Wire `nv.onImageLoaded` in `App.tsx` to use the handler**
**Step 3: Bind `window.applyAdaptiveCTUrinaryPreset`, `window.listCTUrinaryPresets`, `window.applyCTUrinaryPreset`**
**Step 4: Run `npm test` (all)**

---

## Task 11: Swift — RED tests for `CTPresetService`

**Files:**
- Create: `NiiVue/NiiVueTests/CTPresetServiceTests.swift`

**Step 1: Write failing XCTest**
- Validate generated JS commands:
  - `applyAdaptivePreset` → `window.applyAdaptiveCTUrinaryPreset(<index>)`
  - `applyPreset` → `window.applyCTUrinaryPreset(<index>, "<name>")` (JSON-escaped)
  - `listPresets` parses `[String]` from JSON result
  - `setAutoApplyCTPreset(true/false)` → `window.autoApplyCTPreset = true/false`

**Step 2: Run test to verify RED**
- Run: `xcodebuild test -project NiiVue/NiiVue.xcodeproj -scheme NiiVue -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:NiiVueTests/CTPresetServiceTests`

---

## Task 12: Swift — GREEN `CTPresetService` + `WebViewManager` forwarding

**Files:**
- Create: `NiiVue/NiiVue/Services/CTPresetService.swift`
- Modify: `NiiVue/NiiVue/Web/WebViewManager.swift`

**Step 1: Implement `CTPresetService` per guide Section 5 (File 4)**
**Step 2: Add `WebViewManager` convenience methods**
**Step 3: Run Swift tests**

---

## Task 13: Swift/WebKit — set `window.autoApplyCTPreset` from Swift (best practice)

**Files:**
- Modify: `NiiVue/NiiVue/Web/WebViewManager.swift`
- Modify: `NiiVue/NiiVue/ContentView.swift`

**Step 1: Inject initial default via `WKUserScript` (`.atDocumentStart`)**
**Step 2: After `isReady == true`, set current toggle value via `setAutoApplyCTPreset(...)`**
**Step 3: Toggle updates push into JS**

---

## Task 14: SwiftUI — CT Presets UI (toggle + picker)

**Files:**
- Modify: `NiiVue/NiiVue/ContentView.swift`

**Step 1: Add CT preset button + sheet**
**Step 2: Add toggle `autoApplyCTPreset` and preset picker**
**Step 3: Apply preset via `webViewManager.applyCTUrinaryPreset(...)`**

---

## Task 15: Swift — decode `updateUI` CT analysis payload (optional but recommended)

**Files:**
- Modify: `NiiVue/NiiVue/Web/WebViewManager.swift`

**Step 1: Define `CTPresetAnalysisPayload` Codable**
**Step 2: Update `handleScriptMessage` for `updateUI` to parse `type == \"ctPresetAnalysis\"`**

---

## Task 16: Verification

**Step 1: Run TypeScript tests**
- Run: `cd NiiVue/React && npm test`

**Step 2: Run Swift unit tests**
- Run: `xcodebuild test -project NiiVue/NiiVue.xcodeproj -scheme NiiVue -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:NiiVueTests`

**Step 3: (Optional) Run UI tests**
- Run: `xcodebuild test -project NiiVue/NiiVue.xcodeproj -scheme NiiVue -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max' -only-testing:NiiVueUITests`

