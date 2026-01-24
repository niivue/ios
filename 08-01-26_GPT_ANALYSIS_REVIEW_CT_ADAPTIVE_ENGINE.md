# GPT Analysis Review — CT Urinary Tract Adaptive Engine (NiiVue iOS Foundation)

**Date:** 2026-01-08  
**Reviewer:** GPT-5.2 (Codex CLI)  
**Scope:** Audit of implementation concepts + guides for a “CT Urinary Tract Adaptive Preset Engine” intended to optimize CT urography visualization (2D + 3D) inside an iOS app that embeds a Niivue (WebGL) React viewer via `WKWebView`.

---

## Update (2026-01-09)

Since this review was written, the CT Adaptive Engine has been implemented in this repo and verified on-device. As a result, the “missing NEW source files” finding is no longer applicable.

- Implementation is now present under:
  - `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`, `ctUrinaryPresets.ts`, `ctAutoApply.ts` (plus Vitest tests)
  - `NiiVue/NiiVue/Services/CTPresetService.swift`
  - `NiiVue/NiiVue/Web/WebViewManager.swift` (injects `window.autoApplyCTPreset`, decodes `ctPresetAnalysis`)
  - `NiiVue/NiiVue/ContentView.swift` (CT Presets sheet + analysis display)
- Verification status (2026-01-09):
  - TypeScript tests: ✅ PASS — 6 files, 39 tests (`cd NiiVue/React && npm test`)
  - On-device unit tests: ✅ PASS — 87 tests, 0 failures (xcresult: `/tmp/NiiVueDerivedData-NiiVueTests-Device-20260109/Logs/Test/Test-NiiVue-2026.01.09_00-01-52--0300.xcresult`)
  - On-device UI tests: ✅ PASS — 30 tests, 1 skipped, 0 failures (xcresult: `/tmp/NiiVueDerivedData-NiiVueUITests-Device-20260109b/Logs/Test/Test-NiiVue-2026.01.09_00-08-02--0300.xcresult`)
- Documentation suite status is updated to **Implemented** (see `docs/CT_ADAPTIVE_ENGINE_INDEX.md`).
- Full on-device setup + commands: `08_01_26_GPT_OnDevice_XCUITest_Report.md`.

---

## 0) What I Did (Method)

