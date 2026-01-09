# CT Urinary Tract Adaptive Engine - Visual Overview

**Status:** Visual overview — derived from the implementation guide
**Last Verified:** 2026-01-08
**Validated Against:** `niivue-ios-foundation` @ `2c8ffcd6c2e3f0b143e5f610ce031ef6235262d7`
**Upstream API Reference:** `/Users/leandroalmeida/niivue` @ `f0c010293b01cfb162e2b9e959c27717b07686f1`

## Executive Summary

This document provides visual diagrams and workflows for the CT Urinary Tract Adaptive Preset Engine implementation.

Note: The “Detected Phase” UI is implemented via JS → Swift reporting: after applying the adaptive preset, JS posts `{ type: "ctPresetAnalysis", payload: ... }` via the `updateUI` `WKScriptMessageHandler`, and Swift displays it in the CT Presets sheet.

---

## 1. System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              USER INTERFACE                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      SwiftUI (ContentView.swift)                    │   │
│  │  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────┐    │   │
│  │  │ CT Presets  │  │ Auto-Apply  │  │ Detected Phase     │    │   │
│  │  │   Button    │  │   Toggle     │  │   Readout          │    │   │
│  │  └─────────────┘  └──────────────┘  └─────────────────────┘    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ↕
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SERVICE LAYER                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                   CTPresetService.swift                             │   │
│  │  • applyAdaptivePreset(volumeIndex)                              │   │
│  │  • listPresets() → [String]                                        │   │
│  │  • applyPreset(volumeIndex, presetName)                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ↕
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BRIDGE LAYER                                       │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │              WebViewManager.swift Extension                         │   │
│  │  • applyAdaptiveCTUrinaryPreset(volumeIndex)                      │   │
│  │  • listCTUrinaryPresets()                                         │   │
│  │  • applyCTUrinaryPreset(volumeIndex, presetName)                 │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ↕
┌─────────────────────────────────────────────────────────────────────────────┐
│                       JAVASCRIPT BRIDGE                                    │
│  window.applyAdaptiveCTUrinaryPreset(0)  →  React/TypeScript Layer     │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ↕
┌─────────────────────────────────────────────────────────────────────────────┐
│                      ADAPTIVE ENGINE LAYER                                │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                  ctAdaptiveEngine.ts                                │   │
│  │  ┌──────────────────┐  ┌──────────────────┐  ┌────────────────┐   │   │
│  │  │ HistogramAnalyzer│→ │  PhaseDetector  │→ │WindowCalculator│   │   │
│  │  │  • 1001 bins     │  │  • Arterial >211 │  │ • Phase-spec   │   │   │
│  │  │  • Peak detect   │  │  • Excretory 200-400│   │ windows       │   │   │
│  │  │  • Percentiles   │  │  • Nephro 80-150│  └────────────────┘   │   │
│  │  └──────────────────┘  └──────────────────┘           ↓          │   │
│  │                                                     │ColormapGenerator  │   │
│  │  ┌──────────────────────────────────────────────────────────────┐ │   │
│  │  │  • Phase-optimized RGB gradients (orange, red, blue, yellow)  │ │   │
│  │  │  • Phase-optimized alpha curves (smooth, step, bimodal)       │ │   │
│  │  └──────────────────────────────────────────────────────────────┘ │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ↕
┌─────────────────────────────────────────────────────────────────────────────┐
│                       NiiVue CORE LAYER                                    │
│  • nv.addColormap(name, colormap)                                         │
│  • nv.setColormap(volume.id, name)                                        │
│  • nv.volumes[0].cal_min = colormap.min                                   │
│  • nv.volumes[0].cal_max = colormap.max                                   │
│  • nv.updateGLVolume() + nv.drawScene()                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      ↕
                            USER SEES OPTIMIZED VISUALIZATION
```

---

## 2. Data Flow Diagram

```
┌────────────────┐
│ Load CT Volume │
└───────┬────────┘
        ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 1: Histogram Computation (TBD; measure on iOS WebKit)     │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Input:  NVImage (img, hdr)                              │    │
