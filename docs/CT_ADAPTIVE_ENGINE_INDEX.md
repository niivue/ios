# CT Urinary Tract Adaptive Engine - Documentation Index

**Project:** NiiVue iOS Foundation
**Feature:** CT Urinary Tract Adaptive Preset Engine
**Status:** Implemented — integrated into the iOS app (Option B: JS auto-apply gated by `window.autoApplyCTPreset`)
**Date:** 2026-01-08
**Last Verified:** 2026-01-08
**Validated Against:** `niivue-ios-foundation` @ `2c8ffcd6c2e3f0b143e5f610ce031ef6235262d7`
**Upstream API Reference:** `/Users/leandroalmeida/niivue` @ `f0c010293b01cfb162e2b9e959c27717b07686f1`

---

## Document Suite Overview

This documentation suite provides everything needed to implement the CT Urinary Tract Adaptive Preset Engine from start to finish.

**Canonical source:** `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md`

**Derived views (must not contradict the guide):**
- `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md`
- `docs/ct-urinary-tract-adaptive-engine-visual-overview.md`
- `docs/CT_ADAPTIVE_ENGINE_INDEX.md` (this index)

**Implementation status note:** Core implementation files are present in this repo:
- `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
- `NiiVue/React/src/bridge/ctUrinaryPresets.ts`
- `NiiVue/React/src/bridge/ctAutoApply.ts`
- `NiiVue/React/src/App.tsx` (binds the window functions + auto-apply in `nv.onImageLoaded`)
- `NiiVue/NiiVue/Services/CTPresetService.swift`
- `NiiVue/NiiVue/Web/WebViewManager.swift` (injects the flag + decodes `ctPresetAnalysis`)
- `NiiVue/NiiVue/ContentView.swift` (CT Presets UI + analysis display)

```
┌─────────────────────────────────────────────────────────────────────┐
│                        DOCUMENTATION SUITE                           │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  1. Design Document (Original)                               │  │
│  │     File: docs/plans/2026-01-08-adaptive-ct-urinary-engine-design.md │  │
│  │     Size: 87 KB, 2,505 lines                                 │  │
│  │     Purpose: Original design specification                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  2. Implementation Guide (MAIN DOCUMENT) ⭐                   │  │
│  │     File: docs/ct-urinary-tract-adaptive-engine-implementation-guide.md │  │
│  │     Size: 134 KB, 3,627 lines                                 │  │
│  │     Purpose: Complete step-by-step implementation guide        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  3. Implementation Summary                                    │  │
│  │     File: docs/ct-urinary-tract-adaptive-engine-implementation-summary.md │  │
│  │     Size: 12 KB, 349 lines                                    │  │
│  │     Purpose: Quick navigation guide + key takeaways           │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  4. Visual Overview                                            │  │
│  │     File: docs/ct-urinary-tract-adaptive-engine-visual-overview.md │  │
│  │     Size: 53 KB, 674 lines                                    │  │
│  │     Purpose: Diagrams, workflows, visual decision trees       │  │
│  └──────────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │  5. Documentation Index (THIS FILE)                           │  │
│  │     File: docs/CT_ADAPTIVE_ENGINE_INDEX.md                     │  │
│  │     Size: 21 KB, 427 lines                                    │  │
│  │     Purpose: Master navigation guide                          │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Quick Navigation

### I'm a Developer Starting Implementation

**Start Here:**
1. Read `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (15 min) → Quick overview
2. Read `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (10 min) → Understand architecture
3. Open `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` and jump to Section 5 (File-by-File Implementation)
4. Follow the implementation checklist in Appendix A

### I'm a Technical Lead Reviewing the Design

**Start Here:**
1. Read `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (10 min) → Key takeaways
2. Review `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` (15 min) → Architecture diagrams
3. Skim `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` Sections 2-4 → Clinical foundation, algorithms
4. Review Section 7 (Testing Strategy) → Validation approach

### I'm a Radiologist/Clinical Reviewer

**Start Here:**
1. Read `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` Section 2 (Clinical & Technical Foundation)
2. Review `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` Section 9 (Clinical Use Cases)
3. Examine HU reference values (`docs/ct-urinary-tract-adaptive-engine-visual-overview.md`, Card 2)
4. Provide feedback on phase detection rules

### I'm a Product Manager/Project Manager

**Start Here:**
1. Read `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (5 min) → Problem statement + solution
2. Review `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` Section 6 (Implementation Timeline)
3. Check `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` Section 7 (Testing Strategy)
4. Review success criteria (`docs/CT_ADAPTIVE_ENGINE_INDEX.md`, Success Criteria)