1. Read and cross-compared the requested documentation suite:
   - `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md`
   - `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
   - `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`
   - `docs/CT_ADAPTIVE_ENGINE_INDEX.md`
2. Audited the **actual implementation state** of this repo (`/Users/leandroalmeida/niivue-ios-foundation`) to verify whether the “ready for implementation / copy‑paste ready” claims match reality, and to locate integration points.
3. Audited the upstream/original Niivue source code at `/Users/leandroalmeida/niivue` (focus: intensity/windowing, colormaps, render pipeline implications).
4. Verified Apple/WebKit API facts via Cupertino MCP and grounded recommendations on official documentation (see §10).

---

## 1) Executive Summary (High-Signal Findings)

### Bottom line

The documentation suite is ambitious and well-structured, but it is **not audit-clean**: multiple claims and code listings diverge from the current codebase and from Niivue’s actual APIs/behavior. Several issues are “P0” because they would cause **incorrect results, failed compilation, or misguiding implementation**.

### P0 findings (must fix before implementation)

1. **[RESOLVED] Referenced “new” source files were not present in the repo** (e.g., `ctAdaptiveEngine.ts`, `ctUrinaryPresets.ts`, `CTPresetService.swift`, and associated tests). These files are now implemented in this repo (see “Update (2026-01-09)”).
2. **Histogram percentile bug in the guide’s `HistogramAnalyzer.compute()`**: the sentinel approach (`p2 === globalMin`) can silently produce wrong percentile values when the 2nd percentile equals the global minimum (a common case when background intensities dominate). This undermines phase classification and window selection.
3. **Colormap registration uses a likely-nonexistent API**: the guide calls `(nv as any).cmapper.addColormap(...)`. In Niivue’s source, `cmapper` is a module-level singleton and **not a `Niivue` instance property**; the supported API is `nv.addColormap(key, cmap)` (or importing `cmapper` directly).
4. **Swift service example will not compile as written against this repo’s WebViewManager**: it accesses `webViewManager.evaluator`, but in `NiiVue/NiiVue/Web/WebViewManager.swift` the evaluator is `private`.

### P1 findings (high risk / likely to cause clinical or UX failure)

1. **Phase detection logic is under-specified for real-world CT stacks**: relying on the “top 5 peaks” can miss clinically meaningful but low-volume enhancement peaks; fixed voxel-fraction thresholds (e.g., 5%) are unvalidated and likely dataset-dependent.
2. **Windowing logic contradicts CT physics and Niivue support for negatives**: the adaptive path clamps `calMin` to `>= 0`, contradicting the docs’ own “-100…600” stone window and suppressing HU<0 tissues (fat/air) that matter for anatomy context and segmentation.
3. **Performance claims are ungrounded and internally inconsistent** (single pass vs. double pass; “early exit” claimed but not implemented; memory math assumes 8-byte scalars without JS array overhead).

### P2 findings (quality gaps)

1. UX guidance for “Detected Phase” is incomplete: the SwiftUI mock shows the field, but there is no reliable bridge back from JS → Swift to supply phase/confidence.
2. The docs’ analysis of `ct_kidneys` contains at least one factual mismatch: `ct_kidneys.json` min/max are `114..302` (not “0 HU at index 0”), and the mapping for the intermediate node depends on LUT interpolation.

---

## 2) Reality Check: Current Code vs. Documentation Claims

### Docs say (repeated across the suite)
- “✅ Complete - Ready for Implementation”
- “Complete code for 6 files (copy‑paste ready)”
- “6 Files to Create/Modify”

### Repo reality (this workspace)

**Present & relevant today**
- React viewer exists: `NiiVue/React/src/App.tsx`  
- Existing Swift↔JS bridge exists: `NiiVue/NiiVue/Web/WebViewManager.swift` and helpers:
  - `NiiVue/NiiVue/Web/JavaScriptEvaluating.swift`
  - `NiiVue/NiiVue/Web/WKWebView+JavaScriptEvaluating.swift`
  - `NiiVue/NiiVue/Web/JavaScriptQuote.swift`
  - URL scheme handler: `NiiVue/NiiVue/Web/NiivueURLSchemeHandler.swift`
- SwiftUI viewer shell exists: `NiiVue/NiiVue/ContentView.swift`

**Previously missing (now implemented):**
- `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
- `NiiVue/React/src/bridge/ctUrinaryPresets.ts`
- `NiiVue/React/src/bridge/ctAutoApply.ts`
- `NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`
- `NiiVue/React/src/bridge/ctUrinaryPresets.test.ts`
- `NiiVue/React/src/bridge/ctAutoApply.test.ts`
- `NiiVue/NiiVue/Services/CTPresetService.swift`
- `NiiVue/NiiVueTests/CTPresetServiceTests.swift`

**Implication**
Treat the documentation suite as a **design/spec** (not an implementation report). The suite can still be valuable, but it must be re-labeled and corrected so the team doesn’t assume the code already exists or has been benchmarked/validated.

---

## 3) Architecture Audit: Proposed vs Actual

### 3.1 Proposed architecture (from the docs suite)

The docs propose:
- A **TypeScript adaptive engine** computing histogram → phase → window → colormap.
- A JS API exposed on `window.*`:
  - `window.applyAdaptiveCTUrinaryPreset(volumeIndex)`
  - `window.listCTUrinaryPresets()`
  - `window.applyCTUrinaryPreset(volumeIndex, presetName)`
- A Swift “service layer” `CTPresetService` that triggers these JS functions via `WKWebView` evaluation.
- A SwiftUI sheet UI for preset selection + auto-apply.

This high-level approach is coherent with the current project architecture (SwiftUI shell + WKWebView + React/Niivue), but the proposed implementation details need correction to match:
- existing bridge patterns (`JavaScriptQuote`, `JavaScriptEvaluating`)
- Niivue’s real API surface and performance characteristics
- Apple/WebKit best practices (see §10)

### 3.2 Actual architecture (this repo today)

From `docs/ARCHITECTURE_DIAGRAM.md` and the current code:
- Niivue runs inside a bundled React app (built by an Xcode run script) served via a custom `niivue://` scheme (`WKURLSchemeHandler`).
- Swift communicates to JS primarily by:
  - `evaluateJavaScript` for synchronous expressions/side-effects
  - `callAsyncJavaScript` for Promise-returning JS (via `callAsyncString(...)`)
- JS communicates to Swift via `WKScriptMessageHandler` message channels, with a weak proxy handler to avoid retain cycles.