│  │ Process: Two-pass (min/max + histogram) unless using      │    │
│  │          fixed-HU binning or sampling                     │    │
│  │   for i = 0 to img.length:                               │    │
│  │     hu = img[i] * scl_slope + scl_inter                 │    │
│  │     bins[clamp(binIndex)]++                              │    │
│  │ Output: HistogramResult                                   │    │
│  │   • bins[1001]  → 1001 bin counts                        │    │
│  │   • peaks[...]  → Key intensity peaks (top-by-count + HU-band candidates) │    │
│  │   • percentiles → {p2, p50, p98} in HU                  │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 2: Phase Detection (expected fast; measure)               │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Input:  HistogramResult                                   │    │
│  │ Process: Evidence-based decision tree                     │    │
│  │   IF arterialPeak > 211 HU + count > 5%                 │    │
│  │     THEN "corticomedullary" (conf: 0.95)                 │    │
│  │   ELSE IF excretoryPeak 200-400 HU + count > 3%          │    │
│  │     THEN "excretory" (conf: 0.90)                         │    │
│  │   ELSE IF nephroPeak 80-150 HU + median 60-120           │    │
│  │     THEN "nephrographic" (conf: 0.85)                    │    │
│  │   ELSE IF median < 80 HU + no peaks > 150                │    │
│  │     THEN "unenhanced" (conf: 0.90)                       │    │
│  │   ELSE                                                   │    │
│  │     "delayed" (conf: 0.70)                               │    │
│  │ Output: PhaseResult                                       │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 3: Window Calculation (expected fast; measure)            │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Input:  PhaseResult + HistogramResult                    │    │
│  │ Process: Phase-specific window selection                  │    │
│  │   corticomedullary: arterialPeak ± 75 HU                 │    │
│  │   excretory:       100 to (excretoryPeak + 100) HU       │    │
│  │   nephrographic:   60 to 180 HU                          │    │
│  │   unenhanced:     -100 to 600 HU                         │    │
│  │   delayed:         p2 to p98 HU                           │    │
│  │ Constraints: finite HU, calMax - calMin ≥ 50             │    │
│  │ Output: WindowResult                                      │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 4: Colormap Generation (expected fast; measure)           │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Input:  WindowResult + PhaseResult                        │    │
│  │ Process: Interpolate 256 RGB + 256 alpha values           │    │
│  │   for i = 0 to 255:                                      │    │
│  │     hu = calMin + (calMax - calMin) * (i / 255)          │    │
│  │     RGB[i] = interpolateRGB(colorNodes, hu)               │    │
│  │     A[i] = interpolateAlpha(alphaNodes, hu) * 255          │    │
│  │ Output: CustomColormap                                    │    │
│  │   • R, G, B, A, I arrays (256 values each)                 │    │
│  └─────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 5: Apply to NiiVue (rendering; depends on volume/GPU)     │
│  • nv.addColormap("ct_urinary_adaptive", colormap)             │
│  • nv.setColormap(volume.id, "ct_urinary_adaptive")            │
│  • volume.cal_min = 68, volume.cal_max = 165                  │
│  • nv.updateGLVolume()                                         │
│  • nv.drawScene()                                              │
└─────────────────────────────────────────────────────────────────┘
        ↓
┌─────────────────────────────────────────────────────────────────┐
│ STEP 6: Report Analysis to iOS UI (recommended)                 │
│  • window.webkit.messageHandlers.updateUI.postMessage({         │
│      type: "ctPresetAnalysis", payload: { phase, ... }          │
│    })                                                           │
│  • Swift updates @MainActor state (Detected Phase readout)      │
└─────────────────────────────────────────────────────────────────┘
        ↓
                   OPTIMIZED VISUALIZATION DISPLAYED
