# CT Adaptive Engine Documentation Alignment Plan (4-file suite)

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Keep the CT Adaptive Engine doc suite accurate, internally consistent, and grounded in (1) the real `niivue` codebase and (2) official Apple/WebKit documentation (via Cupertino).

**Architecture:** Treat `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` as the source-of-truth; keep the other three docs as derived “views” (summary, visual, index) that must never contradict the guide. Enforce consistency via a repeatable verification checklist (grep-based + spot-checks of upstream code + Cupertino URIs).

**Tech Stack:** Markdown, `rg`, git, upstream `niivue` source at `/Users/leandroalmeida/niivue`, Cupertino MCP (`mcp__cupertino__search`, `mcp__cupertino__read_document`).

---

## Scope (files covered)

- `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md`
- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`
- `docs/CT_ADAPTIVE_ENGINE_INDEX.md`

---

## Task 1: Capture the “ground truth” version pins

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (revision history + status block)
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (revision history + status block)
- Modify: `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (revision history + status block)
- Modify: `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (version history)

**Step 1: Record current repo commit**

Run: `git rev-parse HEAD`
Expected: prints a commit SHA.

**Step 2: Record upstream niivue commit**

Run: `git -C /Users/leandroalmeida/niivue rev-parse HEAD`
Expected: prints a commit SHA.

**Step 3: Update each doc’s “Validated Against” / “Last Verified” metadata**

Add/update a small block near the top of each doc (or in revision history) using this template:

```md
**Last Verified:** 2026-01-08
**Validated Against:** `niivue-ios-foundation` @ <SHA>
**Upstream API Reference:** `/Users/leandroalmeida/niivue` @ <SHA>
```

**Step 4: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md \
  docs/CT_ADAPTIVE_ENGINE_INDEX.md
git commit -m "docs: pin doc suite validation commits"
```

---

## Task 2: Re-assert doc roles + “spec vs implemented” truthfulness

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (Section `1.0 Implementation Status & Verification`)
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (Key Takeaways + Scope)
- Modify: `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (Document Suite Overview + Comparison Matrix)

**Step 1: Define the contract (source vs derived)**

Ensure the index explicitly states:
- The guide is canonical.
- Summary/visual/index must not introduce new facts not present in the guide.

**Step 2: Mark all “planned file paths” as planned (not existing)**

For any referenced path that does not exist in this repo, ensure wording is “proposed/planned” (not “implemented/added”).

**Step 3: Verify no “NEW file created” claims remain**

Run:
```bash
rg -n "NEW file|created file|added file" docs/ct-urinary-tract-adaptive-engine-implementation-*.md docs/CT_ADAPTIVE_ENGINE_INDEX.md
```
Expected: either no matches, or matches are explicitly labeled as “planned”.

**Step 4: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/CT_ADAPTIVE_ENGINE_INDEX.md
git commit -m "docs: clarify spec vs implementation status"
```

---

## Task 3: Verify all referenced file paths exist (or are clearly marked planned)

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (Section 5 file-by-file)
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (File Locations)
- Modify: `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (File Structure Overview)
- Modify: `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (File Locations Summary)

**Step 1: Extract all absolute paths from the doc suite**

Run:
```bash
rg -n "/Users/leandroalmeida/niivue-ios-foundation/[^\") ]+" docs/ct-urinary-tract-adaptive-engine-implementation-*.md docs/CT_ADAPTIVE_ENGINE_INDEX.md
```
Expected: a list of referenced absolute paths.

**Step 2: For each referenced path, verify existence**

Run (repeat for each path):
```bash
test -e "<path>" && echo "OK: <path>" || echo "MISSING: <path>"
```

**Step 3: Fix mismatches**

- If missing: label as “planned/proposed” and (optionally) move it to a “Planned Files” subsection.
- If present but renamed: update the doc with the real path.

**Step 4: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md \
  docs/CT_ADAPTIVE_ENGINE_INDEX.md