### 3.3 Architectural fit: what is good

1. **Bridge safety**: `JavaScriptQuote.jsonStringLiteral` avoids injection/quoting bugs and should remain the standard for all string arguments.
2. **Concurrency discipline**: `WebViewManager` is `@MainActor`, and `WKWebView` evaluation APIs are `@MainActor` in Apple docs; this alignment is correct.
3. **Resource loading model**: the custom scheme approach (`WKURLSchemeHandler`) is exactly the right shape for on-device medical content without base64 overhead.

### 3.4 Architectural gaps: what must be specified

1. **Where does “auto-apply” live?**
   - Docs sometimes imply JS decides based on `window.autoApplyCTPreset`, but there is no authoritative source of truth for that setting in the current architecture.
   - Recommendation: make auto-apply a SwiftUI preference and trigger apply in Swift upon `volumeLoaded` reception (so it’s deterministic and testable).
2. **How does SwiftUI learn “detected phase”?**
   - If the phase detector runs in JS, Swift must receive the result via a message handler (or by evaluating a string-returning JS function).
   - Recommendation: add a dedicated message channel (e.g., `ctPresetAnalysis`) or use `WKScriptMessageHandlerWithReply` if you want request/response semantics.

---

## 4) Algorithm Audit: Histogram → Phase → Window → Colormap

This section evaluates the *documented* algorithm and code snippets for correctness, numerical robustness, and integration realism.

### 4.1 Histogram Analyzer (documented `HistogramAnalyzer.compute(volume)`)

#### Critical correctness issue: percentile sentinel bug

The docs’ `HistogramAnalyzer.compute` initializes:
- `let p2 = globalMin` (same for `p50`, `p98`)
- then sets percentiles when `cumSum >= target && p2 === globalMin`

If the percentile threshold occurs in the first bin (common when background dominates at the global minimum), then `p2` remains equal to `globalMin` and **will keep being overwritten** for every subsequent bin after the threshold, because `cumSum >= p2Target` remains true.

**Impact:** incorrect `p2` → wrong window bounds → wrong phase decision (because `p50`/`p98` can be computed similarly with poor sentinels).

**Fix pattern:** use `null`/`undefined` or boolean flags to ensure “set once”.

#### Numerical edge cases not handled

1. **Constant-valued volumes**: if `globalMax === globalMin`, bin width becomes 0 and binning becomes undefined.
2. **Outlier sensitivity**: min/max derived from a full scan allows single voxel outliers to enlarge the range, reducing bin resolution and destabilizing peak detection.

#### Performance claims do not match the code

The docs repeatedly call this “single pass”, but the published code:
- scans the entire array once for min/max
- scans again for histogram bins
- then loops again for peak detection and percentiles (on the bins)

That is fine conceptually, but the doc should state “two-pass scan” and justify it, or adopt a fixed HU binning scheme (see recommendations).

#### Recommendation: fixed HU histogram window + sampling strategy

For CT urography phase detection, you usually do not need the **true global min/max** of the entire volume. A fixed HU domain (e.g., `[-1024, 3071]` or a narrower clinical domain) yields stable bin widths and makes rules reproducible across datasets.

Also consider:
- center-crop sampling (Niivue’s `calMinMax(..., isBorder: true)` already does this)
- random voxel sampling for speed when voxel counts are huge
- optional smoothing of the histogram before peak detection

### 4.2 Peak detection strategy

The docs detect local maxima with a 1-step neighbor comparison and then keep only the **top 5 peaks** by count.

**Problem:** clinically relevant contrast peaks may be small fractions of a large CT volume. Keeping only the top 5 peaks by count risks dropping the signal you are explicitly trying to detect (e.g., arterial enhancement) if it is not among the largest peaks.

**Recommendation:** evaluate enhancement evidence using:
- region-of-interest sampling (kidney mask, central crop, or intensity band statistics), or
- scanning bins in target HU bands even if those bins are not “top peaks”.

### 4.3 Phase detection rules (`PhaseDetector.classify`)

The rules are plausible as a starting hypothesis, but the documentation overstates certainty:
- “>90% accuracy on labeled dataset”
- specific confidence values (0.95/0.90/0.85/0.70)

**Audit judgment:** these are currently unverified claims. The docs need:
- the dataset definition (where it lives, DICOM vs NIfTI, acquisition protocols)
- a confusion matrix
- which ROI or body-region assumptions were used
- failure modes (e.g., low-dose CT noise, metal artifacts, non-urography phases)