```

---

## 3. Phase Detection Decision Tree

```
                    ┌─────────────────┐
                    │ Histogram Ready │
                    └────────┬────────┘
                             ↓
              ┌────────────────────────┐
              │ Arterial peak >211 HU? │
              │ AND count > 5%?       │
              └────────┬───────────────┘
                       ↓
           ┌─────────────┴─────────────┐
           │ YES                        │ NO
           ↓                            ↓
    ┌──────────────┐         ┌────────────────────────┐
    │ Cortico-     │         │ High-density peak      │
    │ medullary    │         │ 200-400 HU?            │
    │ (conf: 0.95) │         │ AND count > 3%?        │
    └──────────────┘         └────────┬───────────────┘
                                     ↓
                              ┌─────────────┴─────────────┐
                              │ YES                        │ NO
                              ↓                            ↓
                       ┌──────────────┐         ┌────────────────────────┐
                       │ Excretory    │         │ Parenchymal peak       │
                       │ (conf: 0.90) │         │ 80-150 HU?              │
                       └──────────────┘         │ AND median 60-120 HU?  │
                                                 └────────┬───────────────┘
                                                          ↓
                                               ┌─────────────┴─────────────┐
                                               │ YES                        │ NO
                                               ↓                            ↓
                                        ┌──────────────┐         ┌────────────────────────┐
                                        │ Nephrographic│         │ Median < 80 HU?        │
                                        │ (conf: 0.85) │         │ AND no peaks > 150 HU? │
                                        └──────────────┘         └────────┬───────────────┘
                                                                     ↓
                                                          ┌─────────────┴─────────────┐
                                                          │ YES                        │ NO
                                                          ↓                            ↓
                                                   ┌──────────────┐         ┌──────────────┐
                                                   │ Unenhanced  │         │ Delayed     │
                                                   │ (conf: 0.90) │         │ (conf: 0.70) │
                                                   └──────────────┘         └──────────────┘
```

---

## 4. Window Selection by Phase

```
┌─────────────────────┬──────────────┬──────────────┬─────────────────────────────────────┐
│ Phase               │ calMin (HU)  │ calMax (HU)  │ Rationale                            │
├─────────────────────┼──────────────┼──────────────┼─────────────────────────────────────┤
│ Unenhanced          │ -100         │ 600          │ Wide window for stone detection    │
│                     │ (or p2)       │ (or p98)     │ Stones: 400-600 HU                │
├─────────────────────┼──────────────┼──────────────┼─────────────────────────────────────┤
│ Corticomedullary    │ arterialPeak │ arterialPeak │ Narrow window for vascular detail  │
│                     │ - 75         │ + 75         │ Center on arterial enhancement      │
│                     │              │              │ Example: 211 ± 75 → 136-286 HU    │
├─────────────────────┼──────────────┼──────────────┼─────────────────────────────────────┤
│ Nephrographic       │ 60           │ 180          │ Mid-range for parenchyma            │
│                     │ (or p2)       │ (or p98)     │ Cortex: 80-150 HU                  │
├─────────────────────┼──────────────┼──────────────┼─────────────────────────────────────┤
│ Excretory           │ 100          │ excretoryPeak│ High contrast for collecting       │
│                     │              │ + 100 (max 450)│ Opacified ureters: 280-380 HU       │
├─────────────────────┼──────────────┼──────────────┼─────────────────────────────────────┤
│ Delayed             │ p2           │ p98          │ Adaptive to distribution             │
│                     │ (percentile) │ (percentile) │ Fallback for ambiguous cases       │
└─────────────────────┴──────────────┴──────────────┴─────────────────────────────────────┘
```

---

## 5. Colormap Comparison by Phase

```
PHASE: NEPHROGRAPHIC (Most Common)
┌─────────────────────────────────────────────────────────────────┐
│ Color Gradient:  Black → Orange → White                         │
│ Alpha Curve:      Smooth ramp (0% → 34% → 89%)                │
│ Window:           60 - 180 HU                                   │
│ Use Case:         Renal mass characterization, parenchymal disease│
└─────────────────────────────────────────────────────────────────┘