---

## Document Comparison Matrix

| Aspect | Design Document | Implementation Guide | Visual Overview | Summary |
|--------|----------------|---------------------|-----------------|---------|
| **Primary Purpose** | Original specification | Step-by-step instructions | Diagrams & workflows | Quick reference |
| **Target Audience** | Technical leads | Developers | All stakeholders | Everyone |
| **Detail Level** | High | Very High | Medium | Low |
| **Code Examples** | None | File-by-file mapping (7 files) | None | Snippets |
| **Diagrams** | Architecture only | Architecture + data flow | 10+ visual diagrams | ASCII art |
| **Clinical Content** | Extensive | Extensive | Summary | Brief |
| **Testing Strategy** | Outlined | Detailed (with examples) | Workflow only | Checklist |
| **Reading Time** | 60 min | 180 min | 30 min | 15 min |
| **Can Implement From This?** | No | **Yes** | No | No |

---

## Section-by-Section Guide

### Implementation Guide (Main Document)

**Section 1: Executive Summary** (Starts at line 29)
- **Who should read:** Everyone
- **Key takeaways:** Problem, solution, benefits
- **Time:** 5 minutes

**Section 2: Clinical & Technical Foundation** (Starts at line 113)
- **Who should read:** Technical leads, radiologists
- **Key takeaways:** CT phases, HU ranges, why fixed windows fail
- **Time:** 15 minutes

**Section 3: Architecture Deep Dive** (Starts at line 350)
- **Who should read:** Technical leads, developers
- **Key takeaways:** System architecture, data flow, component diagrams
- **Time:** 15 minutes

**Section 4: Algorithm Specifications** (Starts at line 699)
- **Who should read:** Developers, technical leads
- **Key takeaways:** Detailed algorithms with pseudocode
- **Time:** 30 minutes

**Section 5: File-by-File Implementation Guide** (Starts at line 1499) ⭐
- **Who should read:** Developers (REQUIRED)
- **Key takeaways:** File-by-file mapping for 7 files (with key excerpts)
- **Time:** 90 minutes (with code review)

**Section 6: Integration Workflow** (Starts at line 2792)
- **Who should read:** Developers, QA
- **Key takeaways:** Step-by-step sequence, error handling, performance notes, JS→Swift reporting contract
- **Time:** 10 minutes

**Section 7: Testing Strategy** (Starts at line 3029)
- **Who should read:** Developers, QA, technical leads
- **Key takeaways:** Unit tests, integration tests, clinical validation
- **Time:** 20 minutes

**Section 8: User Experience Design** (Starts at line 3309)
- **Who should read:** Designers, developers, PM
- **Key takeaways:** UI flow, visual feedback, accessibility
- **Time:** 10 minutes

**Section 9: References & Sources** (Starts at line 3406)
- **Who should read:** Everyone (as needed)
- **Key takeaways:** Clinical papers, technical docs, standards
- **Time:** 5 minutes (reference)

**Appendix A: Quick Implementation Checklist** (Starts at line 3519)
- **Who should read:** Developers
- **Key takeaways:** Copy-paste task checklist
- **Time:** 5 minutes

**Appendix B: Troubleshooting Guide** (Starts at line 3576)
- **Who should read:** Developers, QA
- **Key takeaways:** Common failure modes and what to check
- **Time:** 5 minutes

---

## Key Code Sections to Review

### 1. Histogram Analyzer (TypeScript)
**File:** `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
**Where:** `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` → Section 5.1 (File 1)
**Purpose:** Core histogram computation
**Complexity:** Medium
**Why Review:** Performance-critical path

### 2. Phase Detector (TypeScript)
**File:** `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
**Where:** `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` → Section 5.1 (File 1)
**Purpose:** Evidence-based phase classification
**Complexity:** Low
**Why Review:** Clinical accuracy depends on this

### 3. Colormap Generator (TypeScript)
**File:** `NiiVue/React/src/bridge/ctAdaptiveEngine.ts`
**Where:** `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` → Section 5.1 (File 1)
**Purpose:** Custom transfer function generation
**Complexity:** Medium
**Why Review:** Visual quality depends on this