### 4.4 Window selection logic (`AdaptiveWindowCalculator.compute`)

#### Contradiction: clamping `calMin >= 0`

The adaptive window logic proposes phase-specific windows that include negative HU (e.g., “-100..600”), but then imposes:
- `calMin = Math.max(calMin, 0)` “Non-negative”

This is both clinically and technically problematic:
- CT HU are routinely negative (air/fat), and suppressing them can remove important context.
- Niivue’s render pipeline explicitly supports negative mapping via `cal_minNeg`/`cal_maxNeg` (see Niivue shader logic in upstream code).

**Recommendation:** remove the “non-negative” clamp unless you have a validated reason; if you need to de-emphasize negatives, do it via transfer function/alpha, not by hard-clipping HU.

#### Constraints should be phase-aware

The doc applies a universal:
- minimum width 50 HU
- max cap 1000 HU

Those constraints can be reasonable, but they need to be tied to:
- actual render quality in Niivue’s WebGL pipeline
- CT urography clinical requirements (e.g., stones/bone can exceed 1000 HU)

### 4.5 Colormap generation and registration (`ColormapGenerator`)

#### API mismatch: `nv.cmapper` is not a stable contract

In Niivue’s source, the public API is:
- `nv.addColormap(key, cmap)`
- `nv.setColormap(volumeId, colormapName)`

`cmapper` exists as a module singleton (`export const cmapper = new ColorTables()`), but it is not a documented `Niivue` instance property. Therefore:
- `const cmapper = (nv as any).cmapper` is likely `undefined`.

**Recommendation:** use `nv.addColormap(...)` and avoid reaching into non-public internals.

#### Hidden performance cost: `setColormap` triggers `calMinMax`

Niivue’s `NVImage.colormap` setter calls `IntensityCalibration.calMinMax(...)` (even if the colormap has explicit min/max). This includes a full image scan to find raw min/max and can be expensive for large volumes.

**Implication:** “apply adaptive preset” may inadvertently add a second heavy scan even though the adaptive engine already scanned the data.

**Recommendation options:**
1. Prefer existing Niivue CT colormaps (`ct_soft_tissue`, `ct_artery`, `ct_kidneys`, `ct_bones`, etc.) and only adjust `cal_min/cal_max` to avoid frequent colormap resets.
2. If custom colormaps are required, minimize colormap changes and treat them as “rare events” (e.g., only when phase changes, not on every load).
3. If you need maximal speed, consider an upstream Niivue optimization: short-circuit `calMinMax` early when colormap min/max are explicitly provided (but this is a library change).

#### Factual mismatch in docs’ `ct_kidneys` interpretation

Upstream Niivue colormap file:
- `/Users/leandroalmeida/niivue/packages/niivue/src/cmaps/ct_kidneys.json` → `min: 114`, `max: 302`, `I: [0,103,255]`

Therefore “index 0” corresponds to HU≈114 under the usual LUT mapping, not “0 HU”. The docs’ prose should be corrected to avoid incorrect clinical reasoning built on colormap semantics.

---

## 5) Swift + WebKit Bridge Audit (Correctness, Concurrency, API Use)

### 5.1 Swift bridge patterns in this repo are strong

`NiiVue/NiiVue/Web/WebViewManager.swift` already demonstrates:
- weak message handler proxy to avoid retain cycles
- `@MainActor` isolation for UI-facing state and WebKit calls
- safe quoting via `JavaScriptQuote`
- asynchronous JS evaluation using modern `WKWebView` APIs
- correct use of `callAsyncJavaScript` for Promise-returning JS

These are aligned with Apple docs:
- `WKScriptMessageHandler` and `WKURLSchemeHandler` are `@MainActor` protocols in the official docs.
- `evaluateJavaScript` completion runs on the main thread.

### 5.2 Documented Swift service (`CTPresetService`) does not match repo reality

In the guide, the service calls:
- `try await webViewManager.evaluator.evaluateCommand(...)`

But in this repo:
- `WebViewManager.evaluator` is `private`.

**Recommendation:** either:
- keep CT preset methods **inside** `WebViewManager` (consistent with existing API surface), or
- add a controlled internal method on `WebViewManager` (e.g., `evaluateCommand(_:)`) rather than exposing the evaluator instance.

### 5.3 Recommendation: prefer typed request/response when you need results