PHASE: CORTICOMEDULLARY (Vascular)
┌─────────────────────────────────────────────────────────────────┐
│ Color Gradient:  Black → Red → Orange → White                   │
│ Alpha Curve:      Vascular-favored (0% → 30% → 80% → 95%)      │
│ Window:           136 - 286 HU (centered on arterial peak)      │
│ Use Case:         Renal artery assessment, RCC vascularity      │
└─────────────────────────────────────────────────────────────────┘

PHASE: EXCRETORY (Collecting System)
┌─────────────────────────────────────────────────────────────────┐
│ Color Gradient:  Black → Blue → Cyan → White                    │
│ Alpha Curve:      Bimodal (0% → 20% → 70% → 95%)               │
│ Window:           100 - 450 HU                                   │
│ Use Case:         Urothelial tumors, hydronephrosis, ureters    │
└─────────────────────────────────────────────────────────────────┘

PHASE: UNENHANCED (Stones)
┌─────────────────────────────────────────────────────────────────┐
│ Color Gradient:  Black → Yellow → White                          │
│ Alpha Curve:      Step function (0% → 0% → 70% → 90%)          │
│ Window:           -100 - 600 HU                                  │
│ Use Case:         Kidney stone detection, hemorrhage            │
└─────────────────────────────────────────────────────────────────┘

PHASE: DELAYED (Fallback)
┌─────────────────────────────────────────────────────────────────┐
│ Color Gradient:  Black → Orange → White (same as nephrographic) │
│ Alpha Curve:      Smooth ramp (0% → 34% → 89%)                 │
│ Window:           p2 - p98 HU (adaptive)                         │
│ Use Case:         Persistent enhancement, ambiguous cases      │
└─────────────────────────────────────────────────────────────────┘
```

---

## 6. Implementation Timeline

```
PHASE 1 (Days 1-2): TypeScript Layer
├─ ctAdaptiveEngine.ts (Histogram → Phase → Window → Colormap)
├─ ctUrinaryPresets.ts (preset library + bridge)
├─ ctAutoApply.ts (Option B gate for nv.onImageLoaded)
├─ App.tsx (bind `window.*` functions for Swift)
└─ Unit tests (Vitest) for the adaptive engine

PHASE 2 (Day 3): Swift Service Layer
├─ CTPresetService.swift (service API)
└─ WebViewManager.swift (convenience bridge methods)

PHASE 3 (Day 4): SwiftUI UI Layer
└─ ContentView.swift (CT preset UI + auto-apply toggle + detected phase readout)

PHASE 4 (Days 5-7): Testing & Validation
├─ Performance benchmarking (WKWebView/XCTest)
├─ Integration tests (Swift/XCTest)
└─ Clinical validation planning + labeled dataset definition (results TBD)
```

---

## 7. File Structure Overview

Note: Paths below reflect the current implementation in this repo.

```
niivue-ios-foundation/
├── NiiVue/
│   ├── React/src/
│   │   ├── App.tsx
│   │   └── bridge/
│   │       ├── ctAdaptiveEngine.ts
│   │       ├── ctAdaptiveEngine.test.ts
│   │       ├── ctUrinaryPresets.ts
│   │       ├── ctUrinaryPresets.test.ts
│   │       ├── ctAutoApply.ts
│   │       └── ctAutoApply.test.ts
│   │
│   ├── NiiVue/
│   │   ├── ContentView.swift
│   │   ├── Services/
│   │   │   └── CTPresetService.swift
│   │   └── Web/
│   │       └── WebViewManager.swift
│   │
│   ├── NiiVueTests/
│   │   ├── CTPresetServiceTests.swift
│   │   └── WebViewManagerStateTests.swift
│   │
│   └── NiiVueUITests/
│       └── NiiVueUITests.swift
│
└── docs/
    ├── ct-urinary-tract-adaptive-engine-implementation-guide.md  ← THIS REPORT (134 KB)
    └── ct-urinary-tract-adaptive-engine-implementation-summary.md ← SUMMARY
