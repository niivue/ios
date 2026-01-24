# 08-01-26 GPT Plan Execution Report — CT Adaptive Engine Doc Suite

**Plan Executed:** `docs/plans/2026-01-08-ct-adaptive-engine-docs-alignment-plan.md`  
**Execution Date:** 2026-01-08  
**Updated:** 2026-01-09  
**Scope:** Documentation-only alignment across the 4-file CT Adaptive Engine doc suite  

---

## Progress Summary

- Completed Tasks: 1–12
- In Progress: —
- Note on commits: The plan includes `git commit` steps per task; those commits were intentionally not created because the session instructions say not to `git commit` unless explicitly requested.

---

## Update (2026-01-09) — CT Adaptive Engine is now implemented

Since this report was first authored (2026-01-08), the CT Adaptive Engine described by the doc suite has been implemented end-to-end in this repo and validated on Leandro’s iPhone via on-device XCTest/XCUITest. As a result:

- The “MISSING (planned/proposed files not present yet)” list in **Task 3** is historical and no longer true (those files now exist in the repo).
- The doc suite status has been updated to **Implemented** (Document Version **1.2**) and the file-by-file mapping is now a 7-file implemented integration (`ctAutoApply.ts` added for Option B).
- Latest on-device verification evidence (2026-01-09):
  - Unit tests: **87** executed, **0** failures — xcresult: `/tmp/NiiVueDerivedData-NiiVueTests-Device-20260109/Logs/Test/Test-NiiVue-2026.01.09_00-01-52--0300.xcresult`
  - UI tests: **30** executed, **1** skipped, **0** failures — xcresult: `/tmp/NiiVueDerivedData-NiiVueUITests-Device-20260109b/Logs/Test/Test-NiiVue-2026.01.09_00-08-02--0300.xcresult`

Full commands + device fixture setup are documented in `08_01_26_GPT_OnDevice_XCUITest_Report.md`.

---

## Task 1 — Capture the “ground truth” version pins

### What I did

1. Captured the current repo commit SHA:
   - Ran: `git rev-parse HEAD`
   - Result: `2c8ffcd6c2e3f0b143e5f610ce031ef6235262d7`
2. Captured the upstream Niivue repo commit SHA:
   - Ran: `git -C /Users/leandroalmeida/niivue rev-parse HEAD`
   - Result: `f0c010293b01cfb162e2b9e959c27717b07686f1`
3. Added a consistent “Last Verified / Validated Against / Upstream API Reference” metadata block near the top of each of the 4 documentation files.

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (added validation metadata block under the header status lines)
- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (added validation metadata block under the header status lines)
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (added a small header metadata block indicating it is derived + validation pins)
- `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (added validation metadata block under the header date/status lines)

### Why this matters

This makes the doc suite auditable: every API claim can now be tied to a specific upstream Niivue snapshot and a specific state of this repo.

---

## Task 2 — Re-assert doc roles + “spec vs implemented” truthfulness

### What I did

1. Explicitly documented which file is canonical and which files are derived:
   - In the implementation guide, clarified that it is the canonical spec.
   - In the index, added an explicit “Canonical source” line and a short list of derived views that must not contradict the guide.
   - In the summary, added an explicit “Canonical Spec” pointer back to the guide (and marked the summary as derived).
2. Verified that no legacy “file creation” claims remain phrased as already-done work:
   - Ran: `rg -n "NEW file|created file|added file" docs/ct-urinary-tract-adaptive-engine-implementation-*.md docs/CT_ADAPTIVE_ENGINE_INDEX.md`
   - Result: no matches.

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (added canonical-spec bullet to Section `1.0 Implementation Status & Verification`)
- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (added “Canonical Spec” line in the header block)
- `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (added canonical vs derived contract under “Document Suite Overview”)

### Why this matters

The suite contains multiple documents with overlapping content. Making the “source of truth” explicit prevents accidental contradictions (especially when future edits land only in the summary or visual overview).

---

## Task 3 — Verify all referenced file paths exist (or are clearly marked planned)

### What I checked

