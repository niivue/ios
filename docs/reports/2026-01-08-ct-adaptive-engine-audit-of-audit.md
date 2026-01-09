# CT Adaptive Engine — Audit-of-Audit Validation Report

**Date:** 2026-01-08  
**Updated:** 2026-01-09  
**Scope:** Validate claims in `08-01-26_GPT_ANALYSIS_REVIEW_CT_ADAPTIVE_ENGINE.md` against:
- This repo (`/Users/leandroalmeida/niivue-ios-foundation`)
- Upstream Niivue source (`/Users/leandroalmeida/niivue`)
- Apple WebKit documentation (via Cupertino MCP)

---

## 1) Summary

The major “P0” findings in `08-01-26_GPT_ANALYSIS_REVIEW_CT_ADAPTIVE_ENGINE.md` were validated at the time and have now been addressed in code + docs:

- **Previously missing “NEW” source files** have been implemented under `NiiVue/React/src/bridge/` and `NiiVue/NiiVue/Services/` (see §2).
- The documentation’s published **percentile logic** sentinel bug was corrected in docs and is implemented using safe sentinels in `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`.
- The documentation’s colormap registration path no longer relies on unstable internals (`nv.cmapper`); both docs and implementation use `nv.addColormap(...)` + `nv.setColormap(...)`.
- The Swift bridge no longer depends on accessing `WebViewManager`’s private evaluator: `CTPresetService` is parameterized over `JavaScriptEvaluating`, and `WebViewManager` owns the evaluator privately.

Additionally, several non-P0 inconsistencies were corrected (deployment target, `ct_kidneys` LUT semantics, performance/validation claims wording, and UX reporting contracts).

On-device verification is documented separately in `08_01_26_GPT_OnDevice_XCUITest_Report.md` (unit + UI tests on Leandro’s iPhone).

---

## 2) Repo Reality Check (niivue-ios-foundation)

Validated against the working tree:

- Present today (CT Adaptive Engine implementation + tests):
  - TypeScript:
    - `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
    - `NiiVue/React/src/bridge/ctUrinaryPresets.ts`
    - `NiiVue/React/src/bridge/ctAutoApply.ts`
    - `NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`
    - `NiiVue/React/src/bridge/ctUrinaryPresets.test.ts`
    - `NiiVue/React/src/bridge/ctAutoApply.test.ts`
    - `NiiVue/React/src/App.tsx` (binds window functions + hooks `nv.onImageLoaded`)
  - Swift:
    - `NiiVue/NiiVue/Services/CTPresetService.swift`
    - `NiiVue/NiiVue/Web/WebViewManager.swift` (injects `window.autoApplyCTPreset` + decodes `ctPresetAnalysis`)
    - `NiiVue/NiiVue/ContentView.swift` (CT Presets sheet + analysis display)
    - `NiiVue/NiiVueTests/CTPresetServiceTests.swift`
    - `NiiVue/NiiVueTests/WebViewManagerStateTests.swift`
    - `NiiVue/NiiVueUITests/NiiVueUITests.swift`

Doc suite language was updated to match the implemented reality (status, paths, file counts, and test commands).

---

## 3) Upstream Niivue Validation (niivue)

Validated against `/Users/leandroalmeida/niivue/packages/niivue`:

- **Custom colormap registration** is supported via the public `Niivue.addColormap(key:cmap)` API (instance method), not via `nv.cmapper`.
- **`nv.setColormap(...)` triggers a `calMinMax(...)` scan** through Niivue’s colormap manager, so colormap changes are “expensive” and should be minimized.
- **CT colormap semantics:** `ct_kidneys.json` has `min: 114`, `max: 302`. Index `0` corresponds to the LUT’s `min` (not “0 HU”).
- **Negative HU support exists** in Niivue (CT colormaps may have negative `min`, and the render pipeline supports negative calibration ranges).

---

## 4) Apple WebKit Grounding (Cupertino MCP)

Validated key WebKit behaviors used by this repo’s bridge layer:

- `WKScriptMessageHandler` is `@MainActor` and JS calls into native via `window.webkit.messageHandlers.<name>.postMessage(<body>)`.  
  URI: `apple-docs://webkit/documentation_webkit_wkscriptmessagehandler`
- `WKWebView.evaluateJavaScript(_:completionHandler:)` completion runs on the app’s main thread.  
  URI: `apple-docs://webkit/documentation_webkit_wkwebview_evaluatejavascript_completionhandler_c8154e7b`
- `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)` expects a *function body* (not a wrapped callable) and awaits Promise-like results.  
  URI: `apple-docs://webkit/documentation_webkit_wkwebview_callasyncjavascript_arguments_in_contentworld_e56f98b7`
- `WKContentWorld` provides script execution scoping.  
  URI: `apple-docs://webkit/documentation_webkit_wkcontentworld`
- `WKUserScript` is the supported way to inject JS into pages and can be scoped to a content world (`init(source:injectionTime:forMainFrameOnly:in:)`).  
  URI: `apple-docs://webkit/documentation_webkit_wkuserscript`
- `WKUserContentController.addUserScript(_:)` injects the user script into page content (and is `@MainActor`).  
  URI: `apple-docs://webkit/documentation_webkit_wkusercontentcontroller_adduserscript_ff2ccbff`

---

## 5) Documentation Fixes Applied

The following files were updated to resolve validated conflicts and remove unverified claims:

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md`
  - Fixed percentile sentinel logic and constant-volume edge case in the documented `HistogramAnalyzer.compute`.
  - Removed invalid “non-negative `calMin`” clamp and replaced with optional CT HU-domain clamping.
  - Replaced `nv.cmapper` usage with `nv.addColormap(...)` and documented colormap-change performance implications.
  - Updated Swift bridge/service examples to respect `WebViewManager` access control.
  - Corrected `ct_kidneys` LUT semantics and clarified phase/confidence + “Detected Phase” reporting contract.
  - Converted performance/accuracy language from “achieved” to “targets/TBD”.
- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
  - Reworded status/metrics as targets, removed `nv.cmapper` guidance, and updated profiling guidance to iOS WebKit.
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`
  - Updated colormap API references, removed hard-coded timing claims, and clarified the JS→Swift reporting requirement.
- `docs/CT_ADAPTIVE_ENGINE_INDEX.md`
  - Updated status/path/file-count references to match the implemented engine and refreshed section start lines/sizes.

---

## 6) Remaining Validation Work (Not Claimed as Complete)

- Define a governed CTU dataset (labels + ground truth), then report a confusion matrix and thresholds sensitivity analysis.
- Build an on-device benchmark harness (XCTest driving WKWebView) for end-to-end measurement.
- Decide whether the product needs per-volume *generated* colormaps or whether built-in CT colormaps + adaptive `cal_min`/`cal_max` are sufficient.