```

---

## 8. Key Performance Metrics

```
┌──────────────────────────────────────┬─────────────┬──────────────┐
│ Metric                                │ Target      │ Measured     │
├──────────────────────────────────────┼─────────────┼──────────────┤
│ Histogram computation time            │ <300ms       │ TBD          │
│ Phase detection time                  │ <10ms        │ TBD          │
│ Window calculation time               │ <10ms        │ TBD          │
│ Colormap generation time              │ <50ms        │ TBD          │
│ TOTAL ANALYSIS TIME                  │ <500ms       │ TBD          │
├──────────────────────────────────────┼─────────────┼──────────────┤
│ Memory overhead (peak)                │ <100MB       │ TBD          │
│ Rendering FPS                         │ 60 FPS       │ TBD          │
│ Phase detection accuracy               │ >90%        | TBD          │
│ Visualization quality (radiologist)    │ ≥4.0/5.0    │ TBD          │
└──────────────────────────────────────┴─────────────┴──────────────┘
```

---

## 9. Clinical Use Cases

```
┌─────────────────────────────────────────────────────────────────────┐
│ USE CASE 1: Renal Cell Carcinoma (RCC) Characterization              │
├─────────────────────────────────────────────────────────────────────┤
│ Scenario: 65-year-old patient with renal mass                       │
│ Acquisition: Corticomedullary phase (40-70s delay)                  │
│                                                                         │
│ WITHOUT Adaptive Preset:                                            │
│   - Fixed window 114-302 HU                                        │
│   - Arterial enhancement at 240 HU compressed into upper 40%      │
│   - Poor visualization of tumor vascularity                        │
│   - Radiologist manually adjusts: 136-286 HU (+15 seconds)        │
│                                                                         │
│ WITH Adaptive Preset:                                               │
│   - Detects "corticomedullary" phase (confidence: 0.95)          │
│   - Applies window: 165-315 HU (centered on arterial peak)        │
│   - Red-orange gradient highlights vessels                         │
│   - Immediate visualization of tumor hypervascularity             │
│   - Time saved: 15 seconds                                        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ USE CASE 2: Urothelial Carcinoma of Ureter                          │
├─────────────────────────────────────────────────────────────────────┤
│ Scenario: 58-year-old patient with hematuria                        │
│ Acquisition: Excretory phase (7-10 min delay)                       │
│                                                                         │
│ WITHOUT Adaptive Preset:                                            │
│   - Fixed window 114-302 HU                                        │
│   - Opacified ureter at 320 HU appears too bright (washed out)     │
│   - Tumor obscurred by contrast                                      │
│   - Radiologist manually adjusts: 100-420 HU (+20 seconds)        │
│                                                                         │
│ WITH Adaptive Preset:                                               │
│   - Detects "excretory" phase (confidence: 0.90)                   │
│   - Applies window: 100-420 HU                                      │
│   - Blue-cyan gradient highlights collecting system               │
│   - Ureter and tumor clearly visible                               │
│   - Time saved: 20 seconds                                        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ USE CASE 3: Kidney Stone Detection                                  │
├─────────────────────────────────────────────────────────────────────┤
│ Scenario: 42-year-old patient with flank pain                       │
│ Acquisition: Unenhanced phase                                      │
│                                                                         │
│ WITHOUT Adaptive Preset:                                            │
│   - Fixed window 114-302 HU                                        │
│   - Calcium oxalate stone at 520 HU is clipped (invisible)        │
│   - Stone missed on initial review                                  │
│   - Radiologist manually adjusts: -100 to 600 HU (+25 seconds)     │
│                                                                         │
│ WITH Adaptive Preset:                                               │
│   - Detects "unenhanced" phase (confidence: 0.90)                 │
│   - Applies window: -100 to 600 HU                                 │
│   - Yellow-white gradient highlights high-density structures        │
│   - Stone immediately visible                                      │
│   - Time saved: 25 seconds (and potential missed diagnosis)       │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 10. Testing Workflow