1. Extracted all absolute paths referenced across the 4-file doc suite:
   - Ran:  
     `rg -n "/Users/leandroalmeida/niivue-ios-foundation/[^\") ]+" docs/ct-urinary-tract-adaptive-engine-implementation-*.md docs/CT_ADAPTIVE_ENGINE_INDEX.md`
2. Verified existence of each referenced path with `test -e`.

### Findings (existence check)

**OK (exists):**

- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVue/`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVue/ContentView.swift`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVue/Web/WebViewManager.swift`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/App.tsx`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/bridge/`
- `/Users/leandroalmeida/niivue-ios-foundation/docs/`
- `/Users/leandroalmeida/niivue-ios-foundation/docs/ct-urinary-tract-adaptive-engine-implementation-guide.md`

**MISSING (planned/proposed files not present yet):** *(historical — true on 2026-01-08; resolved by 2026-01-09 implementation)*

- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVue/Services/CTPresetService.swift`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/CTPresetServiceTests.swift`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
- `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/bridge/ctUrinaryPresets.ts`

### What I fixed in the docs

1. Labeled missing referenced paths explicitly as planned:
   - Updated headings in Section 5 and test file references in Section 7 to say “(planned new file)” where the file does not exist.
2. Removed an invalid “continued in next response / would you like me to continue” block that was mistakenly embedded in the middle of the file-by-file guide:
   - This content is not part of the specification and would confuse implementers; it also risked breaking Markdown structure around code fences.

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (marked planned file paths + removed invalid embedded assistant chatter)

---

## Task 4 — Apple/WebKit bridging section — Cupertino-grounded verification sweep

### What I checked (Cupertino)

Re-verified WebKit behaviors and signatures directly against Apple’s documentation (via Cupertino MCP):

- `WKWebView.evaluateJavaScript(_:completionHandler:)`
  - URI read: `apple-docs://webkit/documentation_webkit_wkwebview_evaluatejavascript_completionhandler_c8154e7b`
  - Verified claim used in docs: “The completion handler always runs on the app’s main thread.”
- `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)`
  - URI read: `apple-docs://webkit/documentation_webkit_wkwebview_callasyncjavascript_arguments_in_contentworld_e56f98b7`
  - Verified claims used in docs:
    - `functionBody` must be a function body (not a `function(){}` wrapper)
    - WebKit awaits Promise-like results (objects with a callable `then`)
- `WKScriptMessageHandler`
  - URI read: `apple-docs://webkit/documentation_webkit_wkscriptmessagehandler`
  - Verified claim used in docs: JavaScript posts messages via `window.webkit.messageHandlers.<name>.postMessage(<body>)`
- `WKContentWorld`
  - URI read: `apple-docs://webkit/documentation_webkit_wkcontentworld`
  - Verified claim used in docs: content worlds provide a scoped namespace for script execution (variables don’t persist across navigation).

### What I fixed in the docs

1. Ensured the Implementation Guide references section includes the Cupertino URI for `WKScriptMessageHandler` (matching the existing URI entries already present for `evaluateJavaScript`, `callAsyncJavaScript`, and `WKContentWorld`).
2. Ensured summary references include a concrete Apple docs URL + Cupertino URI for `WKScriptMessageHandler` so the summary remains traceable to an official source.
3. Sanity-checked Swift examples for access control correctness (no direct access to `WebViewManager`’s private evaluator from other types); examples route through forwarding helpers (`evaluateCommand`, `evaluateString`).

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (added URI: `apple-docs://webkit/documentation_webkit_wkscriptmessagehandler`)
- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (added URL + URI for the WebKit bridge reference)

---

## Task 5 — Niivue API correctness sweep (upstream code-grounded)

### What I checked (upstream `/Users/leandroalmeida/niivue`)

Verified that the public API surface includes the colormap APIs referenced by the docs:

- Ran: `rg -n "addColormap\\(|setColormap\\(" /Users/leandroalmeida/niivue/packages/niivue/src/niivue/index.ts`
- Confirmed:
  - `addColormap(key: string, cmap: ColorMap): void` exists (public method)
  - `setColormap(id: string, colormap: string): void` exists (public method)