Applying a preset is “fire and forget”, but the UI also wants:
- detected phase
- confidence
- chosen window values

Preferred patterns:
1. JS → Swift push: add a message handler (e.g., `ctPresetAnalysis`) and have JS post `{ phase, confidence, windowWidth, windowLevel }` after computation.
2. Swift → JS request/response: use `WKScriptMessageHandlerWithReply`, or `callAsyncJavaScript` to return JSON payloads.

This avoids brittle “evaluate a JS string and parse logs” workflows.

---

## 6) UX / Accessibility Audit (SwiftUI Layer)

The documentation’s SwiftUI sketch is directionally good (a sheet with presets, an auto-apply toggle, manual apply button), but it is not integrated with the current UI architecture and misses several practical details:

### Missing/unclear UX contracts

1. **When is auto-apply evaluated?**
   - Recommend: only on `volumeLoaded` *and* when volume modality indicates CT (if available), or when user explicitly enables “Auto-apply”.
2. **What happens on failure?**
   - Need clear non-blocking UX: show a lightweight banner/toast, keep manual controls available, revert to last-known-good.
3. **How does the user learn what changed?**
   - Provide immediate feedback: updated WW/WL overlay, detected phase label, and a “Reset to previous” option.

### Accessibility

The docs mention accessibility identifiers (good), but the feature also needs:
- VoiceOver-friendly names (“Adaptive (Auto-detect phase)”, “Excretory (ureters)”, etc.)
- state announcements when phase/preset changes
- avoid color-only cues (colormap changes must not be the only indicator)

---

## 7) Testing & Validation Audit

The docs propose:
- TS unit tests (Vitest)
- Swift integration tests (XCTest)
- clinical validation on 25 volumes
- performance target <500ms

### Audit gaps

1. **No reproducible benchmark harness** is defined for WKWebView on-device. Chrome DevTools is useful, but the shipping environment is iOS WebKit. You need:
   - a deterministic JS benchmark function
   - an iOS XCTest performance test that triggers it via `WebViewManager.callAsyncString(...)`
2. **Clinical validation claims are presented as achieved** (“Expected” vs “Achieved” tables are mixed in tone).
3. **Dataset governance**: where is the dataset stored, what are its labels, what is the ground truth, what is the IRB/privacy posture?

### Recommendation: validation structure

- Phase detection validation must report:
  - confusion matrix per phase
  - thresholds sensitivity analysis
  - stratification by scanner protocol / dose / reconstruction kernel if possible
- Performance validation must report:
  - iOS device model, OS version
  - WebKit version (implicitly via iOS)
  - volume voxel count, datatype, number of frames, and whether histogram uses sampling

---

## 8) Security & Privacy Audit (Medical Imaging Context)

The design is inherently on-device (good), but the docs should explicitly require:

1. **No PHI in logs**: current JS→Swift logging bridge (`logToIOS`) must avoid printing:
   - DICOM metadata
   - file names containing PHI
   - URLs/paths that may encode identifiers
2. **Inspector gating**: `webView.isInspectable = true` is already guarded by `#if DEBUG` (good). Keep it strictly debug-only.
3. **Data lifetime policy**:
   - imported files stored under Application Support should have clear retention policy
   - session snapshots should not embed image bytes (the project already avoids that)

---

## 9) Brainstormed Implementation Approaches (Trade-offs)

### Option A — Pure JS adaptive engine (closest to docs)

**Idea:** compute histogram/phase/window/colormap entirely in the React/Niivue layer; Swift triggers it via `window.*` bridge methods.

**Pros**
- minimal iOS-native complexity
- best reuse of Niivue volume representation
- easy iteration on visualization rules

**Cons**
- performance depends on WebKit JS speed and memory
- bridging “results” back to Swift must be designed (message handler)
- risk of duplicated work with Niivue `calMinMax` on colormap changes

**When recommended**
- fastest path to a working feature; acceptable if measured performance is good enough.

### Option B — Hybrid: Swift computes histogram features, JS applies visualization

**Idea:** compute histogram/phase/window in Swift (potentially using Accelerate) from the local file before/while JS loads; then call JS only to apply `cal_min/cal_max` and choose colormap.

**Pros**
- Swift performance + better profiling and unit testing
- avoids heavy JS scans
- easier to enforce privacy rules (no PHI logs in JS)

**Cons**
- duplication of decoding/interpretation (especially for DICOM series)
- risk of mismatch between Swift preprocessing and Niivue’s final volume data