git commit -m "docs: reconcile referenced file paths"
```

---

## Task 4: Apple/WebKit bridging section — Cupertino-grounded verification sweep

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (Swift/WebKit sections + References)
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (Testing Commands + Notes)

**Step 1: Re-verify each Apple API used in docs (via Cupertino)**

For each API/behavior claim, do:
1) `mcp__cupertino__search(query: "<API>", source: "apple-docs")`
2) `mcp__cupertino__read_document(uri: "<result_uri>")`

Minimum set to verify (if referenced anywhere in the suite):
- `WKWebView.evaluateJavaScript(_:completionHandler:)`
- `WKWebView.callAsyncJavaScript(_:arguments:in:contentWorld:)`
- `WKScriptMessageHandler`
- `WKContentWorld`
- `WKScriptMessageHandlerWithReply` (only if used)

**Step 2: Ensure docs embed the Cupertino URIs**

In the implementation guide References, include the `apple-docs://...` URIs next to each cited API.

**Step 3: Ensure Swift examples compile with the real `WebViewManager`**

If `WebViewManager` has a `private` evaluator, ensure examples route calls through public methods or same-file extensions (do not show code that requires accessing `private` properties from other types).

**Step 4: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md
git commit -m "docs: re-ground WebKit guidance in Cupertino + real Swift access control"
```

---

## Task 5: Niivue API correctness sweep (upstream code-grounded)

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (TypeScript integration + colormap sections)
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (Code Highlights snippets)
- Modify: `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (Quick Reference Cards if they mention API names)

**Step 1: Verify Niivue colormap APIs in upstream**

Run:
```bash
rg -n "addColormap\\(|setColormap\\(" /Users/leandroalmeida/niivue/packages/niivue/src/niivue/index.ts
```
Expected: confirms public surface area and method naming.

**Step 2: Ensure docs use stable public APIs only**

Checklist:
- Use `nv.addColormap(...)`, not `nv.cmapper` or `(nv as any).cmapper`.
- Call out performance implications of `nv.setColormap(...)` if relevant (full recalibration scan).

**Step 3: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md
git commit -m "docs: align Niivue API references with upstream public surface"
```

---

## Task 6: `ct_kidneys` LUT semantics + HU mapping consistency

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (Section `2.4 Existing CT_Kidneys Preset Analysis`)
- Modify: `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (HU reference / any LUT card)

**Step 1: Read the upstream `ct_kidneys.json`**

Run:
```bash
cat /Users/leandroalmeida/niivue/packages/niivue/src/cmaps/ct_kidneys.json
```
Expected: shows `min`, `max`, and `R/G/B/A` arrays.

**Step 2: Ensure docs state index-to-HU mapping correctly**

In docs, ensure the mapping formula is correct and consistent:
- `hu = min + (i / 255) * (max - min)` for `i in 0...255`
- Alpha scaling uses `/255` when converting `A[i]` from 8-bit to normalized.

**Step 3: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md
git commit -m "docs: correct ct_kidneys HU/index mapping and alpha normalization"
```

---

## Task 7: Algorithm section integrity (Histogram → Phase → Window → Colormap)

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (Sections 4.1–4.4)
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (Code Highlights)
- Modify: `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (Decision Tree + Window Selection)

**Step 1: Histogram correctness checklist**

Verify and fix (if needed):
- Percentile computation uses a safe sentinel (don’t confuse “value equals globalMin” with “unset”).
- Constant-volume edge case: if `globalMin == globalMax`, return a safe trivial histogram + window fallback.
- Peak selection doesn’t discard clinically-relevant peaks due to low volume alone (consider HU-band candidates).

**Step 2: Windowing correctness checklist**

Verify and fix (if needed):
- Never clamp HU to `>= 0` globally (CT needs negative HU).
- If applying CT-domain clamps, do so explicitly and document it (e.g., `-1024..3071`).
- Enforce minimum window width (e.g., `>= 50 HU`) after clamping.

**Step 3: Colormap generation correctness checklist**

Verify and fix (if needed):
- Alpha curve is based on normalized `[0,1]` and respects LUT semantics.
- Document whether colormap generation is deterministic given the histogram summary inputs.