Also verified the doc suite does not reference unstable internals like `nv.cmapper`:

- Ran: `rg -n "nv\\.cmapper|\\(nv as any\\)\\.cmapper" docs/...`
- Result: no matches.

### Doc impact

No doc edits were required for Task 5 (the suite already uses `nv.addColormap(...)` and `nv.setColormap(...)` exclusively).

---

## Task 6 — `ct_kidneys` LUT semantics + HU mapping consistency

### What I checked (upstream `/Users/leandroalmeida/niivue`)

1. Verified the actual `ct_kidneys` definition:
   - Ran: `cat /Users/leandroalmeida/niivue/packages/niivue/src/cmaps/ct_kidneys.json`
   - Confirmed:
     - `min = 114`, `max = 302`
     - Control points: `I = [0, 103, 255]` with corresponding `R/G/B/A` values
2. Verified how Niivue interprets `(R,G,B,A,I)`:
   - Checked: `/Users/leandroalmeida/niivue/packages/niivue/src/colortables.ts`
   - Confirmed: Niivue linearly interpolates control points into a dense 256-entry LUT (with indices expected to start at 0 and end at 255).

### What I fixed in the docs

Added explicit mapping clarity (without changing clinical intent):

- In the implementation guide:
  - Added the explicit index-to-HU mapping formula: `hu = min + (I / 255) * (max - min)`
  - Clarified that `(R,G,B,A,I)` are control points and Niivue interpolates them into a dense LUT.
- In the visual overview:
  - Added a short note under the HU reference card describing the same mapping formula and what it implies for `ct_kidneys` (e.g., `I=103` ≈ 190 HU for `min=114,max=302`).

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (added mapping formula + interpolation note in Section `2.4 Existing CT_Kidneys Preset Analysis`)
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (added mapping formula note under “Card 2”)

---

## Next Batch (Tasks 7–9)

## Task 7 — Algorithm section integrity (Histogram → Phase → Window → Colormap)

### What I checked

Reviewed the algorithm specification sections in the implementation guide (Sections 4.1–4.4) and the “reference implementation” code blocks in Section 5 for:

- Percentile sentinel correctness (avoid “value equals globalMin means unset”)
- Constant-volume edge case handling (`globalMin == globalMax`)
- Peak selection robustness (ensure clinically-relevant HU-band peaks aren’t dropped due to low volume)
- Windowing constraints (no invalid windows, no hard clamp to `>= 0` for CT)
- Colormap generation semantics (alpha normalized `[0,1]` → `[0,255]`) and determinism

### What I fixed

1. **Window constraints bug fix (spec + reference implementation):**
   - Found a “last resort fallback” that set `calMin = 0; calMax = 1` if constraints produced an invalid window. This is not a meaningful CT fallback (it yields an almost zero-width window).
   - Replaced it with a safer cascade:
     - Clamp to CT domain (`-1024..3071`)
     - Enforce minimum width (50 HU) while staying inside the domain
     - If still invalid, fall back to histogram-derived `[globalMin, globalMax]` within CT domain
     - Final last-resort: `0..50` (non-zero width, avoids crashes/NaNs)
2. **Determinism explicitly documented for colormap generation:**
   - Added a note that colormap generation is deterministic given the same `PhaseResult` + `WindowResult`.

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (updated window constraint logic in both the algorithm spec and the reference TypeScript implementation; added determinism note for colormap generation)

---

## Task 8 — Integration workflow + JS→Swift reporting contract

### What I fixed/added

1. **Made the reporting payload explicit in the implementation guide:**
   - Added a concrete JSON example for the `updateUI` payload with `type: "ctPresetAnalysis"`.
   - Added threading guidance (`WKScriptMessageHandler` callbacks are `@MainActor`) and error-handling guidance (schema validation, ignore unknown types, no PHI logging).
