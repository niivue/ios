# Urology CT Stone Evaluation App - Design Document

**Date:** January 4, 2026
**Author:** Claude Code (Opus 4.5)
**Status:** Approved
**Target Platform:** iOS 26+ (iPhone 16 Pro Max, iPad Pro)

---

## Executive Summary

A mobile CT viewer optimized for urologists, featuring AI-powered kidney stone detection, precise measurements, and 3D surgical planning visualization. Built on NiiVue WebGL with Core ML for on-device AI inference.

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Primary Users | Urologists/Radiologists | Direct clinical use, not SDK distribution |
| Initial Focus | Stone evaluation | Highest volume, clear deliverables |
| Deployment | Mobile/offline | File-based import, no PACS initially |
| Device Strategy | iPhone + iPad parity | Full features on both, Apple Pencil iPad-only |
| Rendering | NiiVue WebGL | Proven technology, faster MVP |
| AI Approach | Hybrid (existing + custom) | TotalSegmentator + HU thresholding |

### Roadmap Summary

| Phase | Focus | Exit Criteria |
|-------|-------|---------------|
| Phase 1 | Foundation | CT viewing with NiiVue on iPhone/iPad |
| Phase 2 | AI Pipeline | Auto stone detection <10 seconds |
| Phase 3 | Clinical Tools | Measurements, 3D, refinement |
| Phase 4 | Polish | Reporting, TestFlight beta |
| Future | Expansion | Tumors, surgical planning, PACS |

---

## 1. Product Overview

### 1.1 Vision

A mobile CT viewer that enables urologists to:
- Import CT scans from any source (Files, AirDrop, cloud)
- Automatically detect and measure kidney stones using AI
- Visualize findings in 2D and 3D
- Generate structured reports for clinical documentation

### 1.2 Target Users

**Primary:** Urologists reviewing CT scans for stone disease
- Hospital-based urologists
- Private practice urologists
- Urology residents/fellows

**Secondary:** Radiologists providing urology consultations

### 1.3 Use Cases

1. **Pre-operative planning** - Evaluate stone burden before surgery
2. **Clinic consultation** - Review imaging with patients
3. **Intraoperative reference** - Quick access in OR
4. **Remote consultation** - Discuss cases with colleagues
5. **Emergency evaluation** - Assess acute stone presentations

### 1.4 Scaling Path

```
Phase 1-4: Stone Evaluation (MVP)
     ↓
Phase 5: Renal Tumors (RENAL nephrometry scoring)
     ↓
Phase 6: Surgical Planning (vessel segmentation, 3D export)
     ↓
Phase 7: PACS Integration (hospital connectivity)
```

---

## 2. Architecture

### 2.1 High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      SwiftUI Layer                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ Study List  │  │ Viewer UI   │  │ Report Generator    │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│                    Bridge Layer (Swift)                     │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐  │
│  │ DICOM       │  │ Measurement │  │ Segmentation        │  │
│  │ Importer    │  │ Manager     │  │ Controller          │  │
│  └─────────────┘  └─────────────┘  └─────────────────────┘  │
├─────────────────────────────────────────────────────────────┤
│              Core ML          │         NiiVue WebGL        │
│  ┌─────────────────────────┐  │  ┌───────────────────────┐  │
│  │ TotalSegmentator        │  │  │ 2D Viewer (MPR)       │  │
│  │ (Kidney Segmentation)   │  │  │ 3D Volume Rendering   │  │
│  │ Stone Detector          │  │  │ Overlay Rendering     │  │
│  │ (HU Thresholding)       │  │  │ Measurement Tools     │  │
│  └─────────────────────────┘  │  └───────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Technology Stack

| Layer | Technology | Version |
|-------|------------|---------|
| UI Framework | SwiftUI | iOS 26 |
| Rendering | NiiVue (WebGL 2.0) | Latest |
| WebView | WKWebView | iOS 26 |
| AI/ML | Core ML | iOS 26 |
| DICOM Parsing | dcm2niix (WASM) | Latest |
| Image Processing | Accelerate, vImage | iOS 26 |

### 2.3 Data Flow