**Step 4: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md
git commit -m "docs: tighten algorithm specs and edge-case handling"
```

---

## Task 8: Integration workflow + JS→Swift reporting contract

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (Section 6: integration + reporting)
- Modify: `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (Data flow diagram)
- Modify: `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (Key Code Sections + Critical Decision Points)

**Step 1: Make the reporting payload explicit**

Ensure docs define:
- Message name (e.g., `updateUI`)
- Payload schema (include a JSON example)
- Threading expectations on Swift side (UI updates on `@MainActor`)
- Error handling expectations (invalid payload → ignore + log minimally, no PHI)

**Step 2: Align diagrams + index references**

If the guide uses `type: "ctPresetAnalysis"` (or similar), ensure the visual overview and index use the same identifier.

**Step 3: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md \
  docs/CT_ADAPTIVE_ENGINE_INDEX.md
git commit -m "docs: formalize JS→Swift reporting contract and align diagrams/index"
```

---

## Task 9: Security, privacy, and operational constraints (medical imaging)

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (Section 6.4)
- Modify: `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (Risk Assessment)

**Step 1: Add a “no PHI in logs” rule + retention policy**

Make sure the guide states:
- Never log PHI.
- Debug logging is opt-in and must redact identifiers.
- Clarify any local persistence expectations (or explicitly state “no persistence”).

**Step 2: Add a “WebView hardening” checklist**

Checklist should include:
- Content world separation when appropriate (`WKContentWorld`).
- Strict message handler allowlist.
- No arbitrary `evaluateJavaScript` on untrusted strings.
- Web Inspector gated to debug builds.

**Step 3: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/CT_ADAPTIVE_ENGINE_INDEX.md
git commit -m "docs: strengthen privacy and WebView hardening guidance"
```

---

## Task 10: Summary + visual overview parity with the guide

**Files:**
- Modify: `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
- Modify: `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`

**Step 1: Summary parity checklist**

Ensure summary contains only facts consistent with the guide:
- “Solution” section matches the guide’s stated implementation status (planned vs implemented).
- File locations reflect Task 3.
- Testing commands reflect real commands in the repo (verify before publishing).

**Step 2: Visual overview parity checklist**

Ensure diagrams/tables reflect the guide:
- Phase detection thresholds.
- Window selection table.
- Colormap comparison table.
- Timeline matches “Implementation Checklist” in summary.

**Step 3: Commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md
git commit -m "docs: sync summary + visual overview with canonical guide"
```

---

## Task 11: Index quality pass (navigation, matrices, and “getting started”)

**Files:**
- Modify: `docs/CT_ADAPTIVE_ENGINE_INDEX.md`

**Step 1: Verify every link in Quick Navigation resolves**

Manual: click each link in your editor preview.

**Step 2: Ensure matrices match doc reality**

Update:
- Document comparison matrix
- Section-by-section guide
- File locations summary (TypeScript/Swift/docs)

**Step 3: Commit**

Run:
```bash
git add docs/CT_ADAPTIVE_ENGINE_INDEX.md
git commit -m "docs: refine index navigation and matrices"
```

---

## Task 12: Verification sweep (grep-based “doc invariants”)

**Files:**
- Modify: (only if failures) any of the 4 docs

**Step 1: Run the invariant grep suite**

Run:
```bash
rg -n "nv\\.cmapper|\\(nv as any\\)\\.cmapper|Math\\.max\\(calMin, 0\\)|webViewManager\\.evaluator" \
  docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md \
  docs/CT_ADAPTIVE_ENGINE_INDEX.md
```
Expected: no matches (or matches are explicitly in “anti-pattern” callouts).

**Step 2: Spot-check the revision histories are consistent**

Confirm each doc’s revision history has the same date and a short “what changed” line.

**Step 3: Final commit**

Run:
```bash
git add docs/ct-urinary-tract-adaptive-engine-implementation-guide.md \
  docs/ct-urinary-tract-adaptive-engine-implementation-summary.md \
  docs/ct-urinary-tract-adaptive-engine-visual-overview.md \
  docs/CT_ADAPTIVE_ENGINE_INDEX.md
git commit -m "docs: verification sweep and consistency fixes"
```

---

## Definition of Done (doc suite)

- All four docs agree on: status, file paths, API names, message payloads, and algorithm invariants.
- Every Apple API behavior claim is backed by a Cupertino `apple-docs://...` URI.
- Every Niivue API claim can be traced to the upstream source at `/Users/leandroalmeida/niivue`.
- No “forbidden patterns” appear in docs (Task 12 grep suite passes).