**When recommended**
- only if JS performance is unacceptable, or if you already have robust native DICOM pipelines.

### Option C — Native Metal volume rendering + native adaptive logic

**Idea:** move rendering out of WebKit entirely and implement 3D CT rendering + adaptive presets natively.

**Pros**
- maximal performance and native integration
- full control over transfer functions, sampling, and UI

**Cons**
- very large scope; effectively replaces Niivue WebGL viewer
- high maintenance cost and feature parity risk

**When recommended**
- only if Niivue-in-WebKit becomes a hard blocker for product requirements.

**Recommendation (today):** Option A, but with the corrections and guardrails in §11.

---

## 10) Apple Documentation Grounding (Cupertino MCP)

Key WebKit facts were verified against Apple documentation (URIs via Cupertino):

1. `WKScriptMessageHandler` (how JS sends messages to native):  
   - URI: `apple-docs://webkit/documentation_webkit_wkscriptmessagehandler`  
   - Notable: JS calls `window.webkit.messageHandlers.<name>.postMessage(<body>)`.
2. `WKURLSchemeHandler` (custom scheme resource loading):  
   - URI: `apple-docs://webkit/documentation_webkit_wkurlschemehandler`
3. `WKWebView.evaluateJavaScript(_:completionHandler:)` (main-thread completion, async overload exists):  
   - URI: `apple-docs://webkit/documentation_webkit_wkwebview_evaluatejavascript_completionhandler_c8154e7b`
4. `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)` (functionBody semantics, Promise handling, supported argument types):  
   - URI: `apple-docs://webkit/documentation_webkit_wkwebview_callasyncjavascript_arguments_in_contentworld_e56f98b7`
5. `WKContentWorld` (separating execution environments / avoiding script conflicts):  
   - URI: `apple-docs://webkit/documentation_webkit_wkcontentworld`

---

## 11) Actionable Recommendations (Prioritized)

### P0 — Documentation and correctness fixes

1. Re-label docs as a **design/spec** unless code truly exists in-repo at the referenced paths.
2. Fix the percentile sentinel logic in the documented histogram code.
3. Replace `nv.cmapper.addColormap(...)` with `nv.addColormap(...)` (or correct import usage).
4. Fix Swift service examples to match the repo’s actual access control (don’t access a `private` evaluator).
5. Remove or justify `calMin >= 0` clamp; align with CT HU and Niivue negative handling.

### P1 — Make the system testable and clinically auditable

1. Define an explicit JS→Swift reporting payload: `{ phase, confidence, reasoning, calMin, calMax, ww, wl }`.
2. Add a deterministic iOS benchmark harness (XCTest) that measures end-to-end apply time in WKWebView.
3. Replace “top 5 peaks only” logic with HU-band evidence checks or ROI sampling.

### P2 — Reduce scope and leverage Niivue’s existing CT assets

1. Consider using Niivue’s built-in CT colormaps (`ct_soft_tissue`, `ct_artery`, `ct_kidneys`, `ct_bones`) as phase presets before generating new colormaps.
2. If custom transfer functions are required, predefine a small set of phase colormaps rather than generating per-volume.

---

## 12) Appendix: Key Repo Paths Mentioned

- Docs suite:
  - `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md`
  - `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
  - `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`
  - `docs/CT_ADAPTIVE_ENGINE_INDEX.md`
- iOS bridge:
  - `NiiVue/NiiVue/Web/WebViewManager.swift`
  - `NiiVue/NiiVue/Web/JavaScriptEvaluating.swift`
  - `NiiVue/NiiVue/Web/WKWebView+JavaScriptEvaluating.swift`
  - `NiiVue/NiiVue/Web/JavaScriptQuote.swift`
  - `NiiVue/NiiVue/Web/NiivueURLSchemeHandler.swift`
- React bridge:
  - `NiiVue/React/src/App.tsx`
  - `NiiVue/React/src/bridge/iosMessaging.ts`
  - `NiiVue/React/src/bridge/volumeCommands.ts`
- Upstream Niivue references (outside this repo):
  - `/Users/leandroalmeida/niivue/packages/niivue/src/nvimage/IntensityCalibration.ts`
  - `/Users/leandroalmeida/niivue/packages/niivue/src/nvimage/ColormapManager.ts`
  - `/Users/leandroalmeida/niivue/packages/niivue/src/cmaps/ct_kidneys.json`