```
┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 1: Unit Testing (TypeScript)                                 │
├─────────────────────────────────────────────────────────────────────┤
│ Framework: Vitest                                                     │
│ File: ctAdaptiveEngine.test.ts                                       │
│                                                                     │
│ Tests:                                                              │
│  ✓ HistogramAnalyzer.compute()                                      │
│  ✓ PhaseDetector.classify()                                         │
│  ✓ AdaptiveWindowCalculator.compute()                              │
│  ✓ ColormapGenerator.generate()                                    │
│                                                                     │
│ Command: npm test -- ctAdaptiveEngine.test.ts                      │
│                                                                     │
│ Coverage Goal: >90%                                                │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 2: Unit Testing (Swift)                                      │
├─────────────────────────────────────────────────────────────────────┤
│ Framework: XCTest                                                    │
│ File: CTPresetServiceTests.swift                                   │
│                                                                     │
│ Tests:                                                              │
│  ✓ CTPresetService.applyAdaptivePreset()                          │
│  ✓ CTPresetService.listPresets()                                   │
│  ✓ CTPresetService.applyPreset()                                   │
│  ✓ Error handling                                                  │
│                                                                     │
│ Command: xcodebuild test -scheme NiiVue                             │
│                                                                     │
│ Coverage Goal: >85%                                                │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 3: Performance Benchmarking                                   │
├─────────────────────────────────────────────────────────────────────┤
│ Tool: Chrome DevTools Performance Tab                               │
│ File: ctAdaptiveEngine.test.ts (Performance section)               │
│                                                                     │
│ Metrics:                                                            │
│  • Histogram computation: <300ms                                   │
│  • Total analysis: <500ms                                         │
│  • Memory overhead: <100MB                                         │
│  • Rendering FPS: 60 FPS                                           │
│                                                                     │
│ Test Volume: 512×512×200 (52M voxels)                              │
│ Device: iPhone 12+                                                 │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│ PHASE 4: Clinical Validation                                       │
├─────────────────────────────────────────────────────────────────────┤
│ Dataset: 25 CT urography volumes (5 per phase)                      │
│ Reviewers: Board-certified radiologists                            │
│                                                                     │
│ Validation Protocol:                                                │
│  1. Load test volume in NiiVue iOS                                │
│  2. Apply adaptive preset                                           │
│  3. Record detected phase + confidence                             │
│  4. Radiologist scores: 1-5 Likert scale                           │
│  5. Compare to manual window/level                                 │
│                                                                     │
│ Success Criteria:                                                  │
│  • Phase detection accuracy: >90% (≥23/25)                         │
│  • Visualization quality: Mean ≥4.0                               │
│  • Time savings: ≥50%                                              │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 11. Quick Reference Cards

### Card 1: Phase Detection Rules

```
┌─────────────────────────────────────────────────────────────────┐
│ CORTICOMEDULLARY (40-70s delay)                                  │
│ Arterial peak >211 HU + count >5% of voxels                      │
│ Confidence: 0.95                                                 │
│ Window: arterialPeak ± 75 HU                                      │
│ Color: Red-orange gradient                                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ EXCRETORY (7-10 min delay)                                      │
│ High-density peak 200-400 HU + count >3% of voxels               │
│ Confidence: 0.90                                                 │
│ Window: 100 to (excretoryPeak + 100) HU                         │
│ Color: Blue-cyan gradient                                        │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ NEPHROGRAPHIC (100-120s delay)                                  │
│ Parenchymal peak 80-150 HU + median 60-120 HU                    │
│ Confidence: 0.85                                                 │
│ Window: 60 to 180 HU                                             │
│ Color: Orange gradient                                            │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ UNENHANCED (pre-contrast)                                       │
│ Median <80 HU + no peaks >150 HU                                │
│ Confidence: 0.90                                                 │
│ Window: -100 to 600 HU                                           │
│ Color: Yellow-white gradient                                      │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ DELAYED (15+ min delay)                                         │
│ Ambiguous distribution (fallback)                                │
│ Confidence: 0.70                                                 │
│ Window: p2 to p98 HU (percentile-based)                        │
│ Color: Orange gradient                                            │
└─────────────────────────────────────────────────────────────────┘
```

### Card 2: Hounsfield Unit Reference

```
┌─────────────────────────────────────┬─────────────────────────────┐
│ Structure/Tissue                     │ HU Range                     │
├─────────────────────────────────────┼─────────────────────────────┤
│ Air                                 │ -1000 HU                     │
│ Fat                                 │ -50 to -100 HU                │
│ Water                               │ 0 HU                         │
│ Soft tissue (unenhanced)            │ +20 to +70 HU                │
│ Renal cortex (corticomedullary)    │ 150-250 HU                   │
│ Renal cortex (nephrographic)       │ 80-150 HU                    │
│ Renal medulla (nephrographic)       │ 60-100 HU                    │
│ Renal arteries (enhanced)          │ >211 HU                      │
│ Collecting system (excretory)       │ 200-400 HU                   │
│ Calcium oxalate stones              │ 400-600 HU                   │
│ Uric acid stones                    │ 200-450 HU                   │
│ Bone                                │ 400-1000 HU                  │
└─────────────────────────────────────┴─────────────────────────────┘
```

**Note on the existing `ct_kidneys` preset (NiiVue):** It defines control points with indices `I` in the range `0…255` and linearly maps those indices onto the HU range `[min,max]`:

- `hu = min + (I / 255) * (max - min)` (for `ct_kidneys`, `min=114`, `max=302`, so `I=103` maps to ~190 HU)

### Card 3: File Checklist

```
IMPLEMENTATION CHECKLIST

