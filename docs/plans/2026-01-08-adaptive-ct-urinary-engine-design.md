# Adaptive CT Urinary Tract Visualization Engine - Implementation Design

**Document Version:** 1.0
**Date:** 2026-01-08
**Target Platform:** NiiVue iOS v0.66.0
**Author:** NiiVue iOS Development Team
**Status:** Design Complete - Ready for Implementation

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Clinical Background](#2-clinical-background)
3. [Technical Architecture](#3-technical-architecture)
4. [Component Specifications](#4-component-specifications)
5. [API Reference](#5-api-reference)
6. [Implementation Guide](#6-implementation-guide)
7. [Integration Points](#7-integration-points)
8. [Testing Strategy](#8-testing-strategy)
9. [Research Sources](#9-research-sources)

---

## 1. Executive Summary

### 1.1 Overview

The Adaptive CT Urinary Tract Visualization Engine is an intelligent preprocessing system designed to automatically optimize CT urography visualization for the NiiVue iOS application. The engine analyzes CT volume data to detect the acquisition phase (unenhanced, corticomedullary, nephrographic, excretory, or delayed) and automatically computes optimal windowing parameters and custom transfer functions.

### 1.2 Problem Statement

Standard CT presets (like the existing `ct_kidneys` preset from MRIcro) use fixed window values (114-302 HU) that may not be optimal for all CT urography phases. Different acquisition phases have distinct Hounsfield Unit (HU) characteristics:

- **Corticomedullary Phase (40-70s):** Arterial enhancement >211 HU
- **Nephrographic Phase (100-120s):** Parenchymal enhancement 80-150 HU
- **Excretory Phase (7-10 min):** Collecting system enhancement 200-400 HU

A fixed preset cannot optimally visualize all phases.

### 1.3 Solution

A four-component adaptive engine:

1. **Histogram Analyzer** - Computes 1001-bin histogram, detects intensity peaks, calculates percentiles
2. **Phase Detector** - Classifies CT urography phase based on histogram peak analysis
3. **Adaptive Window Calculator** - Computes optimal HU window based on detected phase and intensity distribution
4. **Colormap Generator** - Generates custom transfer functions with phase-optimized alpha curves

### 1.4 Benefits

- **Automated Optimization:** No manual window/level adjustment required
- **Phase-Aware Visualization:** Automatically adapts to corticomedullary, nephrographic, or excretory phases
- **Clinical Accuracy:** Uses evidence-based HU thresholds from CT urography literature
- **Seamless Integration:** Works with existing NiiVue iOS architecture (Swift + React bridge)
- **Performance:** Histogram computation scales to 1001 bins (same as NiiVue.js `calMinMax`)

---

## 2. Clinical Background

### 2.1 CT Urography Overview

CT urography (CTU) is a comprehensive imaging examination for evaluating the urinary tract (kidneys, ureters, bladder). It combines multiple contrast phases to visualize different anatomical and pathological features.

### 2.2 Acquisition Phases

| Phase | Timing | Primary Structures Enhanced | HU Range | Clinical Use |
|-------|--------|----------------------------|----------|--------------|
| **Unenhanced** | Pre-contrast | None (baseline) | -100 to +50 | Stone detection, hemorrhage |
| **Corticomedullary** | 40-70s | Renal arteries, cortex | Arteries >211 HU | Vascular assessment, RCC characterization |
| **Nephrographic** | 100-120s | Renal parenchyma | Parenchyma 80-150 HU | Mass characterization, parenchymal disease |
| **Excretory** | 7-10 min | Collecting system, ureters | Contrast 200-400 HU | Urothelial tumors, hydronephrosis |
| **Delayed** | 15+ min | Persistent enhancement | Variable | Papillary necrosis, medullary sponge kidney |

### 2.3 Hounsfield Unit Reference Values

**Baseline (Unenhanced):**
- Water: 0 HU
- Air: -1000 HU
- Fat: -50 to -100 HU
- Soft tissue: +20 to +70 HU
- Bone: +400 to +1000 HU
- Calcium oxalate stones: +400 to +600 HU
- Uric acid stones: +200 to +450 HU

**Enhanced (Post-Contrast):**
- Renal cortex (corticomedullary): 150-250 HU
- Renal cortex (nephrographic): 80-150 HU
- Renal medulla (nephrographic): 60-100 HU
- Collecting system (excretory): 200-400 HU (opacified with contrast)
- Renal vessels (arterial): >211 HU

### 2.4 Why Adaptive Windowing Matters

**Clinical Scenario:**

A radiologist reviewing a CT urography examination needs to:
1. **Identify kidney stones** (unenhanced phase, wide window for bone detail)
2. **Assess vascularity** (corticomedullary phase, narrow window for arterial detail)
3. **Characterize renal masses** (nephrographic phase, mid-range window for parenchymal enhancement)
4. **Detect urothelial lesions** (excretory phase, high-contrast window for collecting system)

Using a single fixed preset (e.g., MRIcro's 114-302 HU) will:
- **Overexpose** corticomedullary phase (arterial detail washed out)
- **Underexpose** excretory phase (collecting system too dark)
- **Miss stones** on unenhanced phase (incorrect alpha curve)

**Solution:** The adaptive engine automatically detects the phase and adjusts window/alpha curves accordingly.

### 2.5 Existing CT_Kidneys Preset Analysis

**MRIcro/NiiVue Reference Implementation:**

```objective-c
// From nii_img.mm (line 1080-1085)
case 23: //CT_kidneys
    numNodes = 3;
    nodes[1] = makeRGBAnode(255,129,0,88,103);  // Orange at 34% opacity (88/256)
    nodes[2] = makeRGBAnode(255,255,255,228,256); // White at 89% opacity (228/256)
    break;
```

**Window Values (from nii_WindowController.m line 512-514):**
```objective-c
if (idx == 23) {//CT_kidneys
    darkEdit.doubleValue = 114;   // cal_min
    brightEdit.doubleValue = 302;  // cal_max
}
```

**NiiVue Colormap JSON:**
```json
{
  "min": 114,
  "max": 302,
  "R": [0, 255, 255],
  "G": [0, 129, 255],
  "B": [0, 0, 255],
  "A": [0, 88, 228],
  "I": [0, 103, 255]
}
```

**Transfer Function Breakdown:**

| Index | HU Value | RGB | Alpha | Purpose |
|-------|----------|-----|-------|---------|
| 0 | 114 | (0,0,0) | 0% | Transparent below 114 HU |
| 103 | ~154 | (255,129,0) | 34% | Orange transition (soft tissue) |
| 255 | 302 | (255,255,255) | 89% | White (enhanced parenchyma) |

**Limitations:**
- Fixed window (114-302 HU) does not adapt to different phases
- No detection of arterial enhancement (>211 HU) for corticomedullary phase
- No optimization for excretory phase (200-400 HU collecting system)
- Single alpha curve does not accommodate stone visualization

---

## 3. Technical Architecture

### 3.1 System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         iOS Swift Layer                          │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              CTPresetService.swift                        │   │
│  │  - Coordinates adaptive preset selection                 │   │
│  │  - Interfaces with WebViewManager                        │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ↕ Swift/JS Bridge                   │
└─────────────────────────────────────────────────────────────────┘
                               ↓
┌─────────────────────────────────────────────────────────────────┐
│                      React/TypeScript Layer                      │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           ctAdaptiveEngine.ts (Core Engine)               │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  1. HistogramAnalyzer                              │  │   │
│  │  │     - Computes 1001-bin histogram                  │  │   │
│  │  │     - Detects peaks using derivative analysis      │  │   │
│  │  │     - Calculates percentiles (2%, 50%, 98%)        │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  2. PhaseDetector                                  │  │   │
│  │  │     - Classifies phase from histogram peaks        │  │   │
│  │  │     - Uses HU thresholds (211, 150, 100, etc.)     │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  3. AdaptiveWindowCalculator                       │  │   │
│  │  │     - Computes optimal cal_min/cal_max             │  │   │
│  │  │     - Phase-specific window ranges                 │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  │  ┌────────────────────────────────────────────────────┐  │   │
│  │  │  4. ColormapGenerator                              │  │   │
│  │  │     - Generates custom transfer function           │  │   │
│  │  │     - Phase-optimized alpha curves                 │  │   │
│  │  │     - Color gradient selection                     │  │   │
│  │  └────────────────────────────────────────────────────┘  │   │
│  └──────────────────────────────────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │           ctUrinaryPresets.ts (Preset Library)            │   │
│  │  - ct_urinary_adaptive (auto-computed)                   │   │
│  │  - ct_urinary_combined (vessels + parenchyma blend)      │   │
│  │  - ct_urinary_excretory (collecting system optimized)    │   │
│  │  - ct_urinary_stones (high contrast for calcifications)  │   │
│  └──────────────────────────────────────────────────────────┘   │
│                              ↕                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │               NiiVue v0.66.0 Core                         │   │
│  │  - nv.volumes[0].img (volume data)                       │   │
│  │  - nv.setColormap(id, colormap)                          │   │
│  │  - nv.volumes[0].cal_min / cal_max                       │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Data Flow

```
User loads CT volume
        ↓
Swift: CTPresetService.applyAdaptivePreset(volumeIndex)
        ↓
Swift→JS: evaluateCommand("window.applyAdaptiveCTUrinaryPreset(0)")
        ↓
JS: ctAdaptiveEngine.analyze(nv.volumes[0])
        ↓
    ┌───────────────────────────────────────┐
    │ 1. HistogramAnalyzer.compute()        │
    │    → {bins, peaks, percentiles}       │
    └───────────────────────────────────────┘
        ↓
    ┌───────────────────────────────────────┐
    │ 2. PhaseDetector.classify()           │
    │    → "nephrographic"                  │
    └───────────────────────────────────────┘
        ↓
    ┌───────────────────────────────────────┐
    │ 3. AdaptiveWindowCalculator.compute() │
    │    → {calMin: 60, calMax: 180}        │
    └───────────────────────────────────────┘
        ↓
    ┌───────────────────────────────────────┐
    │ 4. ColormapGenerator.generate()       │
    │    → {R, G, B, A, I arrays}           │
    └───────────────────────────────────────┘
        ↓
JS: nv.setColormap(volumeId, "ct_urinary_adaptive")
    nv.volumes[0].cal_min = 60
    nv.volumes[0].cal_max = 180
        ↓
JS: nv.updateGLVolume() + nv.drawScene()
        ↓
User sees optimized visualization
```

### 3.3 Component Interaction Diagram

```
┌─────────────────────────┐
│  NVImage (volume data)  │
│  - img: TypedArray      │
│  - dims: [x,y,z,t]      │
│  - hdr: NIFTI header    │
└───────────┬─────────────┘
            │
            ↓ (read-only)
┌─────────────────────────────────────────────────────────────────┐
│                     HistogramAnalyzer                            │
│  Input:  img, dims, scl_slope, scl_inter                        │
│  Output: HistogramResult                                        │
│    - bins: number[] (1001 bins)                                 │
│    - binEdges: number[] (1002 edges in HU)                      │
│    - peaks: Peak[] {binIndex, value, huValue, isLocal}          │
│    - percentiles: {p2, p50, p98} in HU                          │
│    - globalMin, globalMax in HU                                 │
└─────────────────────────────────────────────────────────────────┘
            │
            ↓ (HistogramResult)
┌─────────────────────────────────────────────────────────────────┐
│                       PhaseDetector                              │
│  Input:  HistogramResult                                        │
│  Logic:  Peak analysis + HU thresholds                          │
│  Output: CTUrographyPhase                                       │
│    - "unenhanced" | "corticomedullary" | "nephrographic" |      │
│      "excretory" | "delayed"                                    │
│  Confidence: number (0-1)                                       │
└─────────────────────────────────────────────────────────────────┘
            │
            ↓ (CTUrographyPhase + HistogramResult)
┌─────────────────────────────────────────────────────────────────┐
│                  AdaptiveWindowCalculator                        │
│  Input:  CTUrographyPhase, HistogramResult                      │
│  Output: WindowResult                                           │
│    - calMin: number (HU)                                        │
│    - calMax: number (HU)                                        │
│    - recommendedColormap: string                                │
└─────────────────────────────────────────────────────────────────┘
            │
            ↓ (WindowResult + CTUrographyPhase)
┌─────────────────────────────────────────────────────────────────┐
│                     ColormapGenerator                            │
│  Input:  WindowResult, CTUrographyPhase                         │
│  Output: CustomColormap                                         │
│    - min: number (HU)                                           │
│    - max: number (HU)                                           │
│    - R, G, B, A, I: number[] (256 values each)                  │
└─────────────────────────────────────────────────────────────────┘
            │
            ↓ (CustomColormap)
┌─────────────────────────────────────────────────────────────────┐
│                    NiiVue Colormap System                        │
│  cmapper.addColormap(name, colormap)                            │
│  nv.setColormap(volumeId, name)                                 │
│  nv.volumes[0].cal_min = colormap.min                           │
│  nv.volumes[0].cal_max = colormap.max                           │
└─────────────────────────────────────────────────────────────────┘
```

---

## 4. Component Specifications

### 4.1 Component 1: HistogramAnalyzer

**Purpose:** Compute intensity distribution and detect characteristic peaks.

**Algorithm:**

1. **Input Validation**
   - Check that `nv.volumes[volumeIndex]` exists
   - Verify `img` is a TypedArray (Uint8Array, Int16Array, Float32Array, etc.)
   - Extract `dims`, `scl_slope`, `scl_inter` from NVImage header

2. **Intensity Scaling**
   - Convert raw voxel values to Hounsfield Units (HU):
     ```typescript
     HU = raw * scl_slope + scl_inter
     ```
   - Handle `scl_slope === 0` edge case (default to `scl_slope = 1.0`)

3. **Histogram Binning (1001 bins)**
   - Determine global min/max HU values (exclude NaN, optionally ignore zeros)
   - Compute bin edges:
     ```typescript
     const nBins = 1001;
     const binWidth = (globalMax - globalMin) / nBins;
     const binEdges = Array.from({length: nBins + 1}, (_, i) => globalMin + i * binWidth);
     ```
   - Populate histogram bins:
     ```typescript
     for (let i = 0; i < img.length; i++) {
       const hu = img[i] * scl_slope + scl_inter;
       const binIndex = Math.floor((hu - globalMin) / binWidth);
       bins[clamp(binIndex, 0, nBins - 1)]++;
     }
     ```

4. **Peak Detection**
   - Smooth histogram (optional: 3-point moving average to reduce noise)
   - Compute first derivative (difference between consecutive bins)
   - Identify peaks where derivative changes from positive to negative:
     ```typescript
     const peaks: Peak[] = [];
     for (let i = 1; i < nBins - 1; i++) {
       if (bins[i] > bins[i-1] && bins[i] > bins[i+1]) {
         const huValue = binEdges[i] + binWidth / 2;
         peaks.push({binIndex: i, value: bins[i], huValue, isLocal: true});
       }
     }
     ```
   - Sort peaks by bin count (descending) and keep top 5

5. **Percentile Calculation**
   - Compute cumulative sum of histogram bins
   - Find bin indices for 2%, 50%, 98% percentiles:
     ```typescript
     const totalVoxels = bins.reduce((sum, count) => sum + count, 0);
     const p2Target = totalVoxels * 0.02;
     const p50Target = totalVoxels * 0.50;
     const p98Target = totalVoxels * 0.98;

     let cumSum = 0;
     for (let i = 0; i < nBins; i++) {
       cumSum += bins[i];
       if (cumSum >= p2Target && !p2) p2 = binEdges[i];
       if (cumSum >= p50Target && !p50) p50 = binEdges[i];
       if (cumSum >= p98Target && !p98) p98 = binEdges[i];
     }
     ```

**Output:**
```typescript
interface HistogramResult {
  bins: number[];              // 1001 bin counts
  binEdges: number[];          // 1002 bin edges (HU)
  peaks: Peak[];               // Top 5 peaks sorted by count
  percentiles: {
    p2: number;                // 2nd percentile (HU)
    p50: number;               // 50th percentile (median, HU)
    p98: number;               // 98th percentile (HU)
  };
  globalMin: number;           // Minimum HU in volume
  globalMax: number;           // Maximum HU in volume
  totalVoxels: number;         // Total non-excluded voxels
}

interface Peak {
  binIndex: number;            // Index in bins array
  value: number;               // Voxel count at peak
  huValue: number;             // HU value at peak center
  isLocal: boolean;            // True for local maxima
}
```

**Performance Considerations:**
- Use TypedArray iteration (not `forEach` or `map` for speed)
- Preallocate bins array
- Single-pass histogram computation
- Expected time: O(n) where n = volume size (typically ~10-50M voxels)
- Target: <500ms for 512×512×200 volume on iPhone 12+

---

### 4.2 Component 2: PhaseDetector

**Purpose:** Classify CT urography phase based on histogram peak analysis.

**Algorithm:**

1. **Input:** `HistogramResult` from Component 1

2. **Peak Analysis Rules:**

   **Unenhanced Phase Detection:**
   - Primary peak in soft tissue range (20-70 HU)
   - No significant peaks above 150 HU
   - Median (p50) < 80 HU
   - Confidence: 0.9 if no enhancement detected

   **Corticomedullary Phase Detection:**
   - Strong peak in arterial range (>211 HU)
   - Secondary peak in cortical range (150-250 HU)
   - Median (p50) > 100 HU
   - At least one peak with `huValue > 211` and `value > 5% of totalVoxels`
   - Confidence: 0.95 if arterial peak detected

   **Nephrographic Phase Detection:**
   - Primary peak in parenchymal range (80-150 HU)
   - No strong arterial peak (>211 HU)
   - Median (p50) between 60-120 HU
   - Confidence: 0.85 (most common phase)

   **Excretory Phase Detection:**
   - Strong peak in high-contrast range (200-400 HU)
   - Bimodal distribution (tissue + opacified collecting system)
   - Median (p50) > 90 HU
   - At least one peak with `huValue > 200` and `value > 3% of totalVoxels`
   - Confidence: 0.9 if high-density peak detected

   **Delayed Phase Detection:**
   - Broad distribution (multiple peaks)
   - Median (p50) > 100 HU but no dominant high peak
   - Confidence: 0.7 (fallback for ambiguous cases)

3. **Decision Tree:**

   ```typescript
   function classifyPhase(histResult: HistogramResult): PhaseResult {
     const { peaks, percentiles } = histResult;

     // Sort peaks by HU value
     const sortedPeaks = peaks.sort((a, b) => b.huValue - a.huValue);
     const highestPeak = sortedPeaks[0];

     // Arterial peak check (>211 HU)
     const arterialPeak = peaks.find(p => p.huValue > 211);
     if (arterialPeak && arterialPeak.value > totalVoxels * 0.05) {
       return { phase: "corticomedullary", confidence: 0.95 };
     }

     // Excretory peak check (200-400 HU)
     const excretoryPeak = peaks.find(p => p.huValue >= 200 && p.huValue <= 400);
     if (excretoryPeak && excretoryPeak.value > totalVoxels * 0.03) {
       return { phase: "excretory", confidence: 0.9 };
     }

     // Nephrographic range check (80-150 HU)
     const nephroPeak = peaks.find(p => p.huValue >= 80 && p.huValue <= 150);
     if (nephroPeak && percentiles.p50 >= 60 && percentiles.p50 <= 120) {
       return { phase: "nephrographic", confidence: 0.85 };
     }

     // Unenhanced check (median < 80 HU, no high peaks)
     if (percentiles.p50 < 80 && !peaks.some(p => p.huValue > 150)) {
       return { phase: "unenhanced", confidence: 0.9 };
     }

     // Fallback: delayed phase
     return { phase: "delayed", confidence: 0.7 };
   }
   ```

**Output:**
```typescript
interface PhaseResult {
  phase: CTUrographyPhase;
  confidence: number;          // 0-1 (higher = more confident)
  reasoning?: string;          // Optional diagnostic message
}

type CTUrographyPhase =
  | "unenhanced"
  | "corticomedullary"
  | "nephrographic"
  | "excretory"
  | "delayed";
```

---

### 4.3 Component 3: AdaptiveWindowCalculator

**Purpose:** Compute optimal window (cal_min/cal_max) based on detected phase.

**Algorithm:**

1. **Input:** `PhaseResult` + `HistogramResult`

2. **Phase-Specific Window Rules:**

   **Unenhanced Phase:**
   ```typescript
   // Wide window for stone detection + soft tissue
   calMin = Math.max(percentiles.p2, -100);  // Include low-density structures
   calMax = Math.min(percentiles.p98, 600);  // Include stones (400-600 HU)
   recommendedColormap = "ct_urinary_stones";
   ```

   **Corticomedullary Phase:**
   ```typescript
   // Narrow window centered on arterial enhancement
   const arterialPeak = peaks.find(p => p.huValue > 211);
   if (arterialPeak) {
     const center = arterialPeak.huValue;
     const width = 150;  // Narrow window for vascular detail
     calMin = center - width / 2;
     calMax = center + width / 2;
   } else {
     calMin = 150;
     calMax = 300;
   }
   recommendedColormap = "ct_urinary_combined";  // Vessels + parenchyma blend
   ```

   **Nephrographic Phase:**
   ```typescript
   // Mid-range window for parenchymal detail
   calMin = Math.max(percentiles.p2, 60);
   calMax = Math.min(percentiles.p98, 180);
   recommendedColormap = "ct_kidneys";  // Use standard preset
   ```

   **Excretory Phase:**
   ```typescript
   // High-contrast window for collecting system
   const excretoryPeak = peaks.find(p => p.huValue >= 200 && p.huValue <= 400);
   if (excretoryPeak) {
     calMin = 100;  // Show parenchyma as baseline
     calMax = Math.min(excretoryPeak.huValue + 100, 450);
   } else {
     calMin = 100;
     calMax = 400;
   }
   recommendedColormap = "ct_urinary_excretory";
   ```

   **Delayed Phase:**
   ```typescript
   // Broad window for persistent enhancement
   calMin = percentiles.p2;
   calMax = percentiles.p98;
   recommendedColormap = "ct_kidneys";
   ```

3. **Adaptive Refinement:**
   - Clamp `calMin` to avoid negative windows: `calMin = Math.max(calMin, 0)`
   - Ensure minimum width: `if (calMax - calMin < 50) calMax = calMin + 50`
   - Cap maximum window: `calMax = Math.min(calMax, 1000)`

**Output:**
```typescript
interface WindowResult {
  calMin: number;              // Lower HU boundary
  calMax: number;              // Upper HU boundary
  recommendedColormap: string; // Suggested preset name
  windowWidth: number;         // calMax - calMin
  windowLevel: number;         // (calMax + calMin) / 2
}
```

---

### 4.4 Component 4: ColormapGenerator

**Purpose:** Generate custom transfer function (RGBA + I arrays) for NiiVue.

**Algorithm:**

1. **Input:** `WindowResult` + `PhaseResult`

2. **Color Gradient Selection:**

   **Phase-Specific Color Schemes:**

   - **Unenhanced (Stones):**
     ```typescript
     // High-contrast black → yellow → white for stone visibility
     colors = [
       {hu: calMin, rgb: [0, 0, 0]},       // Black
       {hu: 400, rgb: [255, 255, 0]},      // Yellow (stones)
       {hu: calMax, rgb: [255, 255, 255]}  // White
     ];
     ```

   - **Corticomedullary (Vessels):**
     ```typescript
     // Black → red → orange → white for arterial detail
     colors = [
       {hu: calMin, rgb: [0, 0, 0]},       // Black
       {hu: 150, rgb: [178, 36, 24]},      // Dark red (parenchyma)
       {hu: 211, rgb: [232, 51, 37]},      // Red (arteries)
       {hu: calMax, rgb: [255, 255, 255]}  // White
     ];
     ```

   - **Nephrographic (Parenchyma):**
     ```typescript
     // Standard ct_kidneys gradient (black → orange → white)
     colors = [
       {hu: calMin, rgb: [0, 0, 0]},
       {hu: (calMin + calMax) / 2, rgb: [255, 129, 0]},  // Orange
       {hu: calMax, rgb: [255, 255, 255]}
     ];
     ```

   - **Excretory (Collecting System):**
     ```typescript
     // Black → blue → cyan → white for contrast-filled structures
     colors = [
       {hu: calMin, rgb: [0, 0, 0]},       // Black
       {hu: 200, rgb: [0, 100, 200]},      // Blue (contrast)
       {hu: calMax, rgb: [200, 255, 255]}  // Cyan
     ];
     ```

3. **Alpha Curve Generation:**

   **Phase-Specific Alpha Curves:**

   - **Unenhanced:**
     ```typescript
     // Step function for stone visibility
     alphaNodes = [
       {hu: calMin, alpha: 0.0},
       {hu: 100, alpha: 0.0},        // Transparent soft tissue
       {hu: 400, alpha: 0.7},        // Opaque stones
       {hu: calMax, alpha: 0.9}
     ];
     ```

   - **Corticomedullary:**
     ```typescript
     // Smooth ramp favoring high-density vessels
     alphaNodes = [
       {hu: calMin, alpha: 0.0},
       {hu: 150, alpha: 0.3},        // Semi-transparent parenchyma
       {hu: 211, alpha: 0.8},        // Opaque arteries
       {hu: calMax, alpha: 0.95}
     ];
     ```

   - **Nephrographic:**
     ```typescript
     // Standard ct_kidneys alpha (smooth ramp)
     alphaNodes = [
       {hu: calMin, alpha: 0.0},
       {hu: calMin + (calMax - calMin) * 0.4, alpha: 0.34},  // 34% at 40% range
       {hu: calMax, alpha: 0.89}
     ];
     ```

   - **Excretory:**
     ```typescript
     // Bimodal alpha for parenchyma + contrast
     alphaNodes = [
       {hu: calMin, alpha: 0.0},
       {hu: 150, alpha: 0.2},        // Dim parenchyma
       {hu: 200, alpha: 0.7},        // Bright contrast
       {hu: calMax, alpha: 0.95}
     ];
     ```

4. **Array Interpolation (256 values):**

   ```typescript
   function interpolateColormap(
     colors: ColorNode[],
     alphaNodes: AlphaNode[],
     calMin: number,
     calMax: number
   ): CustomColormap {
     const R = new Array(256);
     const G = new Array(256);
     const B = new Array(256);
     const A = new Array(256);
     const I = new Array(256);  // Intensity (index 0-255)

     for (let i = 0; i < 256; i++) {
       I[i] = i;
       const hu = calMin + (calMax - calMin) * (i / 255);

       // Interpolate RGB
       const rgb = interpolateRGB(colors, hu);
       R[i] = rgb[0];
       G[i] = rgb[1];
       B[i] = rgb[2];

       // Interpolate Alpha
       A[i] = interpolateAlpha(alphaNodes, hu) * 255;  // Scale 0-1 → 0-255
     }

     return { min: calMin, max: calMax, R, G, B, A, I };
   }
   ```

**Output:**
```typescript
interface CustomColormap {
  min: number;                 // calMin (HU)
  max: number;                 // calMax (HU)
  R: number[];                 // 256 red values (0-255)
  G: number[];                 // 256 green values (0-255)
  B: number[];                 // 256 blue values (0-255)
  A: number[];                 // 256 alpha values (0-255)
  I: number[];                 // 256 intensity indices (0-255)
}
```

---

## 5. API Reference

### 5.1 TypeScript API (React Layer)

#### 5.1.1 Main Adaptive Engine Interface

```typescript
// File: src/bridge/ctAdaptiveEngine.ts

import { Niivue, NVImage } from '@niivue/niivue';

/**
 * Main adaptive engine API
 */
export class CTAdaptiveEngine {
  /**
   * Analyzes a CT volume and returns adaptive visualization parameters
   * @param volume - NVImage from nv.volumes[index]
   * @returns Complete analysis result with phase, window, and colormap
   */
  static analyze(volume: NVImage): AdaptiveAnalysisResult;

  /**
   * Applies adaptive preset to a Niivue instance
   * @param nv - Niivue instance
   * @param volumeIndex - Index in nv.volumes array
   */
  static applyAdaptivePreset(nv: Niivue, volumeIndex: number): void;
}

/**
 * Complete analysis result
 */
export interface AdaptiveAnalysisResult {
  histogram: HistogramResult;
  phase: PhaseResult;
  window: WindowResult;
  colormap: CustomColormap;
}

/**
 * Histogram computation result
 */
export interface HistogramResult {
  bins: number[];              // 1001 bin counts
  binEdges: number[];          // 1002 bin edges (HU)
  peaks: Peak[];               // Top 5 peaks
  percentiles: {
    p2: number;                // 2nd percentile (HU)
    p50: number;               // Median (HU)
    p98: number;               // 98th percentile (HU)
  };
  globalMin: number;           // Min HU in volume
  globalMax: number;           // Max HU in volume
  totalVoxels: number;         // Non-excluded voxel count
}

export interface Peak {
  binIndex: number;            // Bin array index
  value: number;               // Voxel count
  huValue: number;             // HU at peak center
  isLocal: boolean;            // Local maximum flag
}

/**
 * CT phase classification result
 */
export interface PhaseResult {
  phase: CTUrographyPhase;
  confidence: number;          // 0-1
  reasoning?: string;          // Diagnostic message
}

export type CTUrographyPhase =
  | "unenhanced"
  | "corticomedullary"
  | "nephrographic"
  | "excretory"
  | "delayed";

/**
 * Adaptive window calculation result
 */
export interface WindowResult {
  calMin: number;              // Lower HU boundary
  calMax: number;              // Upper HU boundary
  recommendedColormap: string; // Preset name
  windowWidth: number;         // calMax - calMin
  windowLevel: number;         // (calMax + calMin) / 2
}

/**
 * Custom colormap for NiiVue
 */
export interface CustomColormap {
  min: number;                 // calMin (HU)
  max: number;                 // calMax (HU)
  R: number[];                 // 256 values (0-255)
  G: number[];                 // 256 values (0-255)
  B: number[];                 // 256 values (0-255)
  A: number[];                 // 256 values (0-255)
  I: number[];                 // 256 indices (0-255)
}
```

#### 5.1.2 Histogram Analyzer

```typescript
// File: src/bridge/ctAdaptiveEngine.ts

export class HistogramAnalyzer {
  /**
   * Computes 1001-bin histogram with peak detection
   * @param volume - NVImage to analyze
   * @param options - Analysis options
   */
  static compute(
    volume: NVImage,
    options?: HistogramOptions
  ): HistogramResult;
}

export interface HistogramOptions {
  nBins?: number;              // Default: 1001
  ignoreZeroVoxels?: boolean;  // Default: false
  volumeFrame?: number;        // For 4D volumes, default: 0
  borderFraction?: number;     // Crop border, default: 0 (no crop)
}
```

#### 5.1.3 Phase Detector

```typescript
export class PhaseDetector {
  /**
   * Classifies CT urography phase from histogram
   * @param histogram - Result from HistogramAnalyzer
   */
  static classify(histogram: HistogramResult): PhaseResult;

  /**
   * Gets HU thresholds for a given phase
   */
  static getPhaseThresholds(phase: CTUrographyPhase): PhaseThresholds;
}

export interface PhaseThresholds {
  arterialMin: number;         // e.g., 211 HU for arteries
  parenchymaMin: number;       // e.g., 80 HU for nephrographic
  parenchymaMax: number;       // e.g., 150 HU
  contrastMin: number;         // e.g., 200 HU for excretory
  contrastMax: number;         // e.g., 400 HU
}
```

#### 5.1.4 Window Calculator

```typescript
export class AdaptiveWindowCalculator {
  /**
   * Computes optimal window based on phase and histogram
   * @param phase - Detected phase
   * @param histogram - Histogram result
   */
  static compute(
    phase: PhaseResult,
    histogram: HistogramResult
  ): WindowResult;
}
```

#### 5.1.5 Colormap Generator

```typescript
export class ColormapGenerator {
  /**
   * Generates custom colormap for detected phase
   * @param window - Window parameters
   * @param phase - Detected phase
   */
  static generate(
    window: WindowResult,
    phase: PhaseResult
  ): CustomColormap;

  /**
   * Registers colormap with NiiVue
   * @param nv - Niivue instance
   * @param name - Colormap name
   * @param colormap - Custom colormap
   */
  static register(
    nv: Niivue,
    name: string,
    colormap: CustomColormap
  ): void;
}
```

#### 5.1.6 Window Bridge Functions

```typescript
// File: src/bridge/ctUrinaryPresets.ts

/**
 * Applies adaptive CT urinary preset to a volume
 * Exposed to Swift via window.applyAdaptiveCTUrinaryPreset
 */
export function applyAdaptiveCTUrinaryPreset(
  nv: Niivue,
  volumeIndex: number
): void;

/**
 * Lists available CT urinary presets
 */
export function listCTUrinaryPresets(): string[];

/**
 * Applies a named CT urinary preset
 * @param nv - Niivue instance
 * @param volumeIndex - Volume index
 * @param presetName - One of: "ct_urinary_adaptive", "ct_urinary_combined",
 *                     "ct_urinary_excretory", "ct_urinary_stones"
 */
export function applyCTUrinaryPreset(
  nv: Niivue,
  volumeIndex: number,
  presetName: string
): void;
```

### 5.2 Swift API (iOS Layer)

#### 5.2.1 CTPresetService

```swift
// File: NiiVue/NiiVue/Services/CTPresetService.swift

import Foundation

/// Service for applying adaptive CT urinary presets
@MainActor
final class CTPresetService {

    /// Applies adaptive CT urinary preset to a volume
    /// - Parameters:
    ///   - webViewManager: WebViewManager instance
    ///   - volumeIndex: Index in nv.volumes array
    /// - Throws: JavaScriptError if evaluation fails
    static func applyAdaptivePreset(
        webViewManager: WebViewManager,
        volumeIndex: Int = 0
    ) async throws

    /// Lists available CT urinary presets
    /// - Parameter webViewManager: WebViewManager instance
    /// - Returns: Array of preset names
    static func listPresets(
        webViewManager: WebViewManager
    ) async throws -> [String]

    /// Applies a named CT urinary preset
    /// - Parameters:
    ///   - webViewManager: WebViewManager instance
    ///   - volumeIndex: Volume index
    ///   - presetName: Preset identifier (e.g., "ct_urinary_excretory")
    static func applyPreset(
        webViewManager: WebViewManager,
        volumeIndex: Int = 0,
        presetName: String
    ) async throws
}
```

#### 5.2.2 WebViewManager Extensions

```swift
// File: NiiVue/NiiVue/Web/WebViewManager.swift

extension WebViewManager {

    /// Applies adaptive CT urinary preset (convenience wrapper)
    func applyAdaptiveCTUrinaryPreset(volumeIndex: Int = 0) async throws {
        try await CTPresetService.applyAdaptivePreset(
            webViewManager: self,
            volumeIndex: volumeIndex
        )
    }

    /// Lists CT urinary presets
    func listCTUrinaryPresets() async throws -> [String] {
        try await CTPresetService.listPresets(webViewManager: self)
    }
}
```

#### 5.2.3 SwiftUI Integration Example

```swift
// File: NiiVue/NiiVue/ContentView.swift

struct CTPresetPicker: View {
    @ObservedObject var webViewManager: WebViewManager
    @State private var selectedPreset: String = "ct_urinary_adaptive"
    @State private var availablePresets: [String] = []

    var body: some View {
        Picker("CT Preset", selection: $selectedPreset) {
            ForEach(availablePresets, id: \.self) { preset in
                Text(preset).tag(preset)
            }
        }
        .onChange(of: selectedPreset) { newValue in
            Task {
                try? await webViewManager.applyAdaptiveCTUrinaryPreset(volumeIndex: 0)
            }
        }
        .task {
            availablePresets = try? await webViewManager.listCTUrinaryPresets() ?? []
        }
    }
}
```

---

## 6. Implementation Guide

### 6.1 Implementation Phases

**Phase 1: Core Engine (React/TypeScript)**
- Duration: 2 days
- Files: `src/bridge/ctAdaptiveEngine.ts`
- Deliverables:
  - HistogramAnalyzer class
  - PhaseDetector class
  - AdaptiveWindowCalculator class
  - ColormapGenerator class
  - Unit tests for each component

**Phase 2: Preset Library (React/TypeScript)**
- Duration: 1 day
- Files: `src/bridge/ctUrinaryPresets.ts`
- Deliverables:
  - Window bridge functions
  - Static preset definitions (combined, excretory, stones)
  - Integration with NiiVue colormap system

**Phase 3: Swift Bridge (iOS)**
- Duration: 1 day
- Files: `Services/CTPresetService.swift`, `Web/WebViewManager.swift`
- Deliverables:
  - CTPresetService implementation
  - WebViewManager extensions
  - Swift unit tests

**Phase 4: UI Integration (SwiftUI)**
- Duration: 1 day
- Files: `ContentView.swift`
- Deliverables:
  - CT preset picker UI component
  - Automatic preset application on volume load
  - User preference storage

**Phase 5: Testing & Validation**
- Duration: 2 days
- Deliverables:
  - Test suite with sample CT urography datasets
  - Phase detection accuracy validation
  - Performance benchmarking
  - Clinical review with radiologist

### 6.2 Step-by-Step Implementation

#### Step 1: Create Histogram Analyzer

**File:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/bridge/ctAdaptiveEngine.ts`

```typescript
import { NVImage } from '@niivue/niivue';

export interface Peak {
  binIndex: number;
  value: number;
  huValue: number;
  isLocal: boolean;
}

export interface HistogramResult {
  bins: number[];
  binEdges: number[];
  peaks: Peak[];
  percentiles: { p2: number; p50: number; p98: number };
  globalMin: number;
  globalMax: number;
  totalVoxels: number;
}

export class HistogramAnalyzer {
  static compute(volume: NVImage): HistogramResult {
    const { img, hdr } = volume;
    if (!img || !hdr) {
      throw new Error('Invalid NVImage: missing img or hdr');
    }

    // Scaling parameters
    const scl_slope = hdr.scl_slope || 1.0;
    const scl_inter = hdr.scl_inter || 0.0;
    const toHU = (raw: number) => raw * scl_slope + scl_inter;

    // Find global min/max (exclude NaN)
    let globalMin = Infinity;
    let globalMax = -Infinity;
    let totalVoxels = 0;

    for (let i = 0; i < img.length; i++) {
      const hu = toHU(img[i]);
      if (!isNaN(hu)) {
        globalMin = Math.min(globalMin, hu);
        globalMax = Math.max(globalMax, hu);
        totalVoxels++;
      }
    }

    // Create histogram bins
    const nBins = 1001;
    const binWidth = (globalMax - globalMin) / nBins;
    const bins = new Array(nBins).fill(0);
    const binEdges = Array.from({ length: nBins + 1 },
      (_, i) => globalMin + i * binWidth
    );

    // Populate histogram
    for (let i = 0; i < img.length; i++) {
      const hu = toHU(img[i]);
      if (isNaN(hu)) continue;
      const binIndex = Math.floor((hu - globalMin) / binWidth);
      const clampedIndex = Math.max(0, Math.min(nBins - 1, binIndex));
      bins[clampedIndex]++;
    }

    // Detect peaks
    const peaks: Peak[] = [];
    for (let i = 1; i < nBins - 1; i++) {
      if (bins[i] > bins[i - 1] && bins[i] > bins[i + 1]) {
        peaks.push({
          binIndex: i,
          value: bins[i],
          huValue: binEdges[i] + binWidth / 2,
          isLocal: true
        });
      }
    }
    peaks.sort((a, b) => b.value - a.value); // Sort by count
    const topPeaks = peaks.slice(0, 5);

    // Compute percentiles
    let cumSum = 0;
    let p2 = globalMin, p50 = globalMin, p98 = globalMin;
    const p2Target = totalVoxels * 0.02;
    const p50Target = totalVoxels * 0.50;
    const p98Target = totalVoxels * 0.98;

    for (let i = 0; i < nBins; i++) {
      cumSum += bins[i];
      if (cumSum >= p2Target && p2 === globalMin) p2 = binEdges[i];
      if (cumSum >= p50Target && p50 === globalMin) p50 = binEdges[i];
      if (cumSum >= p98Target && p98 === globalMin) p98 = binEdges[i];
    }

    return {
      bins,
      binEdges,
      peaks: topPeaks,
      percentiles: { p2, p50, p98 },
      globalMin,
      globalMax,
      totalVoxels
    };
  }
}
```

#### Step 2: Create Phase Detector

```typescript
export type CTUrographyPhase =
  | "unenhanced"
  | "corticomedullary"
  | "nephrographic"
  | "excretory"
  | "delayed";

export interface PhaseResult {
  phase: CTUrographyPhase;
  confidence: number;
  reasoning?: string;
}

export class PhaseDetector {
  static classify(histogram: HistogramResult): PhaseResult {
    const { peaks, percentiles, totalVoxels } = histogram;

    // Check for arterial peak (corticomedullary)
    const arterialPeak = peaks.find(p => p.huValue > 211);
    if (arterialPeak && arterialPeak.value > totalVoxels * 0.05) {
      return {
        phase: "corticomedullary",
        confidence: 0.95,
        reasoning: `Arterial peak at ${arterialPeak.huValue.toFixed(1)} HU`
      };
    }

    // Check for excretory peak (200-400 HU)
    const excretoryPeak = peaks.find(p => p.huValue >= 200 && p.huValue <= 400);
    if (excretoryPeak && excretoryPeak.value > totalVoxels * 0.03) {
      return {
        phase: "excretory",
        confidence: 0.9,
        reasoning: `High-density peak at ${excretoryPeak.huValue.toFixed(1)} HU`
      };
    }

    // Check for nephrographic range (80-150 HU)
    const nephroPeak = peaks.find(p => p.huValue >= 80 && p.huValue <= 150);
    if (nephroPeak && percentiles.p50 >= 60 && percentiles.p50 <= 120) {
      return {
        phase: "nephrographic",
        confidence: 0.85,
        reasoning: `Parenchymal peak at ${nephroPeak.huValue.toFixed(1)} HU`
      };
    }

    // Check for unenhanced (median < 80 HU)
    if (percentiles.p50 < 80 && !peaks.some(p => p.huValue > 150)) {
      return {
        phase: "unenhanced",
        confidence: 0.9,
        reasoning: `Low median (${percentiles.p50.toFixed(1)} HU), no enhancement`
      };
    }

    // Fallback: delayed
    return {
      phase: "delayed",
      confidence: 0.7,
      reasoning: "Ambiguous distribution, default to delayed phase"
    };
  }
}
```

#### Step 3: Create Window Calculator

```typescript
export interface WindowResult {
  calMin: number;
  calMax: number;
  recommendedColormap: string;
  windowWidth: number;
  windowLevel: number;
}

export class AdaptiveWindowCalculator {
  static compute(phase: PhaseResult, histogram: HistogramResult): WindowResult {
    const { percentiles, peaks } = histogram;
    let calMin = 0, calMax = 300, recommendedColormap = "ct_kidneys";

    switch (phase.phase) {
      case "unenhanced":
        calMin = Math.max(percentiles.p2, -100);
        calMax = Math.min(percentiles.p98, 600);
        recommendedColormap = "ct_urinary_stones";
        break;

      case "corticomedullary":
        const arterialPeak = peaks.find(p => p.huValue > 211);
        if (arterialPeak) {
          const center = arterialPeak.huValue;
          calMin = center - 75;
          calMax = center + 75;
        } else {
          calMin = 150;
          calMax = 300;
        }
        recommendedColormap = "ct_urinary_combined";
        break;

      case "nephrographic":
        calMin = Math.max(percentiles.p2, 60);
        calMax = Math.min(percentiles.p98, 180);
        recommendedColormap = "ct_kidneys";
        break;

      case "excretory":
        const excretoryPeak = peaks.find(p => p.huValue >= 200 && p.huValue <= 400);
        calMin = 100;
        calMax = excretoryPeak ? Math.min(excretoryPeak.huValue + 100, 450) : 400;
        recommendedColormap = "ct_urinary_excretory";
        break;

      case "delayed":
        calMin = percentiles.p2;
        calMax = percentiles.p98;
        recommendedColormap = "ct_kidneys";
        break;
    }

    // Ensure minimum width
    if (calMax - calMin < 50) {
      calMax = calMin + 50;
    }

    return {
      calMin,
      calMax,
      recommendedColormap,
      windowWidth: calMax - calMin,
      windowLevel: (calMax + calMin) / 2
    };
  }
}
```

#### Step 4: Create Colormap Generator

```typescript
export interface CustomColormap {
  min: number;
  max: number;
  R: number[];
  G: number[];
  B: number[];
  A: number[];
  I: number[];
}

export class ColormapGenerator {
  static generate(window: WindowResult, phase: PhaseResult): CustomColormap {
    const { calMin, calMax } = window;
    const R = new Array(256);
    const G = new Array(256);
    const B = new Array(256);
    const A = new Array(256);
    const I = Array.from({ length: 256 }, (_, i) => i);

    // Phase-specific color and alpha gradients
    for (let i = 0; i < 256; i++) {
      const t = i / 255;
      const hu = calMin + (calMax - calMin) * t;

      // Default: nephrographic-style gradient (black → orange → white)
      let r = 0, g = 0, b = 0, a = 0;

      if (phase.phase === "nephrographic" || phase.phase === "delayed") {
        // Black → Orange → White
        if (t < 0.4) {
          r = Math.floor(255 * (t / 0.4));
          g = Math.floor(129 * (t / 0.4));
          b = 0;
          a = Math.floor(88 * (t / 0.4));
        } else {
          const tt = (t - 0.4) / 0.6;
          r = Math.floor(255);
          g = Math.floor(129 + (255 - 129) * tt);
          b = Math.floor(255 * tt);
          a = Math.floor(88 + (228 - 88) * tt);
        }
      } else if (phase.phase === "corticomedullary") {
        // Black → Red → Orange → White (emphasize vessels)
        if (t < 0.3) {
          r = Math.floor(178 * (t / 0.3));
          g = Math.floor(36 * (t / 0.3));
          b = Math.floor(24 * (t / 0.3));
          a = Math.floor(100 * (t / 0.3));
        } else if (t < 0.6) {
          const tt = (t - 0.3) / 0.3;
          r = Math.floor(178 + (232 - 178) * tt);
          g = Math.floor(36 + (51 - 36) * tt);
          b = Math.floor(24 + (37 - 24) * tt);
          a = Math.floor(100 + (204 - 100) * tt);
        } else {
          const tt = (t - 0.6) / 0.4;
          r = 255;
          g = Math.floor(51 + (255 - 51) * tt);
          b = Math.floor(37 + (255 - 37) * tt);
          a = Math.floor(204 + (242 - 204) * tt);
        }
      } else if (phase.phase === "excretory") {
        // Black → Blue → Cyan (high contrast for collecting system)
        if (t < 0.5) {
          r = 0;
          g = Math.floor(100 * (t / 0.5));
          b = Math.floor(200 * (t / 0.5));
          a = Math.floor(178 * (t / 0.5));
        } else {
          const tt = (t - 0.5) / 0.5;
          r = Math.floor(200 * tt);
          g = Math.floor(100 + (255 - 100) * tt);
          b = Math.floor(200 + (255 - 200) * tt);
          a = Math.floor(178 + (242 - 178) * tt);
        }
      } else if (phase.phase === "unenhanced") {
        // Black → Yellow → White (stone visibility)
        if (hu < 400) {
          r = 0;
          g = 0;
          b = 0;
          a = 0;
        } else if (hu < 500) {
          const tt = (hu - 400) / 100;
          r = Math.floor(255 * tt);
          g = Math.floor(255 * tt);
          b = 0;
          a = Math.floor(178 * tt);
        } else {
          const tt = (hu - 500) / (calMax - 500);
          r = 255;
          g = 255;
          b = Math.floor(255 * tt);
          a = Math.floor(178 + (230 - 178) * tt);
        }
      }

      R[i] = r;
      G[i] = g;
      B[i] = b;
      A[i] = a;
    }

    return { min: calMin, max: calMax, R, G, B, A, I };
  }

  static register(nv: any, name: string, colormap: CustomColormap): void {
    const cmapper = (nv as any).cmapper;
    if (cmapper && typeof cmapper.addColormap === 'function') {
      cmapper.addColormap(name, colormap);
    } else {
      console.warn('[ColormapGenerator] Cannot register colormap: cmapper not available');
    }
  }
}
```

#### Step 5: Create Main Engine Interface

```typescript
export interface AdaptiveAnalysisResult {
  histogram: HistogramResult;
  phase: PhaseResult;
  window: WindowResult;
  colormap: CustomColormap;
}

export class CTAdaptiveEngine {
  static analyze(volume: NVImage): AdaptiveAnalysisResult {
    // 1. Compute histogram
    const histogram = HistogramAnalyzer.compute(volume);

    // 2. Detect phase
    const phase = PhaseDetector.classify(histogram);

    // 3. Compute optimal window
    const window = AdaptiveWindowCalculator.compute(phase, histogram);

    // 4. Generate custom colormap
    const colormap = ColormapGenerator.generate(window, phase);

    return { histogram, phase, window, colormap };
  }

  static applyAdaptivePreset(nv: any, volumeIndex: number): void {
    const volume = nv.volumes[volumeIndex];
    if (!volume) {
      throw new Error(`No volume at index ${volumeIndex}`);
    }

    const result = this.analyze(volume);

    // Register and apply custom colormap
    const cmapName = "ct_urinary_adaptive";
    ColormapGenerator.register(nv, cmapName, result.colormap);

    // Set window
    (volume as any).cal_min = result.window.calMin;
    (volume as any).cal_max = result.window.calMax;

    // Apply colormap
    nv.setColormap(volume.id, cmapName);

    console.log(`[CTAdaptiveEngine] Applied adaptive preset:`, {
      phase: result.phase.phase,
      confidence: result.phase.confidence,
      window: `${result.window.calMin.toFixed(1)} - ${result.window.calMax.toFixed(1)} HU`
    });
  }
}
```

#### Step 6: Create Preset Library

**File:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/bridge/ctUrinaryPresets.ts`

```typescript
import { Niivue } from '@niivue/niivue';
import { CTAdaptiveEngine } from './ctAdaptiveEngine';

/**
 * Applies adaptive CT urinary preset (exposed to Swift)
 */
export function applyAdaptiveCTUrinaryPreset(nv: Niivue, volumeIndex: number): void {
  CTAdaptiveEngine.applyAdaptivePreset(nv, volumeIndex);
}

/**
 * Lists available CT urinary presets
 */
export function listCTUrinaryPresets(): string[] {
  return [
    "ct_urinary_adaptive",
    "ct_urinary_combined",
    "ct_urinary_excretory",
    "ct_urinary_stones"
  ];
}

/**
 * Applies a named preset
 */
export function applyCTUrinaryPreset(
  nv: Niivue,
  volumeIndex: number,
  presetName: string
): void {
  const volume = nv.volumes[volumeIndex];
  if (!volume) {
    throw new Error(`No volume at index ${volumeIndex}`);
  }

  switch (presetName) {
    case "ct_urinary_adaptive":
      applyAdaptiveCTUrinaryPreset(nv, volumeIndex);
      break;

    case "ct_urinary_combined":
      // Vessels + parenchyma blend (fixed preset)
      (volume as any).cal_min = 100;
      (volume as any).cal_max = 300;
      nv.setColormap(volume.id, "ct_kidneys");
      break;

    case "ct_urinary_excretory":
      // Collecting system optimized (fixed preset)
      (volume as any).cal_min = 100;
      (volume as any).cal_max = 400;
      nv.setColormap(volume.id, "ct_kidneys");
      break;

    case "ct_urinary_stones":
      // Stone visualization (fixed preset)
      (volume as any).cal_min = -100;
      (volume as any).cal_max = 600;
      nv.setColormap(volume.id, "bone");
      break;

    default:
      throw new Error(`Unknown CT urinary preset: ${presetName}`);
  }

  nv.updateGLVolume();
  nv.drawScene();
}
```

#### Step 7: Expose to Window Global

**File:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/React/src/App.tsx`

Add imports at the top:
```typescript
import {
  applyAdaptiveCTUrinaryPreset as nvApplyAdaptiveCTUrinaryPreset,
  listCTUrinaryPresets as nvListCTUrinaryPresets,
  applyCTUrinaryPreset as nvApplyCTUrinaryPreset
} from './bridge/ctUrinaryPresets'
```

Add window interface declarations:
```typescript
declare global {
  interface Window {
    // ... existing declarations ...

    // CT Adaptive Engine
    applyAdaptiveCTUrinaryPreset: (volumeIndex: number) => void,
    listCTUrinaryPresets: () => string[],
    applyCTUrinaryPreset: (volumeIndex: number, presetName: string) => void,
  }
}
```

Add function definitions in App component:
```typescript
function applyAdaptiveCTUrinaryPreset(volumeIndex: number): void {
  nvApplyAdaptiveCTUrinaryPreset(nv, volumeIndex)
}

function listCTUrinaryPresets(): string[] {
  return nvListCTUrinaryPresets()
}

function applyCTUrinaryPreset(volumeIndex: number, presetName: string): void {
  nvApplyCTUrinaryPreset(nv, volumeIndex, presetName)
}
```

Add to useEffect hook:
```typescript
React.useEffect(() => {
  // ... existing window assignments ...

  window.applyAdaptiveCTUrinaryPreset = applyAdaptiveCTUrinaryPreset
  window.listCTUrinaryPresets = listCTUrinaryPresets
  window.applyCTUrinaryPreset = applyCTUrinaryPreset
}, []);
```

#### Step 8: Create Swift Service

**File:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVue/Services/CTPresetService.swift`

```swift
import Foundation

/// Service for applying adaptive CT urinary presets to NiiVue volumes
@MainActor
final class CTPresetService {

    /// Applies adaptive CT urinary preset to a volume
    ///
    /// This analyzes the volume's histogram to detect the CT urography phase
    /// (unenhanced, corticomedullary, nephrographic, excretory, delayed) and
    /// automatically computes optimal window/level and colormap settings.
    ///
    /// - Parameters:
    ///   - webViewManager: WebViewManager instance
    ///   - volumeIndex: Index in nv.volumes array (default: 0)
    /// - Throws: JavaScriptError if evaluation fails
    static func applyAdaptivePreset(
        webViewManager: WebViewManager,
        volumeIndex: Int = 0
    ) async throws {
        try await webViewManager.evaluator.evaluateCommand(
            "window.applyAdaptiveCTUrinaryPreset(\(volumeIndex))"
        )
    }

    /// Lists available CT urinary presets
    ///
    /// Returns:
    /// - "ct_urinary_adaptive": Auto-detected phase-optimized preset
    /// - "ct_urinary_combined": Vessels + parenchyma blend (fixed)
    /// - "ct_urinary_excretory": Collecting system optimized (fixed)
    /// - "ct_urinary_stones": Stone visualization (fixed)
    ///
    /// - Parameter webViewManager: WebViewManager instance
    /// - Returns: Array of preset names
    /// - Throws: JavaScriptError if evaluation fails
    static func listPresets(
        webViewManager: WebViewManager
    ) async throws -> [String] {
        guard let jsonString = try await webViewManager.evaluator.evaluateString(
            "JSON.stringify(window.listCTUrinaryPresets())"
        ),
              let data = jsonString.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    /// Applies a named CT urinary preset
    ///
    /// - Parameters:
    ///   - webViewManager: WebViewManager instance
    ///   - volumeIndex: Volume index (default: 0)
    ///   - presetName: One of: "ct_urinary_adaptive", "ct_urinary_combined",
    ///                 "ct_urinary_excretory", "ct_urinary_stones"
    /// - Throws: JavaScriptError if evaluation fails or preset name is invalid
    static func applyPreset(
        webViewManager: WebViewManager,
        volumeIndex: Int = 0,
        presetName: String
    ) async throws {
        let escapedName = try JavaScriptQuote.jsonStringLiteral(presetName)
        try await webViewManager.evaluator.evaluateCommand(
            "window.applyCTUrinaryPreset(\(volumeIndex), \(escapedName))"
        )
    }
}
```

#### Step 9: Add WebViewManager Extension

**File:** `/Users/leandroalmeida/niivue-ios-foundation/NiiVue/NiiVue/Web/WebViewManager.swift`

Add to the end of the file (before final closing brace):

```swift
// MARK: - CT Adaptive Engine (Phase 3: Urinary Tract Visualization)

extension WebViewManager {

    /// Applies adaptive CT urinary preset to the current volume
    func applyAdaptiveCTUrinaryPreset(volumeIndex: Int = 0) async throws {
        try await CTPresetService.applyAdaptivePreset(
            webViewManager: self,
            volumeIndex: volumeIndex
        )
    }

    /// Lists available CT urinary presets
    func listCTUrinaryPresets() async throws -> [String] {
        try await CTPresetService.listPresets(webViewManager: self)
    }

    /// Applies a specific CT urinary preset by name
    func applyCTUrinaryPreset(
        volumeIndex: Int = 0,
        presetName: String
    ) async throws {
        try await CTPresetService.applyPreset(
            webViewManager: self,
            volumeIndex: volumeIndex,
            presetName: presetName
        )
    }
}
```

---

## 7. Integration Points

### 7.1 Existing NiiVue iOS Architecture

The adaptive engine integrates with the existing NiiVue iOS architecture at these key points:

**1. Volume Loading Pipeline:**
```
User imports CT file
    ↓
FileImportService copies to app container
    ↓
ImportedFileStore assigns ID
    ↓
WebViewManager.loadImageFromUrl(niivue://app/files/{id})
    ↓
NiiVue loads volume → onImageLoaded callback
    ↓
** NEW: Auto-apply adaptive preset **
    ↓
CTPresetService.applyAdaptivePreset()
```

**2. WebViewManager Integration:**
- Reuses existing `evaluator` protocol for JS execution
- Leverages `JavaScriptQuote` for safe string escaping
- Follows existing async/await patterns
- Compatible with current error handling (lastErrorMessage)

**3. NiiVue Colormap System:**
- Uses standard `cmapper.addColormap()` API
- Follows NiiVue colormap JSON schema (R, G, B, A, I arrays)
- Sets `cal_min`/`cal_max` via direct volume property access
- Triggers redraw with `updateGLVolume()` + `drawScene()`

**4. React Bridge Layer:**
- Follows existing pattern from `volumeCommands.ts`
- Exposed via `window` global (same as `setColormap`, `setOpacity`)
- Uses TypeScript interfaces for type safety
- Integrates with existing `logToIOS` for diagnostics

### 7.2 Data Flow Integration

```
┌─────────────────────────────────────────────────────────────┐
│                    Existing Components                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  FileImportService → ImportedFileStore → WebViewManager    │
│                                                             │
│  WebViewManager.loadImageFromUrl()                         │
│         ↓                                                   │
│  NiiVue.loadVolumes([{url, name}])                         │
│         ↓                                                   │
│  onImageLoaded(volume) callback                            │
│         ↓                                                   │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                 NEW: Adaptive Engine                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CTPresetService.applyAdaptivePreset(volumeIndex: 0)       │
│         ↓                                                   │
│  window.applyAdaptiveCTUrinaryPreset(0)                    │
│         ↓                                                   │
│  CTAdaptiveEngine.analyze(nv.volumes[0])                   │
│         ↓                                                   │
│  HistogramAnalyzer → PhaseDetector → WindowCalculator      │
│         ↓                                                   │
│  ColormapGenerator.generate() + register()                 │
│         ↓                                                   │
│  nv.setColormap(id, "ct_urinary_adaptive")                 │
│  volume.cal_min = X, volume.cal_max = Y                    │
│         ↓                                                   │
│  nv.updateGLVolume() + nv.drawScene()                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                Existing Rendering Pipeline                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  NiiVue WebGL shaders apply colormap + alpha               │
│         ↓                                                   │
│  User sees optimized CT visualization                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 7.3 Backward Compatibility

**No Breaking Changes:**
- All existing colormaps remain available
- Standard `setColormap()`/`setOpacity()` API unchanged
- Manual window/level adjustment still works
- Adaptive engine is opt-in (must be explicitly called)

**Fallback Behavior:**
- If adaptive engine fails (e.g., corrupted volume), logs error but doesn't crash
- Falls back to default NiiVue behavior (robust min/max from `calMinMax`)
- User can manually override with standard colormap picker

### 7.4 Session Persistence

The adaptive preset should **not** be persisted in session snapshots (too volume-specific). Instead:

**Current Behavior (Preserved):**
- `SessionSnapshotV1` stores `volumeSources` (URLs + names)
- `ViewerStateSnapshot` stores per-volume `colormap`, `opacity`, `frame4D`

**Adaptive Engine Behavior:**
- On session restore, reload volumes from `volumeSources`
- Re-run adaptive analysis (histogram distribution may differ due to sampling)
- **Alternative:** Store computed `cal_min`/`cal_max` in `ViewerStateSnapshot` (simpler)

**Recommended Approach:**
```typescript
// In exportViewerState:
const volumes = (nv.volumes as any[]).map((v) => ({
  colormap: v.colormap,
  opacity: v.opacity,
  frame4D: v.frame4D ?? 0,
  calMin: v.cal_min,     // NEW: Persist computed window
  calMax: v.cal_max,     // NEW
}))
```

```typescript
// In applyViewerState:
snapshot.volumes.forEach((state, index) => {
  // ... existing code ...

  if (typeof state.calMin === 'number' && typeof state.calMax === 'number') {
    volume.cal_min = state.calMin;
    volume.cal_max = state.calMax;
  }
})
```

---

## 8. Testing Strategy

### 8.1 Unit Testing (TypeScript)

**Test File:** `src/bridge/ctAdaptiveEngine.test.ts`

**Test Cases:**

1. **HistogramAnalyzer Tests:**
   - Valid volume with known distribution → correct bin counts
   - Volume with NaN values → NaN excluded from histogram
   - Volume with all zeros → handles degenerate case
   - Percentile calculation accuracy (synthetic data with known p2/p50/p98)
   - Peak detection: single peak, multiple peaks, no peaks

2. **PhaseDetector Tests:**
   - Synthetic histogram with arterial peak (>211 HU) → "corticomedullary"
   - Histogram with excretory peak (200-400 HU) → "excretory"
   - Histogram with parenchymal peak (80-150 HU) → "nephrographic"
   - Low median (<80 HU), no high peaks → "unenhanced"
   - Ambiguous distribution → "delayed" with low confidence

3. **AdaptiveWindowCalculator Tests:**
   - Each phase → expected calMin/calMax range
   - Edge case: calMax - calMin < 50 → enforces minimum width
   - Edge case: calMin < 0 → clamps to 0

4. **ColormapGenerator Tests:**
   - Generate colormap → R/G/B/A/I arrays have 256 values
   - Alpha curve monotonicity (should generally increase with HU)
   - Register with NiiVue → colormap added to cmapper

**Example Test:**

```typescript
import { describe, it, expect } from 'vitest';
import { PhaseDetector } from './ctAdaptiveEngine';

describe('PhaseDetector', () => {
  it('classifies corticomedullary phase with arterial peak', () => {
    const histogram: HistogramResult = {
      bins: Array(1001).fill(0),
      binEdges: Array(1002).fill(0),
      peaks: [
        { binIndex: 700, value: 50000, huValue: 220, isLocal: true }  // Arterial
      ],
      percentiles: { p2: 50, p50: 110, p98: 250 },
      globalMin: 0,
      globalMax: 300,
      totalVoxels: 1000000
    };

    const result = PhaseDetector.classify(histogram);

    expect(result.phase).toBe('corticomedullary');
    expect(result.confidence).toBeGreaterThan(0.9);
  });
});
```

### 8.2 Integration Testing (Swift)

**Test File:** `NiiVueTests/CTPresetServiceTests.swift`

**Test Cases:**

1. **Service API Tests:**
   - `applyAdaptivePreset()` executes without error
   - `listPresets()` returns expected array
   - `applyPreset()` with valid name succeeds
   - `applyPreset()` with invalid name throws error

2. **WebViewManager Integration:**
   - Load CT volume → call `applyAdaptiveCTUrinaryPreset()` → no crash
   - Verify `cal_min`/`cal_max` changed after preset application
   - Verify colormap changed (check `volumes[0].colormap` property)

**Example Test:**

```swift
import XCTest
@testable import NiiVue

@MainActor
final class CTPresetServiceTests: XCTestCase {

    func testListPresetsReturnsExpectedArray() async throws {
        let manager = WebViewManager()
        manager.load()

        // Wait for ready
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertTrue(manager.isReady)

        let presets = try await CTPresetService.listPresets(webViewManager: manager)

        XCTAssertTrue(presets.contains("ct_urinary_adaptive"))
        XCTAssertTrue(presets.contains("ct_urinary_combined"))
        XCTAssertTrue(presets.contains("ct_urinary_excretory"))
        XCTAssertTrue(presets.contains("ct_urinary_stones"))
    }
}
```

### 8.3 UI Testing (XCTest)

**Test Scenarios:**

1. **Preset Picker UI:**
   - Launch app → tap "CT Preset" picker → verify presets listed
   - Select "ct_urinary_adaptive" → verify volume rendering changes

2. **Automatic Preset Application:**
   - Import CT file → verify adaptive preset auto-applied
   - Check console logs for phase detection message

**Example UI Test:**

```swift
import XCTest

final class CTPresetUITests: XCTestCase {

    func testAdaptivePresetPickerIsVisible() throws {
        let app = XCUIApplication()
        app.launch()

        // Wait for web view ready
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10))

        // Find CT preset picker
        let picker = app.pickers["CTPresetPicker"]
        XCTAssertTrue(picker.exists)

        // Tap to open picker
        picker.tap()

        // Verify adaptive option exists
        let adaptiveOption = app.pickerWheels.element.adjust(toPickerWheelValue: "ct_urinary_adaptive")
        XCTAssertTrue(adaptiveOption)
    }
}
```

### 8.4 Clinical Validation

**Test Dataset Requirements:**

Obtain sample CT urography DICOM series representing each phase:

1. **Unenhanced Phase:**
   - Expected: Median ~40 HU, no enhancement peaks
   - Validate: Engine classifies as "unenhanced" with confidence >0.85
   - Visual check: Stone visibility (if present)

2. **Corticomedullary Phase:**
   - Expected: Arterial peak >211 HU
   - Validate: Engine classifies as "corticomedullary" with confidence >0.9
   - Visual check: Renal arteries clearly visible, good cortex detail

3. **Nephrographic Phase:**
   - Expected: Parenchymal peak 80-150 HU
   - Validate: Engine classifies as "nephrographic" with confidence >0.8
   - Visual check: Uniform parenchymal enhancement, good mass characterization

4. **Excretory Phase:**
   - Expected: High-density peak 200-400 HU (opacified collecting system)
   - Validate: Engine classifies as "excretory" with confidence >0.85
   - Visual check: Collecting system/ureters clearly opacified

**Validation Protocol:**

1. Load each test volume
2. Apply adaptive preset
3. Record detected phase + confidence
4. Have radiologist review visualization quality (5-point Likert scale):
   - 1 = Poor (unusable)
   - 2 = Fair (suboptimal)
   - 3 = Good (adequate)
   - 4 = Very Good (preferred over manual adjustment)
   - 5 = Excellent (perfect)

5. Compare to manual window/level adjustment by expert

**Success Criteria:**
- Phase detection accuracy: >90% on labeled dataset (n=20 volumes minimum)
- Radiologist quality rating: Mean ≥4.0
- Time savings: Adaptive preset faster than manual adjustment by ≥50%

### 8.5 Performance Benchmarking

**Metrics to Track:**

1. **Histogram Computation Time:**
   - Target: <300ms for 512×512×200 volume (52M voxels)
   - Measure on iPhone 12, 13, 14, 15

2. **Total Analysis Time (end-to-end):**
   - Target: <500ms (histogram + phase + window + colormap)

3. **Memory Usage:**
   - Peak memory during histogram computation
   - Target: <100MB additional memory

4. **Rendering Performance:**
   - FPS before/after adaptive preset application
   - Target: No degradation (same as standard presets)

**Benchmark Test:**

```typescript
// In ctAdaptiveEngine.test.ts
describe('Performance', () => {
  it('analyzes 512x512x200 volume in <500ms', () => {
    const volume = createSyntheticVolume(512, 512, 200);

    const start = performance.now();
    const result = CTAdaptiveEngine.analyze(volume);
    const elapsed = performance.now() - start;

    expect(elapsed).toBeLessThan(500);
    console.log(`Analysis completed in ${elapsed.toFixed(1)}ms`);
  });
});
```

---

## 9. Research Sources

### 9.1 Clinical Literature

**Primary References:**

1. **Silverman SG, Leyendecker JR, Amis ES Jr.**
   "What is the current role of CT urography and MR urography in the evaluation of the urinary tract?"
   *Radiology.* 2009;250(2):309-323.
   DOI: 10.1148/radiol.2502080534
   *Key: Defines CT urography phases and timing*

2. **Rouprêt M, Babjuk M, Compérat E, et al.**
   "European Association of Urology Guidelines on Upper Urinary Tract Urothelial Carcinoma: 2020 Update"
   *European Urology.* 2021;79(1):62-79.
   DOI: 10.1016/j.eururo.2020.05.042
   *Key: Clinical indications for excretory phase imaging*

3. **Kawamoto S, Horton KM, Fishman EK.**
   "Opacification of the Collecting System on Early-Phase CT: A Sign of Renal Pelvic Obstruction."
   *American Journal of Roentgenology.* 2006;186(2):472-477.
   DOI: 10.2214/AJR.04.1318
   *Key: Excretory phase HU values for contrast opacification*

4. **Cohan RH, Sherman LS, Korobkin M, et al.**
   "Renal Masses: Assessment of Corticomedullary-Phase and Nephrographic-Phase CT Scans."
   *Radiology.* 1995;196(2):445-451.
   DOI: 10.1148/radiology.196.2.7617859
   *Key: Parenchymal enhancement values by phase*

### 9.2 Hounsfield Unit Reference Data

**Standard HU Values:**

- **ACR CT Accreditation Program Phantom Testing:**
  HU accuracy requirements: ±5 HU for water, ±10% for contrast materials
  Source: ACR CT Quality Control Manual (2017)

- **AAPM Report No. 204:**
  "Size-Specific Dose Estimates (SSDE) in Pediatric and Adult Body CT Examinations"
  American Association of Physicists in Medicine (2011)
  *Key: Standardized HU measurement protocols*

**Urinary Tract Specific:**

- **Renal Enhancement Values:**
  - Unenhanced cortex: 30-50 HU
  - Corticomedullary cortex: 150-250 HU
  - Nephrographic cortex: 80-150 HU
  - Nephrographic medulla: 60-100 HU

  Source: Leyendecker JR, et al. "MR urography: practical techniques and clinical applications." *Radiographics.* 2008;28(1):23-46.

- **Stone Attenuation:**
  - Calcium oxalate: 400-600 HU
  - Uric acid: 200-450 HU
  - Struvite: 600-900 HU
  - Cystine: 400-600 HU

  Source: Mostafavi MR, et al. "Dependence of Hounsfield unit on calculus composition and size." *Journal of Endourology.* 2000;14(1):65-68.

### 9.3 Technical References

**NiiVue Implementation:**

1. **NiiVue GitHub Repository:**
   https://github.com/niivue/niivue
   Commit: 0.66.0 release (2023)
   *Key: Colormap JSON schema, `calMinMax` algorithm in IntensityCalibration.ts*

2. **MRIcro Desktop Implementation:**
   https://github.com/neurolabusc/MRIcro (Objective-C reference)
   Files: `nii_img.mm` (colormap LUTs), `nii_WindowController.m` (window presets)
   *Key: CT_kidneys preset definition (nodes + HU window)*

**Histogram Analysis Algorithms:**

3. **Otsu N.**
   "A threshold selection method from gray-level histograms."
   *IEEE Transactions on Systems, Man, and Cybernetics.* 1979;9(1):62-66.
   DOI: 10.1109/TSMC.1979.4310076
   *Key: Peak detection and threshold selection from histograms*

4. **Freedman D, Diaconis P.**
   "On the histogram as a density estimator: L2 theory."
   *Zeitschrift für Wahrscheinlichkeitstheorie und verwandte Gebiete.* 1981;57(4):453-476.
   DOI: 10.1007/BF01025868
   *Key: Optimal bin width calculation (though we use fixed 1001 bins)*

**Transfer Function Design:**

5. **Levoy M.**
   "Display of surfaces from volume data."
   *IEEE Computer Graphics and Applications.* 1988;8(3):29-37.
   DOI: 10.1109/38.511
   *Key: Alpha compositing and transfer function design for volume rendering*

6. **Kniss J, Kindlmann G, Hansen C.**
   "Multidimensional Transfer Functions for Interactive Volume Rendering."
   *IEEE Transactions on Visualization and Computer Graphics.* 2002;8(3):270-285.
   DOI: 10.1109/TVCG.2002.1021579
   *Key: Advanced transfer function design (alpha curves)*

### 9.4 Medical Imaging Standards

**DICOM Standard:**

- **DICOM PS3.3-2023e - Information Object Definitions**
  Section C.8.15.3: CT Image Module (Rescale Intercept/Slope for HU conversion)
  https://dicom.nema.org/medical/dicom/current/output/chtml/part03/sect_C.8.15.3.html

- **DICOM PS3.4-2023e - Service-Object Pair Classes**
  Section CC: Enhanced CT Image IOD
  https://dicom.nema.org/medical/dicom/current/output/chtml/part04/sect_CC.html

**NIfTI Format:**

- **Cox RW, Ashburner J, Breman H, et al.**
   "A (sort of) new image data format standard: NIfTI-1"
   *10th Annual Meeting of the Organization for Human Brain Mapping.* 2004.
   https://nifti.nimh.nih.gov/nifti-1/
   *Key: scl_slope and scl_inter for intensity scaling*

### 9.5 iOS Development References

**Swift Concurrency:**

- **Apple Developer Documentation:**
  "Adopting Swift Concurrency"
  https://developer.apple.com/documentation/swift/adopting-swift-concurrency
  *Key: async/await patterns used in CTPresetService*

**WebKit JavaScript Bridge:**

- **Apple Developer Documentation:**
  "WKScriptMessageHandler Protocol Reference"
  https://developer.apple.com/documentation/webkit/wkscriptmessagehandler
  *Key: Swift ↔ JavaScript messaging (used in WebViewManager)*

**Performance Optimization:**

- **Apple WWDC 2021:**
  "Explore advanced project configuration in Xcode"
  Session 10210
  *Key: Build optimization for release builds*

---

## Appendix A: Example CT Urography Histogram Profiles

### A.1 Unenhanced Phase
```
Histogram: Single peak at ~40 HU (soft tissue)
  |
  |     *
  |    * *
  |   *   *
  |  *     *
  | *       *___________
  |____________________ HU
 -100  0   50  100 200 400

Percentiles: p2=10, p50=42, p98=80
Detected Phase: "unenhanced" (confidence 0.92)
Window: -100 to 600 HU (wide for stones)
```

### A.2 Corticomedullary Phase
```
Histogram: Bimodal (tissue + arterial enhancement)
  |
  |                    *
  |        *          * *
  |       * *        *   *
  |      *   *      *     *
  |_____*_____*____*_______*_____ HU
      60    110   211      280

Percentiles: p2=55, p50=115, p98=265
Detected Phase: "corticomedullary" (confidence 0.96)
Window: 135 to 285 HU (arterial peak ±75 HU)
```

### A.3 Nephrographic Phase
```
Histogram: Single peak at ~110 HU (parenchyma)
  |
  |          *
  |         * *
  |        *   *
  |       *     *
  |______*_______*_________ HU
       60  110   150  200

Percentiles: p2=68, p50=108, p98=165
Detected Phase: "nephrographic" (confidence 0.87)
Window: 68 to 165 HU (standard parenchymal)
```

### A.4 Excretory Phase
```
Histogram: Bimodal (tissue + contrast-filled collecting system)
  |
  |                      *
  |        *            * *
  |       * *          *   *
  |      *   *        *     *
  |_____*_____*______*_______*___ HU
      70    120    280     380

Percentiles: p2=65, p50=135, p98=395
Detected Phase: "excretory" (confidence 0.91)
Window: 100 to 450 HU (high contrast for collecting system)
```

---

## Appendix B: Colormap Array Format Reference

**NiiVue Colormap JSON Schema:**

```json
{
  "min": number,          // Lower HU boundary (cal_min)
  "max": number,          // Upper HU boundary (cal_max)
  "R": number[256],       // Red channel (0-255)
  "G": number[256],       // Green channel (0-255)
  "B": number[256],       // Blue channel (0-255)
  "A": number[256],       // Alpha channel (0-255)
  "I": number[256]        // Intensity index (0-255)
}
```

**Example: ct_kidneys (from NiiVue source):**

```json
{
  "min": 114,
  "max": 302,
  "R": [0, ..., 255, 255],   // 256 values: black → orange → white
  "G": [0, ..., 129, 255],   // 256 values
  "B": [0, ..., 0, 255],     // 256 values
  "A": [0, ..., 88, 228],    // 256 values: 0% → 34% → 89%
  "I": [0, 1, 2, ..., 255]   // 256 values: linear index
}
```

**Node-Based Definition (MRIcro nii_img.mm format):**

```objective-c
// CT_kidneys (case 23 in createlutX)
nodes[0] = {R:0,   G:0,   B:0,   A:0,   idx:0};      // Black, transparent
nodes[1] = {R:255, G:129, B:0,   A:88,  idx:103};    // Orange, 34% alpha
nodes[2] = {R:255, G:255, B:255, A:228, idx:256};    // White, 89% alpha
```

**Interpolation between nodes:**
```c
for (int i = nodes[n-1].idx; i < nodes[n].idx; i++) {
  float t = (i - nodes[n-1].idx) / (nodes[n].idx - nodes[n-1].idx);
  R[i] = lerp(nodes[n-1].R, nodes[n].R, t);
  G[i] = lerp(nodes[n-1].G, nodes[n].G, t);
  B[i] = lerp(nodes[n-1].B, nodes[n].B, t);
  A[i] = lerp(nodes[n-1].A, nodes[n].A, t);
}
```

---

## Appendix C: Quick Reference - Phase Detection Rules

| Phase | Primary Peak (HU) | Secondary Peak (HU) | Median (HU) | Confidence |
|-------|-------------------|---------------------|-------------|------------|
| Unenhanced | 20-70 (soft tissue) | None | <80 | 0.90 |
| Corticomedullary | >211 (arterial) | 150-250 (cortex) | >100 | 0.95 |
| Nephrographic | 80-150 (parenchyma) | None or weak | 60-120 | 0.85 |
| Excretory | 200-400 (contrast) | 60-120 (tissue) | >90 | 0.90 |
| Delayed | Multiple/broad | Variable | >100 | 0.70 |

**Detection Priority (first match wins):**
1. Arterial peak >211 HU + count >5% → Corticomedullary
2. High peak 200-400 HU + count >3% → Excretory
3. Parenchymal peak 80-150 HU + median 60-120 → Nephrographic
4. Median <80 HU + no peaks >150 HU → Unenhanced
5. Default → Delayed (low confidence)

---

## Appendix D: Performance Optimization Notes

**TypedArray Iteration:**
- Use `for (let i = 0; i < array.length; i++)` NOT `forEach` or `map`
- Reason: Direct indexing is 5-10x faster for large arrays

**Histogram Binning Optimization:**
```typescript
// FAST (single pass, no function calls)
for (let i = 0; i < img.length; i++) {
  const binIndex = Math.floor((img[i] * scl_slope + scl_inter - globalMin) / binWidth);
  bins[Math.max(0, Math.min(nBins - 1, binIndex))]++;
}

// SLOW (avoid this)
img.forEach(val => {
  const hu = intensityRaw2Scaled(volume, val);  // Function call overhead
  const binIndex = findBinIndex(hu, binEdges);  // Another function call
  bins[binIndex]++;
});
```

**Memory Allocation:**
- Preallocate all arrays before loops
- Use typed arrays when possible (e.g., `Int32Array` for bins)

**Peak Detection Smoothing:**
- Optional: 3-point moving average to reduce noise
- Trade-off: Slightly slower but more robust peak detection
- Enable for noisy data (e.g., low-dose CT)

**Parallelization Opportunities:**
- Histogram computation is embarrassingly parallel (consider Web Workers for >100M voxels)
- Not implemented in v1 (unnecessary for typical CT volumes <50M voxels)

---

## Document Revision History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-01-08 | Initial design document | NiiVue iOS Team |

---

**End of Document**

**Implementation Status:** Design Complete - Ready for Implementation
**Estimated Implementation Time:** 7 days (1 developer)
**Next Steps:** Begin Phase 1 (Core Engine) implementation in React/TypeScript layer