2. **Aligned diagrams + index references on the same identifier:**
   - Updated the visual overview to use the same `type: "ctPresetAnalysis"` naming in the “Detected Phase” note and in the data-flow diagram (added Step 6 for reporting).
   - Updated the index to call out the JS→Swift contract as a key code section and a critical decision point.

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (expanded Section `6.5 JS → Swift Reporting`)
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (aligned terminology; added explicit reporting step in data flow)
- `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (added a “JS → Swift Reporting Contract” key section + decision point)

---

## Task 9 — Security, privacy, and operational constraints (medical imaging)

### What I fixed/added

1. **Clarified privacy requirements and defaults in the guide:**
   - Added “debug logging is opt-in” guidance (DEBUG builds and/or explicit developer toggle).
   - Made persistence expectations explicit: default to “no persistence” for analysis outputs; if persisting, store only derived metadata and define purge policy.
   - Added a compact WebView hardening checklist (allowlist handler names, validate schemas, prefer `WKContentWorld`, avoid untrusted `evaluateJavaScript`).
2. **Updated index risk assessment to include privacy/WebView risks:**
   - Added explicit risks for PHI leakage (logs/bridge) and WebView message injection, with mitigations aligned to the guide.

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (expanded Section `6.4 Security & Privacy`)
- `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (added privacy/WebView rows in Risk Assessment)

---

## Next Batch (Tasks 10–12)

## Task 10 — Summary + visual overview parity with the guide

### What I checked

- Confirmed the summary does not introduce facts that contradict the canonical guide.
- Verified the documented test commands match the actual repo tooling:
  - `npm test` exists in `NiiVue/React/package.json`
  - `xcodebuild test -scheme NiiVue ...` is valid (`xcodebuild -list` shows scheme `NiiVue`)
- Audited the visual overview for any “implemented/measured” claims that are inconsistent with the guide’s “targets until benchmarked” stance.

### What I fixed

- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
  - Added an explicit note that “NEW” files are planned/proposed and not present yet.
  - Added a small comment clarifying the simulator name in the `xcodebuild` example may need adjustment.
  - Updated the guide size reference in “Next Steps” to match the current guide size/line count.
  - Added a small revision history table and bumped to version `1.1` (same date).
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`
  - Replaced an overlong 2-week/12-day timeline with a 4-phase (7-day) timeline consistent with the summary and guide.
  - Removed “Achieved” performance numbers (replaced with `TBD`) to avoid false claims.
  - Added a note that “NEW” paths are planned/proposed.
  - Updated the guide size reference in the file tree to match the current guide size.
  - Added a small revision history table and bumped to version `1.1` (same date).

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`

---

## Task 11 — Index quality pass (navigation, matrices, and “getting started”)

### What I fixed

- Updated the index to reflect current reality:
  - Correct file sizes and line counts (guide/summary/visual/index + design doc).
  - Replaced shorthand filenames (`implementation-summary.md`, etc.) with full doc paths used in this repo.
  - Updated the section guide to use actual “Starts at line …” values (and removed the non-existent “Section 10” reference).
  - Removed stale/incorrect line ranges in “Key Code Sections to Review” and replaced with stable “Where” pointers.
  - Synced the implementation timeline summary to the same 4-phase (7-day) structure.
  - Clarified “NEW (planned)” in file location trees.
  - Updated the index’s own version history table to include `1.1`.

### Files modified

- `docs/CT_ADAPTIVE_ENGINE_INDEX.md`

---

## Task 12 — Verification sweep (grep-based “doc invariants”)

### Verification run

Ran the invariant grep suite from the plan:

```bash
rg -n "nv\\.cmapper|\\(nv as any\\)\\.cmapper|Math\\.max\\(calMin, 0\\)|webViewManager\\.evaluator" \
  docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md \
  docs/CT_ADAPTIVE_ENGINE_INDEX.md
```

Result: no matches.

### Consistency fixes applied during verification

- Added/updated revision history across the doc suite on `2026-01-08` (later updates bumped the suite to version `1.2`).
- Fixed the implementation guide table-of-contents numbering so it matches the actual section structure.

### Files modified

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md`
- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`
- `docs/CT_ADAPTIVE_ENGINE_INDEX.md`

---

## Plan Status