### 4. CTPresetService (Swift)
**File:** `NiiVue/NiiVue/Services/CTPresetService.swift`
**Where:** `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` → Section 5.2 (File 5)
**Purpose:** Swift service layer
**Complexity:** Low
**Why Review:** Swift/TypeScript bridge integration

### 5. CT Presets UI (SwiftUI)
**File:** `NiiVue/NiiVue/ContentView.swift`
**Where:** `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` → Section 5.3 (File 7)
**Purpose:** User interface
**Complexity:** Medium
**Why Review:** User experience depends on this

### 6. JS → Swift Reporting Contract (WebKit)
**File:** `NiiVue/NiiVue/Web/WebViewManager.swift`
**Where:** `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` → Section 6.5
**Purpose:** Report phase/window back to native UI (`updateUI` message, `type: "ctPresetAnalysis"`)
**Complexity:** Medium
**Why Review:** Enables “Detected Phase” UI and needs strict schema validation (no PHI)

---

## Critical Decision Points

### 1. Histogram Bin Count
**Decision:** 1001 bins (same as NiiVue's calMinMax)
**Rationale:** Balances precision and performance
**Alternatives Considered:**
- 256 bins (faster, less precise)
- 2001 bins (slower, more precise)
**Trade-off:** 1001 bins = 0.4 HU precision for typical 400 HU range

### 2. Phase Detection Thresholds
**Decision:** Literature-informed initial thresholds (must be validated on your target dataset)
- Arterial: >211 HU (Kawamoto 2006)
- Excretory: 200-400 HU (Silverman 2009)
- Nephrographic: 80-150 HU (Cohan 1995)
**Rationale:** Peer-reviewed references inform initial values; clinical performance must be validated and thresholds tuned per protocol/dataset
**Alternatives Considered:**
- Machine learning (more accurate, slower, requires training data)
- User-specified phase (manual input, defeats automation)

### 3. Adaptive vs. Fixed Presets
**Decision:** Hybrid approach
- Primary: Adaptive preset (auto-detect phase)
- Fallback: Fixed presets (user manual override)
**Rationale:** Best of both worlds (automation + control)
**Alternatives Considered:**
- Fully adaptive (no manual override - rejected for user control)
- Fully fixed (no automation - rejected for time savings)

### 4. Colormap Interpolation
**Decision:** Linear interpolation in RGB + alpha
**Rationale:** Fast, predictable, matches NiiVue standard
**Alternatives Considered:**
- Bézier curves (smoother, slower, harder to tune)
- Spline interpolation (smoothest, slowest, overkill)

### 5. JS → Swift Message Payload Contract
**Decision:** Use the existing `updateUI` `WKScriptMessageHandler` with message body `{ type: "ctPresetAnalysis", payload: { phase, confidence, calMin, calMax, windowWidth, windowLevel, colormap } }`
**Rationale:** Minimizes new bridge surface area; keeps UI updates in a single channel; easier to validate and version
**Alternatives Considered:**
- Create a dedicated `ctPresetAnalysis` message handler channel (clearer separation, but increases bridge surface area)
- Pull-based native polling (simpler, but adds latency and complexity)
**Trade-off:** Requires strict schema validation, minimal logging (no PHI), and a clear “ignore unknown message types” policy

---

## Risk Assessment

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Phase detection inaccurate | Medium | High | Clinical validation, fallback to manual |
| Performance regression | Low | Medium | Benchmarking, optimization |
| Clinical rejection | Low | High | Radiologist review, iterative refinement |
| Integration issues | Medium | Medium | Comprehensive testing, graceful fallback |
| UI/UX confusion | Low | Medium | User testing, clear labels |
| PHI leakage (logs/bridge) | Low | High | No PHI in logs, redaction, debug-only inspector, defined retention/purge policy |
| WebView message injection | Low | Medium | Strict handler allowlist + schema validation, avoid arbitrary `evaluateJavaScript`, use `WKContentWorld` where appropriate |

---

## Success Criteria

### Technical Metrics
- Histogram computation: <300ms for large volumes (target; measure in iOS WebKit)
- Total analysis time: <500ms end-to-end (target)
- Memory overhead: <100MB (target)
- Rendering FPS: 60 FPS (no degradation) (target)
- Unit test coverage: >85% (target)

### Clinical Metrics
- Phase detection accuracy: >90% on a labeled dataset (target; report confusion matrix)
- Visualization quality: ≥4.0/5.0 mean radiologist rating (target)
- Time savings: ≥50% vs. manual adjustment (target)

### User Experience Metrics
- Preset sheet load time: <1 second (target)
- Preset application feedback: <500ms (target)
- Error recovery: Graceful fallback to standard presets (required)
- Accessibility: VoiceOver compatible (required)

---

## File Locations Summary

These paths reflect the current implementation in this repo.

### TypeScript Files
```
/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/
├── App.tsx
└── bridge/
    ├── ctAdaptiveEngine.ts
    ├── ctAdaptiveEngine.test.ts
    ├── ctUrinaryPresets.ts
    ├── ctUrinaryPresets.test.ts
    ├── ctAutoApply.ts
    └── ctAutoApply.test.ts
```

### Swift Files
```
/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVue/
├── ContentView.swift
├── Services/
│   └── CTPresetService.swift
└── Web/
    └── WebViewManager.swift

/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueTests/
├── CTPresetServiceTests.swift
└── WebViewManagerStateTests.swift

/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVueUITests/
└── NiiVueUITests.swift
```

### Documentation Files
```
/Users/leandroalmeida/niivue-ios-foundation/docs/
├── plans/
│   └── 2026-01-08-adaptive-ct-urinary-engine-design.md
├── ct-urinary-tract-adaptive-engine-implementation-guide.md    ⭐
├── ct-urinary-tract-adaptive-engine-implementation-summary.md
├── ct-urinary-tract-adaptive-engine-visual-overview.md
└── CT_ADAPTIVE_ENGINE_INDEX.md (this file)
```

---

## Implementation Timeline Summary

```
PHASE 1 (Days 1-2): TypeScript Layer
├─ ctAdaptiveEngine.ts + unit tests (Vitest)
├─ ctUrinaryPresets.ts (preset library + bridge)
└─ App.tsx modifications (bind `window.*` functions)

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

## Getting Started Checklist

- [ ] Read `docs/ct-urinary-tract-adaptive-engine-implementation-summary.md` (15 min)
- [ ] Review `docs/ct-urinary-tract-adaptive-engine-visual-overview.md` architecture diagrams (10 min)
- [ ] Open `docs/ct-urinary-tract-adaptive-engine-implementation-guide.md` (Section 5: file-by-file)
- [ ] Set up development environment (Xcode, npm, etc.)
- [ ] Run TypeScript tests (`cd NiiVue/React && npm test`)
- [ ] Run Swift unit/UI tests on device (`xcodebuild test ... -destination 'platform=iOS,id=<DEVICE_UDID>' -collect-test-diagnostics never`)
- [ ] Verify CT Presets UI (open sheet, apply preset, confirm analysis appears)
- [ ] Validate with labeled dataset + radiologist review (targets; see guide)
- [ ] Iterate based on feedback

---

## Support & Questions

**Technical Questions:**
- Review the troubleshooting section (Implementation Guide, Appendix B)
- Check the original design document (plans/2026-01-08-*.md)
- Refer to NiiVue iOS architecture docs (docs/ARCHITECTURE_DIAGRAM.md)

**Clinical Questions:**
- Review Section 2 (Clinical & Technical Foundation)
- Examine clinical use cases (Visual Overview, Section 9)
- Consult the references section (Implementation Guide, Section 9)

**Implementation Issues:**
- Check error handling strategies (Implementation Guide, Section 6.2)
- Review testing approach (Implementation Guide, Section 7)
- See performance notes (Implementation Guide, Section 6.3) and performance metrics (Visual Overview, Section 8)

---

## Document Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-01-08 | Initial documentation suite | NiiVue iOS Team |
| 1.1 | 2026-01-08 | Plan execution alignment (sizes/paths, reporting contract, privacy hardening) | NiiVue iOS Team |
| 1.2 | 2026-01-08 | Implemented engine + on-device verification updates | NiiVue iOS Team |

---

**Next Steps:** Run verification tests on a physical device and validate phase detection thresholds against a labeled dataset.

**Questions?** Refer to the appropriate document based on your role and needs (see "Quick Navigation" above).