```
DICOM Files → Import → Parse → NIfTI Conversion
                                      ↓
                         ┌────────────┴────────────┐
                         ↓                         ↓
                    Core ML                   NiiVue
                    (Segmentation)            (Rendering)
                         ↓                         ↓
                    Stone Detection           2D/3D Display
                         ↓                         ↓
                    Measurements ─────────→ Overlay on View
                         ↓
                    Report Generation
```

---

## 3. Clinical Workflow

### 3.1 Stone Evaluation Workflow

```
┌──────────────────────────────────────────────────────────────────┐
│  1. IMPORT                                                        │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐           │
│  │ Files App   │ OR │ AirDrop     │ OR │ Cloud Link  │           │
│  └──────┬──────┘    └──────┬──────┘    └──────┬──────┘           │
│         └──────────────────┼──────────────────┘                   │
│                            ▼                                      │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ DICOM Parser → Series Selection → Load to NiiVue            │ │
│  └─────────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────────┤
│  2. AI ANALYSIS (runs automatically on load)                      │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ TotalSegmentator    →  Kidney + Ureter Masks                │ │
│  │ HU Threshold (>150) →  Stone Candidates                     │ │
│  │ Connected Components →  Individual Stone Objects            │ │
│  │ Auto-Measure         →  Size, Volume, HU per stone          │ │
│  └─────────────────────────────────────────────────────────────┘ │
├──────────────────────────────────────────────────────────────────┤
│  3. REVIEW & REFINE                                               │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ 2D MPR View  │  │ 3D VRT View  │  │ Stone List Panel       │ │
│  │ • Axial      │  │ • Rotate     │  │ • Each stone           │ │
│  │ • Coronal    │  │ • Clip plane │  │ • Size (mm)            │ │
│  │ • Sagittal   │  │ • Zoom       │  │ • HU value             │ │
│  │ • Oblique    │  │ • Presets    │  │ • Location             │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
│                                                                   │
│  Manual Corrections:                                              │
│  • Add missed stone    • Delete false positive                   │
│  • Adjust measurement  • Reclassify location                     │
├──────────────────────────────────────────────────────────────────┤
│  4. REPORT                                                        │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │ Summary: 3 stones, total burden 15mm                        │ │
│  │ • Right kidney, lower pole: 8mm (450 HU)                    │ │
│  │ • Right kidney, upper pole: 4mm (380 HU)                    │ │
│  │ • Left UPJ: 3mm (520 HU)                                    │ │
│  │                                                              │ │
│  │ [Export PDF]  [Copy to Clipboard]  [Share]                  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

### 3.2 Feature List (MVP)

| Category | Feature | Priority |
|----------|---------|----------|
| **Import** | DICOM folder import from Files app | P0 |
| **Import** | AirDrop receive | P0 |
| **Import** | Series picker (if multiple series) | P0 |
| **Viewing** | 2D axial/coronal/sagittal | P0 |
| **Viewing** | MPR (arbitrary plane) | P1 |
| **Viewing** | Window/level presets (soft tissue, bone, urographic) | P0 |
| **Viewing** | 3D volume rendering | P0 |
| **AI** | Kidney segmentation (TotalSegmentator) | P0 |
| **AI** | Stone detection (HU threshold) | P0 |
| **AI** | Auto-measurement (size, HU) | P0 |
| **AI** | Location classification | P1 |
| **Measurement** | Manual distance tool | P0 |
| **Measurement** | Manual HU probe | P0 |
| **Measurement** | Stone volume calculation | P1 |
| **Segmentation** | Overlay visualization (kidney mask) | P0 |
| **Segmentation** | Stone highlighting | P0 |
| **Segmentation** | Manual refinement (add/remove) | P1 |
| **Report** | Stone summary list | P0 |
| **Report** | Export to PDF | P1 |
| **Report** | Copy text to clipboard | P0 |

---

## 4. AI/ML Architecture

### 4.1 Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    CT Volume (DICOM)                             │
│                         512×512×~300                             │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  STAGE 1: Preprocessing                                          │
│  • Resample to isotropic voxels (1.5mm³)                        │
│  • Normalize HU values (-1024 to 3071 → 0-1)                    │
│  • Patch extraction for inference (128³ tiles)                   │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  STAGE 2: Organ Segmentation (TotalSegmentator Core ML)          │
│  Input:  CT patches (128×128×128)                               │
│  Output: Kidney masks (L+R), Ureter masks, Bladder mask         │
│  Model:  ~50MB Core ML, runs on Neural Engine                   │
│  Time:   ~3-5 seconds on A18 Pro                                │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  STAGE 3: Stone Detection (Classical + ML Hybrid)                │
│  Within kidney/ureter ROI only:                                 │
│  1. HU Threshold: voxels > 150 HU (stone candidates)            │
│  2. Connected Components: group into objects                    │
│  3. Size Filter: remove < 2mm (noise)                           │
│  4. Shape Analysis: sphericity, elongation                      │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  STAGE 4: Measurement & Classification                           │
│  For each detected stone:                                       │
│  • Bounding box → longest axis (mm)                             │
│  • Voxel count → volume (mm³)                                   │
│  • Mean HU within stone mask                                    │
│  • Centroid location → classify (kidney pole, ureter, UPJ)      │
└─────────────────────────┬───────────────────────────────────────┘
                          ▼
┌─────────────────────────────────────────────────────────────────┐
│  OUTPUT: Stone Report                                            │
│  stones: [                                                      │
│    { id: 1, location: "Right kidney, lower pole",               │
│      size_mm: 8.2, volume_mm3: 245, hu_mean: 450 },             │
│    { id: 2, location: "Left UPJ",                               │
│      size_mm: 4.1, volume_mm3: 32, hu_mean: 520 }               │
│  ]                                                              │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Model Strategy

| Component | Source | Size | Conversion |
|-----------|--------|------|------------|
| TotalSegmentator (kidneys) | PyTorch → ONNX → Core ML | ~50-100MB | coremltools |
| Stone detector | Classical algorithm (no model) | N/A | Swift implementation |
| Future: Stone classifier | Train on collected data | ~5MB | Create ML |

### 4.3 Performance Targets (iPhone 16 Pro Max)

| Stage | Target Time |
|-------|-------------|
| DICOM load | < 2 sec |
| Preprocessing | < 1 sec |
| Organ segmentation | < 5 sec |
| Stone detection | < 1 sec |
| **Total** | **< 10 sec** |

---

## 5. UI/UX Design

### 5.1 Design Principles

- **Same functionality** on both iPhone and iPad
- **Adaptive layout** - responsive, not separate designs
- **Gesture-first** - minimize button taps during review
- **Apple Pencil** annotation on iPad only
- **Dark mode primary** - easier on eyes for imaging

### 5.2 iPhone Layout (Portrait)

```
┌─────────────────────────────────┐
│ ← Study    Stone CT    ⚙️ 👁️    │  ← Navigation bar
├─────────────────────────────────┤
│                                 │
│      ┌─────────────────┐        │
│      │                 │        │
│      │   Main Viewer   │        │  ← Primary view
│      │   (2D or 3D)    │        │
│      │                 │        │
│      └─────────────────┘        │
│                                 │
│   [Axial] [Coronal] [3D]        │  ← View mode tabs
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ 🔴 Stone 1: 8mm, 450 HU     │ │  ← Stone list
│ │    Right kidney, lower pole │ │
│ ├─────────────────────────────┤ │
│ │ 🔴 Stone 2: 4mm, 380 HU     │ │
│ │    Right kidney, upper pole │ │
│ └─────────────────────────────┘ │
├─────────────────────────────────┤
│  📏  📍  🎨  📋                 │  ← Tool bar
│ Measure HU  Window Report       │
└─────────────────────────────────┘
```

### 5.3 iPad Layout (Landscape)

```
┌───────────────────────────────────────────────────────────────────────┐
│ ← Studies    Patient: John Doe - CT Abdomen    ⚙️  📋 Report  👁️ View │
├───────────────────────────────────────────────────────────────────────┤
│                                    │                                   │
│  ┌──────────────────────────────┐  │  ┌─────────────────────────────┐ │
│  │                              │  │  │      3D Volume View         │ │
│  │      Primary 2D View         │  │  │     (Kidney + Stones)       │ │
│  │      (Axial/Coronal/Sag)     │  │  │                             │ │
│  │                              │  │  └─────────────────────────────┘ │
│  └──────────────────────────────┘  │                                   │
│                                    │  ┌─────────────────────────────┐ │
│  [Axial] [Coronal] [Sagittal]      │  │  Stone Summary              │ │
│  Window: [Soft] [Bone] [Uro]       │  │  🔴 8mm - R lower pole      │ │
│                                    │  │  🔴 4mm - R upper pole      │ │
│  ┌─────────────────────┐           │  │  Total burden: 15mm         │ │
│  │ Slice: 145/312      │           │  └─────────────────────────────┘ │
│  │ HU at cursor: 45    │           │                                   │
│  └─────────────────────┘           │                                   │
├───────────────────────────────────────────────────────────────────────┤
│  ✏️ Annotate  📏 Measure  📍 HU Probe  🎯 AI Detect  ↩️ Undo          │
└───────────────────────────────────────────────────────────────────────┘
```

### 5.4 Gesture Reference

| Gesture | Action |
|---------|--------|
| **Swipe L/R** on viewer | Change slice |
| **Pinch** | Zoom in/out |
| **Two-finger drag** | Pan |
| **Long press** | HU measurement at point |
| **Tap stone in list** | Jump to stone location |
| **3D: One-finger drag** | Rotate volume |

### 5.5 Shared Components (SwiftUI)

| Component | Description |
|-----------|-------------|
| `CTViewer2D` | NiiVue-powered 2D slice viewer |
| `CTViewer3D` | NiiVue-powered 3D volume renderer |
| `StoneListView` | Scrollable stone summary |
| `MeasurementToolbar` | Distance, HU, annotation tools |
| `WindowPresetPicker` | Soft tissue, bone, urographic |
| `ReportSheet` | Generate/export findings |
| `StudyImporter` | Files app / AirDrop handler |

---

## 6. Implementation Roadmap

### Phase 1: Foundation

**Goal:** Basic CT viewing with NiiVue integration

| Task | Deliverable |
|------|-------------|
| Project setup | Xcode project, iOS 26 SDK, SwiftUI |
| DICOM importer | Load from Files app, parse series |
| NiiVue integration | WebView bridge from existing ios-foundation |
| 2D viewing | Axial, coronal, sagittal navigation |
| Window presets | Soft tissue, bone, urographic |
| Adaptive layout | iPhone/iPad responsive UI |
| Basic gestures | Swipe scroll, pinch zoom, pan |

**Exit Criteria:** Can import CT, view slices, change windows on iPhone + iPad

---

### Phase 2: AI Pipeline

**Goal:** Automatic kidney segmentation and stone detection

| Task | Deliverable |
|------|-------------|
| TotalSegmentator conversion | PyTorch → ONNX → Core ML model |
| Preprocessing pipeline | Resample, normalize, tile CT volume |
| Kidney segmentation | Run Core ML, get kidney masks |
| Stone detection | HU threshold + connected components |
| Auto-measurement | Size (mm), volume, mean HU per stone |
| Location classification | Map centroid to anatomical region |
| Segmentation overlay | Display kidney/stone masks on 2D view |
| Performance optimization | Target <10 sec total pipeline |

**Exit Criteria:** AI detects stones with size/HU in <10 seconds

---

### Phase 3: Clinical Tools

**Goal:** Complete measurement and 3D visualization

| Task | Deliverable |
|------|-------------|
| Manual distance tool | Draw line, show mm |
| HU probe tool | Tap to measure Hounsfield Units |
| 3D volume rendering | NiiVue VRT with kidney/stone highlight |
| 3D interaction | Rotate, zoom, clip plane |
| Stone list panel | Tap to navigate, edit measurements |
| Manual refinement | Add/delete stones, adjust boundaries |
| Apple Pencil (iPad) | Annotation drawing, circle findings |
| Undo/redo | Measurement and annotation history |

**Exit Criteria:** Full clinical workflow functional end-to-end

---

### Phase 4: Polish & Scale

**Goal:** Production-ready app with reporting

| Task | Deliverable |
|------|-------------|
| Report generation | Structured stone summary |
| PDF export | Formatted report with images |
| Clipboard copy | Quick paste into EMR |
| Share sheet | AirDrop, email, save to Files |
| Onboarding | First-run tutorial |
| Settings | Preferences, default presets |
| Error handling | Graceful failures, user messaging |
| TestFlight beta | Deploy to clinical testers |
| Feedback collection | In-app feedback mechanism |

**Exit Criteria:** App ready for TestFlight clinical validation

---

### Future Phases

| Phase | Focus | Key Features |
|-------|-------|--------------|
| Phase 5 | Renal Tumors | Tumor segmentation, RENAL score, multi-phase CT |
| Phase 6 | Surgical Planning | Vessel segmentation, 3D model export, AR preview |
| Phase 7 | PACS Integration | DICOM Query/Retrieve, hospital network connectivity |
| Phase 8 | AI Enhancement | Custom stone classifier, composition prediction |

---

## 7. Technical Specifications

### 7.1 Platform Requirements

| Requirement | Specification |
|-------------|---------------|
| iOS Version | 26.0+ |
| Devices | iPhone 16 Pro/Pro Max, iPad Pro (M-series) |
| Architecture | arm64 only |
| Storage | ~200MB app + user data |
| Memory | 6GB+ recommended |

### 7.2 File Format Support

| Format | Extension | Support Level |
|--------|-----------|---------------|
| DICOM | .dcm, folder | Full |
| NIfTI | .nii, .nii.gz | Full |
| NRRD | .nrrd | Planned |

### 7.3 Security & Privacy

| Concern | Approach |
|---------|----------|
| Data storage | On-device only, no cloud upload |
| PHI handling | No patient data leaves device |
| AI processing | On-device Core ML (no server) |
| File access | Sandboxed, user-initiated import only |

---

## 8. Success Metrics

### Clinical Validation

| Metric | Target |
|--------|--------|
| Stone detection sensitivity | > 95% |
| Stone detection specificity | > 90% |
| Size measurement accuracy | ± 1mm |
| HU measurement accuracy | ± 10 HU |
| Time to complete review | < 2 minutes |

### User Experience

| Metric | Target |
|--------|--------|
| Time to first view | < 5 seconds |
| AI analysis time | < 10 seconds |
| App crash rate | < 0.1% |
| User satisfaction | > 4.5/5 stars |

---

## Appendix A: Window Presets

| Preset | Window Width | Window Level | Use Case |
|--------|--------------|--------------|----------|
| Soft Tissue | 400 | 40 | General abdomen |
| Bone | 2000 | 500 | Skeletal structures, stones |
| Urographic | 300 | 50 | Collecting system, ureters |
| Lung | 1500 | -600 | Chest CT (if applicable) |

---

## Appendix B: Stone Location Classification

| Location Code | Anatomical Region |
|---------------|-------------------|
| RK-UP | Right kidney, upper pole |
| RK-MP | Right kidney, mid pole |
| RK-LP | Right kidney, lower pole |
| LK-UP | Left kidney, upper pole |
| LK-MP | Left kidney, mid pole |
| LK-LP | Left kidney, lower pole |
| R-UPJ | Right ureteropelvic junction |
| L-UPJ | Left ureteropelvic junction |
| R-URE | Right ureter |
| L-URE | Left ureter |
| R-UVJ | Right ureterovesical junction |
| L-UVJ | Left ureterovesical junction |
| BLA | Bladder |

---

## Appendix C: HU Reference Values

| Material | Typical HU Range |
|----------|------------------|
| Air | -1000 |
| Fat | -100 to -50 |
| Water | 0 |
| Soft tissue | 20-80 |
| Blood | 30-45 |
| Muscle | 10-40 |
| Calcium oxalate stone | 400-600 |
| Calcium phosphate stone | 500-700 |
| Uric acid stone | 200-450 |
| Struvite stone | 600-900 |
| Cystine stone | 600-1100 |
| Cortical bone | 1000+ |

---

*Document generated by Claude Code (Opus 4.5) on January 4, 2026*