All 12 tasks in `docs/plans/2026-01-08-ct-adaptive-engine-docs-alignment-plan.md` have been executed.

---

# Addendum (2026-01-09) — CT Adaptive Engine Implementation (TDD + On-Device)

**Plan Executed:** `docs/plans/2026-01-08-ct-adaptive-engine-implementation-plan.md`  
**Execution Date:** 2026-01-09  
**Scope:** Implement the CT Adaptive Engine end-to-end (TypeScript engine + Swift bridge + SwiftUI controls), using Option **B** auto-apply (JS `nv.onImageLoaded` gated by `window.autoApplyCTPreset` configured by Swift), and validate via on-device tests.

> Note: The plan’s `xcodebuild` examples use the simulator; those steps were intentionally adapted to use **Leandro’s iPhone** only (per session requirement).

## Batch 1 (Tasks 1–3) — Histogram foundation (TDD)

### Task 1 — TypeScript RED tests for `HistogramAnalyzer.compute`

- Created: `NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`
- Covered:
  - NIfTI scaling (`hdr.scl_slope`, `hdr.scl_inter`)
  - Percentile extraction via histogram cumulative sum
  - Constant-volume edge case (`globalMin == globalMax`) returns finite values

### Task 2 — TypeScript GREEN `HistogramAnalyzer`

- Created: `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
- Implemented: `HistogramAnalyzer.compute(...)` using TypedArray loops and safe sentinels (no “percentile equals globalMin means unset” bug).

### Task 3 — TypeScript RED tests for phase detection + window calculation

- Extended: `NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`
- Added coverage for:
  - `PhaseDetector.classify(...)` phase rules
  - `AdaptiveWindowCalculator.compute(...)` CT HU-domain clamp + minimum width + safe fallback

---

## Batch 2 (Tasks 4–6) — Phase/window + colormap + apply pipeline (TDD)

### Task 4 — TypeScript GREEN `PhaseDetector` + `AdaptiveWindowCalculator`

- Implemented in: `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
- Key constraints:
  - No global clamp of HU to `>= 0` (CT supports negative HU)
  - Optional explicit CT-domain clamp `[-1024, 3071]`
  - Minimum window width enforcement (default 50 HU)

### Task 5 — TypeScript RED tests for colormap generation + apply pipeline

- Extended: `NiiVue/React/src/bridge/ctAdaptiveEngine.test.ts`
- Added coverage for:
  - 256-entry RGBA generation
  - Engine apply pipeline registers custom colormap and applies cal_min/cal_max + `nv.setColormap(...)`

### Task 6 — TypeScript GREEN `ColormapGenerator` + `CTAdaptiveEngine`