TypeScript Layer:
✓ ctAdaptiveEngine.ts (implemented)
  ✓ HistogramAnalyzer class
  ✓ PhaseDetector class
  ✓ AdaptiveWindowCalculator class
  ✓ ColormapGenerator class
  ✓ CTAdaptiveEngine main interface
  ✓ Unit tests (ctAdaptiveEngine.test.ts)

✓ ctUrinaryPresets.ts (implemented)
  ✓ applyAdaptiveCTUrinaryPreset() (+ `updateUI` `ctPresetAnalysis` report on iOS)
  ✓ listCTUrinaryPresets()
  ✓ applyCTUrinaryPreset()
  ✓ Fixed preset implementations

✓ ctAutoApply.ts (implemented)
  ✓ Auto-apply gate (`window.autoApplyCTPreset`)

✓ App.tsx (modified)
  ✓ Import statements
  ✓ Window interface declarations
  ✓ Bridge function definitions
  ✓ useEffect bindings
  ✓ onImageLoaded auto-apply logic

Swift Layer:
✓ CTPresetService.swift (implemented)
  ✓ setAutoApplyCTPreset()
  ✓ applyAdaptivePreset()
  ✓ listPresets()
  ✓ applyPreset()

✓ WebViewManager.swift (modified)
  ✓ Inject default `window.autoApplyCTPreset` (document start, `.page` world)
  ✓ CT preset convenience methods
  ✓ Decode `ctPresetAnalysis` from `updateUI`

✓ ContentView.swift (modified)
  ✓ CT Presets button + sheet
  ✓ Auto-apply toggle (AppStorage)
  ✓ Detected phase readout (`niivue.ctPresetAnalysis.phase`)
  ✓ Accessibility labels

Testing:
✓ CTPresetServiceTests.swift (implemented)
  ✓ Unit tests for service methods

✓ UI tests (implemented)
  ✓ CT Presets sheet opens
  ✓ CT analysis label appears after applying adaptive preset

Documentation:
✓ Implementation guide (complete)
□ Clinical validation report (PENDING)
□ User documentation (PENDING)
```

---

**End of Visual Overview**

## Document Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-01-08 | Initial visual overview | NiiVue iOS Team |
| 1.1 | 2026-01-08 | Synced with canonical guide (reporting contract + timeline/metrics placeholders) | NiiVue iOS Team |
| 1.2 | 2026-01-08 | Updated to reflect implemented engine + on-device verification | NiiVue iOS Team |

---

**Document Version:** 1.2
**Date:** 2026-01-08
**Author:** NiiVue iOS Development Team