- Implemented in: `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
- Uses stable public Niivue APIs:
  - `nv.addColormap(...)`
  - `nv.setColormap(...)`

---

## Batch 3 (Tasks 7–9) — Preset library + Option B auto-apply gate (TDD)

### Task 7 — TypeScript RED tests for preset library

- Created: `NiiVue/React/src/bridge/ctUrinaryPresets.test.ts`
- Validates stable preset list + routing between fixed presets and adaptive preset.

### Task 8 — TypeScript GREEN preset library

- Created: `NiiVue/React/src/bridge/ctUrinaryPresets.ts`
- Adds iOS WebView reporting:
  - After applying the adaptive preset, posts `updateUI` with `{ type: "ctPresetAnalysis", payload: ... }` when running inside iOS `WKWebView`.

### Task 9 — TypeScript RED test for auto-apply gating

- Created: `NiiVue/React/src/bridge/ctAutoApply.test.ts`
- Validates:
  - If `window.autoApplyCTPreset === true`, the handler applies the adaptive preset on image load.
  - Otherwise it does nothing.

---

## Batch 4 (Tasks 10–12) — React wiring + Swift bridge service (TDD)

### Task 10 — TypeScript GREEN Option B integration + `window.*` API

- Created: `NiiVue/React/src/bridge/ctAutoApply.ts`
- Modified: `NiiVue/React/src/App.tsx`
- Implemented:
  - `nv.onImageLoaded` calls `maybeAutoApplyAdaptiveCTUrinaryPreset(0)`
  - Exposed stable `window.*` API:
    - `window.listCTUrinaryPresets`
    - `window.applyCTUrinaryPreset`
    - `window.applyAdaptiveCTUrinaryPreset`

### Task 11 — Swift RED tests for `CTPresetService`

- Created: `NiiVue/NiiVueTests/CTPresetServiceTests.swift`
- Verifies:
  - Generated JS strings are safe/quoted correctly
  - `listPresets` parsing is correct

### Task 12 — Swift GREEN `CTPresetService` + WebViewManager forwarding

- Created: `NiiVue/NiiVue/Services/CTPresetService.swift`
- Modified: `NiiVue/NiiVue/Web/WebViewManager.swift`
- Key design:
  - `CTPresetService` depends on a protocol (`JavaScriptEvaluating`) instead of reaching into `WebViewManager` internals.

---

## Batch 5 (Tasks 13–15) — Swift injection + SwiftUI UI + analysis decode

### Task 13 — Inject `window.autoApplyCTPreset` from Swift (best practice)

- Modified: `NiiVue/NiiVue/Web/WebViewManager.swift`
- Modified: `NiiVue/NiiVue/ContentView.swift`
- Implemented:
  - Injects a default `window.autoApplyCTPreset` via `WKUserScript` at `.atDocumentStart` in the `.page` content world.
  - Persists toggle via `@AppStorage("autoApplyCTPreset")` and pushes changes into JS.

### Task 14 — SwiftUI CT Presets UI (toggle + picker + apply)

- Modified: `NiiVue/NiiVue/ContentView.swift`
- Added:
  - CT Presets sheet entry point
  - Auto-apply toggle
  - Preset picker + Apply button
  - Analysis display (phase) with accessibility id `niivue.ctPresetAnalysis.phase`

### Task 15 — Decode JS→Swift `ctPresetAnalysis` payload

- Modified: `NiiVue/NiiVue/Web/WebViewManager.swift`
- Implemented:
  - Decode `updateUI` messages with `type == "ctPresetAnalysis"`
  - Store latest analysis in `WebViewManager.lastCTPresetAnalysis` for UI display

---

## Task 16 — Verification (on-device)

### TypeScript tests (host)

- ✅ PASS
- Command: `cd NiiVue/React && npm test`
- Result: 6 test files, 39 tests, 0 failures

### Device fixture setup

Some UI tests use a pre-seeded KiTS23 DICOM series inside the app container:

- App: `com.niivue.mobile`
- Destination on device: `Documents/dicom-fixtures/VOLUME_MED_E_ABD_3`

Copied via:

```bash
xcrun devicectl device copy to \
  --device 00008140-001664420413C01C \
  --source /Users/leandroalmeida/Downloads/kits23-v1/src/kits23/workspace-kits23/TC_DA_PELVE/VOLUME_MED_E_ABD_3 \
  --domain-type appDataContainer \
  --domain-identifier com.niivue.mobile \
  --destination Documents/dicom-fixtures/VOLUME_MED_E_ABD_3 \
  --remove-existing-content true
```

### Swift unit tests (on-device)

- ✅ **TEST SUCCEEDED**
- **Executed:** 87 tests
- **Failures:** 0
- xcresult: `/tmp/NiiVueDerivedData-NiiVueTests-Device-20260109/Logs/Test/Test-NiiVue-2026.01.09_00-01-52--0300.xcresult`

### UI tests (on-device)

- ✅ **TEST SUCCEEDED**
- **Executed:** 30 tests
- **Skipped:** 1
- **Failures:** 0
- xcresult: `/tmp/NiiVueDerivedData-NiiVueUITests-Device-20260109b/Logs/Test/Test-NiiVue-2026.01.09_00-08-02--0300.xcresult`

### Notes

- All physical-device test runs used `-collect-test-diagnostics never` to avoid post-run diagnostics prompts.
- A single earlier run failed with `Timed out while enabling automation mode.`; a retry succeeded (running the smoke UI test first helped).
