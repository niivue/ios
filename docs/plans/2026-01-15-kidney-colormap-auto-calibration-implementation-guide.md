# Kidney Colormap Auto-Calibration Implementation Guide

> **Version**: 1.1.0
> **Date**: January 15, 2026
> **Target Platform**: iOS 16+ / NiiVue iOS Foundation
> **Author**: Claude Code (Opus 4.5)
> **Reference Assets**: Dense V-Net Abdominal CT (NiftyNet), TotalSegmentator Color Standards

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Problem Statement](#2-problem-statement)
3. [Architecture Overview](#3-architecture-overview)
   - 3.1 System Architecture
   - 3.2 Data Flow
   - 3.3 Technology Stack
   - 3.4 **Reference Assets (Dense V-Net + TotalSegmentator)** *(NEW)*
4. [Phase 1: Algorithmic Approach](#4-phase-1-algorithmic-approach)
   - 4.6 Transfer Function Generation *(enhanced with TotalSegmentator colors)*
5. [Phase 2: Core ML Segmentation](#5-phase-2-core-ml-segmentation)
   - 5.5 **Alternative Model: Dense V-Net** *(NEW)*
6. [Integration Guide](#6-integration-guide)
   - 6.1 File Structure *(updated with reference data)*
7. [Testing Strategy](#7-testing-strategy)
   - 7.4 **Ground Truth Validation** *(NEW)*
8. [Performance Considerations](#8-performance-considerations)
9. [Appendices](#9-appendices)
   - 9.5 **Dense V-Net Reference Solution** *(NEW)*

---

## 1. Executive Summary

### Goal
Implement automatic kidney colormap calibration for CT volumes rendered in 3D, achieving optimal visualization across any CT volume regardless of scanner, protocol, or contrast phase.

### Approach
Two-phase implementation:

| Phase | Approach | Accuracy | Complexity | Timeline |
|-------|----------|----------|------------|----------|
| **Phase 1** | Pure algorithmic (GMM + entropy) | ~85-90% | Low | Immediate |
| **Phase 2** | Core ML segmentation | ~95-98% | Medium | After Phase 1 |

### Key Innovation
Unlike fixed presets (e.g., MRIcro's 114-302 HU), this system **dynamically discovers** the optimal intensity window for each volume by:

1. **Multi-modal histogram decomposition** (Gaussian Mixture Models)
2. **Gradient-based tissue boundary detection**
3. **Entropy-maximizing window optimization**
4. **ML-guided segmentation** (Phase 2)

---

## 2. Problem Statement

### The Issue
MRIcro and similar tools use **fixed HU presets** for kidney visualization:

```
CT_kidneys: darkEdit = 114, brightEdit = 302
```

This works only when:
- Volume has standard HU calibration (intercept = -1024)
- Kidney tissue falls in the expected intensity range
- Contrast phase matches the preset assumptions

### Evidence of Failure

| Volume | Intercept | Kidney Appearance | Result |
|--------|-----------|-------------------|--------|
| CT_abdomen.nii.gz | -1024 | ✅ Orange, well-defined | Preset works |
| JOAO_ANDRADE_GONCALVES | -8192 | ❌ Washed out, invisible | Preset fails |

### Root Cause
The -8192 intercept shifts all HU values by **7168 units**, causing the fixed 114-302 window to target the wrong tissue entirely.

### Solution Requirements

1. **Automatic HU normalization** - Handle non-standard intercepts
2. **Adaptive window discovery** - Find kidney tissue in any histogram
3. **Phase-aware optimization** - Adjust for contrast enhancement patterns
4. **Robust fallbacks** - Graceful degradation for edge cases

---

## 3. Architecture Overview

### System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    KIDNEY AUTO-CALIBRATION SYSTEM                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌─────────────────────┐    ┌─────────────────────┐                    │
│  │   PHASE 1           │    │   PHASE 2           │                    │
│  │   (Algorithmic)     │    │   (ML-Based)        │                    │
│  │                     │    │                     │                    │
│  │ • Histogram GMM     │    │ • Core ML Model     │                    │
│  │ • Gradient Analysis │    │ • Mask Extraction   │                    │
│  │ • Entropy Optim.    │    │ • Voxel Statistics  │                    │
│  │                     │    │                     │                    │
│  │ Accuracy: ~85-90%   │    │ Accuracy: ~95-98%   │                    │
│  │ Speed: <500ms       │    │ Speed: 3-5 sec      │                    │
│  └──────────┬──────────┘    └──────────┬──────────┘                    │
│             │                          │                                │
│             └──────────┬───────────────┘                                │
│                        ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                 UNIFIED PRESET ENGINE                            │   │
│  │                                                                  │   │
│  │ • Colormap Generation (MRIcro-style orange→white)               │   │
│  │ • Transfer Function Optimization                                 │   │
│  │ • Swift ↔ JavaScript Bridge                                      │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                        │                                                │
│                        ▼                                                │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                 NIIVUE WEBGL RENDERER                            │   │
│  │                                                                  │   │
│  │ • Custom colormap registration                                   │   │
│  │ • cal_min / cal_max application                                  │   │
│  │ • 3D volume rendering with optimized transfer function          │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Data Flow

```
CT Volume (DICOM/NIfTI)
    │
    ├─[PHASE 1]─────────────────────────────────────────────┐
    │                                                        │
    │  1. HU Conversion (scl_slope × raw + scl_inter)       │
    │  2. Spatial ROI Estimation (anatomical priors)        │
    │  3. GMM Tissue Decomposition (5-8 components)         │
    │  4. Gradient Analysis (intensity vs. gradient 2D)     │
    │  5. Entropy Window Optimization                       │
    │  6. Transfer Function Generation                      │
    │                                                        │
    └────────────────────────────────────────────────────────┤
                                                             │
    ├─[PHASE 2]─────────────────────────────────────────────┤
    │                                                        │
    │  1. Resample to 96³ (model input size)                │
    │  2. Normalize HU [-200, 400] → [0, 1]                 │
    │  3. Core ML Inference (SegResNet)                     │
    │  4. Post-process Mask (morphological ops)             │
    │  5. Extract Kidney Voxel Statistics                   │
    │  6. Compute Optimal Window from Mask                  │
    │                                                        │
    └────────────────────────────────────────────────────────┤
                                                             ▼
                                                    Optimized Colormap
                                                    (calMin, calMax, RGBA LUT)
                                                             │
                                                             ▼
                                                    3D Volume Rendering
```

### Technology Stack

| Layer | Technology | Files |
|-------|------------|-------|
| **Rendering** | NiiVue.js (WebGL) | `React/src/App.tsx` |
| **Algorithm** | TypeScript | `React/src/bridge/kidneyPresetCalculator.ts` |
| **Bridge** | WKWebView | `Web/WebViewManager.swift` |
| **ML Inference** | Core ML | `Services/KidneySegmentationService.swift` |
| **UI** | SwiftUI | `ContentView.swift` |

### Reference Assets (Dense V-Net + TotalSegmentator)

A third-party reference solution provides valuable validation data and alternative approaches:

**Location**: `/Users/leandroalmeida/MRIcro/Reference_not_included_in_project_for_working_with_development/anatomical_groups/`

| Asset | Description | Usage |
|-------|-------------|-------|
| `100_CT.nii` (6MB) | Sample abdominal CT volume | Ground truth validation |
| `100_Label.nii` (3MB) | Multi-organ segmentation labels (9 classes) | Compute actual kidney HU statistics |
| `dense_vnet_abdominal_ct_weights.tar` (10MB) | Pre-trained TensorFlow weights | Alternative model conversion |
| `anatomical_groups.py` | TotalSegmentator color mappings | Standardized kidney colors |

**Dense V-Net Model Specifications:**

| Parameter | Value |
|-----------|-------|
| Input Size | 144³ voxels |
| Architecture | Dense V-Net (NiftyNet) |
| Organs | 8 (esophagus, stomach, duodenum, pancreas, liver, gallbladder, spleen, **left kidney**) |
| Classes | 9 (8 organs + background) |
| Framework | TensorFlow 1.x |
| Loss | Dice + Hinge (class imbalance handling) |

> **Important**: Dense V-Net only segments the **left kidney**. For bilateral kidney support, prefer the SegResNet model in Phase 2 or use TotalSegmentator which includes both `kidney_left` and `kidney_right` labels.

**TotalSegmentator Kidney Colors (3DSlicer Standard):**

```python
# From TotalSegmentator / 3DSlicer extension
kidney_colors = {
    'kidney_left':  (190, 135,  85),   # Brownish-orange
    'kidney_right': (185, 135,  95),   # Similar brownish-orange
}
```

These can be used as alternative clinical colormap anchors alongside MRIcro's orange→white scheme.

---

## 4. Phase 1: Algorithmic Approach

### 4.1 Implementation Files

Create the following files in the NiiVue React project:

```
NiiVue/React/src/bridge/
├── kidneyPresetCalculator.ts      # Main calculator class
├── gaussianMixtureModel.ts        # GMM implementation
├── gradientAnalyzer.ts            # 2D histogram gradient analysis
├── entropyOptimizer.ts            # Entropy-based window optimization
├── spatialROIEstimator.ts         # Anatomical ROI estimation
└── kidneyColormapGenerator.ts     # Transfer function generation
```

### 4.2 Core Algorithm: KidneyPresetCalculator

```typescript
// kidneyPresetCalculator.ts

export class KidneyPresetCalculator {
  /**
   * Main entry point: analyzes volume and computes optimal kidney colormap
   */
  static analyze(volume: NVImage): KidneyAnalysisResult {
    // Stage 1: Global histogram analysis
    const globalHistogram = HistogramAnalyzer.compute(volume)

    // Stage 1b: Spatial ROI estimation (anatomical priors)
    const spatialROI = SpatialROIEstimator.estimate(volume)

    // Stage 1c: ROI-specific histogram
    const roiHistogram = spatialROI
      ? SpatialROIEstimator.computeROIHistogram(volume, spatialROI)
      : globalHistogram

    // Stage 2: Phase detection
    const phase = PhaseDetector.classify(roiHistogram)

    // Stage 2b: GMM tissue decomposition
    const gmm = GaussianMixtureModel.fitOptimal(roiHistogram)

    // Stage 3: Gradient analysis
    const gradientAnalysis = GradientAnalyzer.analyze(volume)

    // Stage 4a: Determine kidney HU range from all sources
    const kidneyHURange = this.determineKidneyHURange(
      phase, gmm, gradientAnalysis, roiHistogram
    )

    // Stage 4b-c: Entropy optimization
    const entropyResult = EntropyOptimizer.optimize(
      roiHistogram, kidneyHURange[0] - 20, kidneyHURange[1] + 50, kidneyHURange
    )

    // Stage 4d: Apply robust bounds
    const { calMin, calMax } = this.applyRobustBounds(
      entropyResult.optimalCalMin, entropyResult.optimalCalMax, roiHistogram
    )

    // Stage 5: Generate transfer function
    const colormap = KidneyColormapGenerator.generate(
      calMin, calMax, phase, gmm.kidneyComponent
    )

    return { /* ... result object */ }
  }
}
```

### 4.3 Gaussian Mixture Model (GMM)

The GMM decomposes the histogram into tissue components:

```typescript
// gaussianMixtureModel.ts

export class GaussianMixtureModel {
  /**
   * Fits GMM using Expectation-Maximization algorithm
   */
  static fit(histogram: HistogramResult, nComponents: number = 5): GMMResult {
    // Initialize components using k-means++ style
    const components = this.initializeComponents(samples, weights, nComponents)

    // EM iterations
    for (let iter = 0; iter < 100; iter++) {
      // E-step: compute responsibilities
      const responsibilities = this.computeResponsibilities(samples, weights, components)

      // M-step: update components
      this.updateComponents(samples, weights, responsibilities, components)

      // Check convergence
      if (Math.abs(logLikelihood - prevLogLikelihood) < 1e-6) break
    }

    // Classify tissue types based on HU ranges
    this.classifyTissueTypes(components)

    return { components, kidneyComponent, bic, logLikelihood }
  }
}
```

**Tissue Classification by HU:**

| Tissue Type | HU Range | GMM Weight Threshold |
|-------------|----------|---------------------|
| Air | < -500 | Any |
| Fat | -150 to -30 | Any |
| Water | -10 to 20 | Any |
| Kidney (unenhanced) | 20 to 60 | > 2% |
| Soft tissue | 60 to 80 | Any |
| Kidney (enhanced) | 80 to 200 | > 2% |
| Blood (enhanced) | 200 to 350 | Any |
| Contrast pooling | 350 to 600 | Any |
| Bone | > 600 | Any |

### 4.4 Gradient Analysis

2D histogram of intensity vs. gradient magnitude identifies tissue boundaries:

```typescript
// gradientAnalyzer.ts

export class GradientAnalyzer {
  static analyze(volume: NVImage): GradientHistogramResult {
    // Compute gradient magnitude at each voxel
    for (sampled voxels) {
      const gx = (toHU(img[idx + 1]) - toHU(img[idx - 1])) / 2
      const gy = (toHU(img[idx + nx]) - toHU(img[idx - nx])) / 2
      const gz = (toHU(img[idx + nx * ny]) - toHU(img[idx - nx * ny])) / 2
      const gradMag = Math.sqrt(gx² + gy² + gz²)
    }

    // Build 2D histogram: [intensity_bin][gradient_bin]
    // Low gradient = homogeneous tissue (kidney parenchyma)
    // High gradient = boundaries (kidney surface, vessels)

    return {
      histogram2D,
      homogeneousRegionHU,  // Kidney parenchyma candidate
      boundaryPeakHU        // Surface/vessel candidates
    }
  }
}
```

### 4.5 Entropy Optimization

Finds the window that maximizes information content:

```typescript
// entropyOptimizer.ts

export class EntropyOptimizer {
  static optimize(histogram, initialMin, initialMax, kidneyRange): EntropyResult {
    // Grid search with refinement
    for (calMin in searchRange) {
      for (calMax in searchRange) {
        const entropy = this.computeWindowEntropy(bins, calMin, calMax)

        // Penalize windows that clip too many voxels
        const clipPenalty = Math.pow(fractionInWindow, 0.5)

        if (entropy * clipPenalty > bestEntropy) {
          bestCalMin = calMin
          bestCalMax = calMax
        }
      }
    }

    return { optimalCalMin, optimalCalMax, entropy, iterations }
  }
}
```

### 4.6 Transfer Function Generation

MRIcro-style orange→white colormap with optional TotalSegmentator clinical standard:

```typescript
// kidneyColormapGenerator.ts

export type KidneyColormapStyle = 'mricro' | 'totalsegmentator' | 'hybrid'

export class KidneyColormapGenerator {
  /**
   * Colormap style presets from reference solutions
   */
  private static readonly PRESETS = {
    // MRIcro CT_kidneys: orange → white (original reference)
    mricro: {
      colorNodes: [
        { t: 0.0, rgb: [0, 0, 0] },
        { t: 0.4, rgb: [255, 129, 0] },    // MRIcro orange
        { t: 1.0, rgb: [255, 255, 255] }
      ],
      alphaNodes: [
        { t: 0.0, alpha: 0.0 },
        { t: 0.4, alpha: 0.34 },           // MRIcro: 88/255
        { t: 1.0, alpha: 0.89 }            // MRIcro: 228/255
      ]
    },

    // TotalSegmentator / 3DSlicer clinical standard: brownish-orange
    totalsegmentator: {
      colorNodes: [
        { t: 0.0, rgb: [0, 0, 0] },
        { t: 0.3, rgb: [95, 68, 43] },     // Dark brown (kidney shadow)
        { t: 0.6, rgb: [190, 135, 85] },   // TotalSegmentator kidney_left
        { t: 1.0, rgb: [255, 220, 180] }   // Light peach (highlight)
      ],
      alphaNodes: [
        { t: 0.0, alpha: 0.0 },
        { t: 0.3, alpha: 0.25 },
        { t: 0.6, alpha: 0.55 },
        { t: 1.0, alpha: 0.85 }
      ]
    },

    // Hybrid: MRIcro intensity curve with TotalSegmentator color anchors
    hybrid: {
      colorNodes: [
        { t: 0.0, rgb: [0, 0, 0] },
        { t: 0.35, rgb: [190, 135, 85] },  // TotalSegmentator kidney color
        { t: 0.65, rgb: [255, 170, 80] },  // Blend toward MRIcro orange
        { t: 1.0, rgb: [255, 255, 255] }
      ],
      alphaNodes: [
        { t: 0.0, alpha: 0.0 },
        { t: 0.4, alpha: 0.34 },           // MRIcro alpha curve
        { t: 1.0, alpha: 0.89 }
      ]
    }
  }

  static generate(
    calMin: number,
    calMax: number,
    phase: PhaseResult,
    kidneyComponent: GMMComponent | null,
    style: KidneyColormapStyle = 'mricro'
  ): CustomColormap {
    const preset = this.PRESETS[style]
    const { colorNodes, alphaNodes } = preset

    // Generate 256-entry LUT
    const R = new Uint8Array(256)
    const G = new Uint8Array(256)
    const B = new Uint8Array(256)
    const A = new Uint8Array(256)
    const I = new Uint8Array(256)

    for (let i = 0; i < 256; i++) {
      const t = i / 255
      R[i] = this.interpolate(colorNodes, t, 0)
      G[i] = this.interpolate(colorNodes, t, 1)
      B[i] = this.interpolate(colorNodes, t, 2)
      A[i] = Math.round(this.interpolateAlpha(alphaNodes, t) * 255)
      I[i] = i  // Identity intensity mapping
    }

    return { min: calMin, max: calMax, R, G, B, A, I }
  }

  private static interpolate(nodes: Array<{t: number, rgb: number[]}>, t: number, channel: number): number {
    // Find bounding nodes and linearly interpolate
    for (let i = 0; i < nodes.length - 1; i++) {
      if (t >= nodes[i].t && t <= nodes[i + 1].t) {
        const localT = (t - nodes[i].t) / (nodes[i + 1].t - nodes[i].t)
        return Math.round(nodes[i].rgb[channel] + localT * (nodes[i + 1].rgb[channel] - nodes[i].rgb[channel]))
      }
    }
    return nodes[nodes.length - 1].rgb[channel]
  }

  private static interpolateAlpha(nodes: Array<{t: number, alpha: number}>, t: number): number {
    for (let i = 0; i < nodes.length - 1; i++) {
      if (t >= nodes[i].t && t <= nodes[i + 1].t) {
        const localT = (t - nodes[i].t) / (nodes[i + 1].t - nodes[i].t)
        return nodes[i].alpha + localT * (nodes[i + 1].alpha - nodes[i].alpha)
      }
    }
    return nodes[nodes.length - 1].alpha
  }
}
```

**Colormap Style Comparison:**

| Style | Source | Best For | Appearance |
|-------|--------|----------|------------|
| `mricro` | MRIcro CT_kidneys | 3D volume rendering, high contrast | Black → Orange → White |
| `totalsegmentator` | 3DSlicer clinical | Multi-organ views, anatomical context | Dark brown → Brownish-orange → Peach |
| `hybrid` | Combined | Best of both: clinical colors, MRIcro contrast | Black → TotalSegmentator brown → Orange → White |

### 4.7 Integration with Existing CT Adaptive Engine

Extend `ctAdaptiveEngine.ts`:

```typescript
// Add to ctAdaptiveEngine.ts

import { KidneyPresetCalculator } from './kidneyPresetCalculator'

export class UnifiedCTPresetEngine {
  static analyzeAndApply(nv, volumeIndex, presetType = 'ct_kidney_adaptive') {
    switch (presetType) {
      case 'ct_kidney_adaptive':
        return this.applyKidneyAdaptive(nv, volumeIndex)

      case 'ct_kidney_3d_render':
        return this.applyKidney3DRender(nv, volumeIndex)

      // ... other presets
    }
  }

  private static applyKidneyAdaptive(nv, volumeIndex) {
    const kidneyResult = KidneyPresetCalculator.analyze(nv.volumes[volumeIndex])

    nv.addColormap('ct_kidney_adaptive', kidneyResult.colormap)
    nv.setColormap(volume.id, 'ct_kidney_adaptive')

    volume.cal_min = kidneyResult.calMin
    volume.cal_max = kidneyResult.calMax

    nv.updateGLVolume()
    nv.drawScene()

    return kidneyResult
  }
}

// Register bridge functions
window.applyKidneyAdaptivePreset = (volumeIndex) => {
  return UnifiedCTPresetEngine.analyzeAndApply(nv, volumeIndex, 'ct_kidney_adaptive')
}
```

### 4.8 Swift Service Extension

Extend `CTPresetService.swift`:

```swift
// CTPresetService+Kidney.swift

extension CTPresetService {
    public func applyKidneyAdaptivePreset(volumeIndex: Int) async throws -> KidneyAnalysisResult {
        let js = "window.applyKidneyAdaptivePreset(\(volumeIndex))"
        let resultJSON = try await webViewManager.evaluateJavaScript(js)
        return try decode(resultJSON)
    }

    public func listAllPresets() async throws -> [CTPresetInfo] {
        return [
            CTPresetInfo(id: "ct_kidney_adaptive", name: "Kidney Auto-Detect", ...),
            CTPresetInfo(id: "ct_kidney_3d_render", name: "Kidney 3D Render", ...),
            // ... other presets
        ]
    }
}
```

---

## 5. Phase 2: Core ML Segmentation

### 5.1 Model Conversion

Convert the MONAI SegResNet model to Core ML:

```bash
# Install dependencies
pip install coremltools torch monai

# Run conversion script
python convert_kidney_model.py
```

**convert_kidney_model.py:**

```python
import torch
import coremltools as ct
from monai.networks.nets import SegResNet

# Load PyTorch model
model = SegResNet(
    spatial_dims=3,
    in_channels=1,
    out_channels=5,  # Background + 4 kidney structures
    init_filters=32,
    blocks_down=[1, 2, 2, 4],
    blocks_up=[1, 1, 1],
    dropout_prob=0.2,
)

state_dict = torch.load("model-zoo/models/renalStructures_CECT_segmentation/models/model.pt")
model.load_state_dict(state_dict)
model.eval()

# Trace and convert
example_input = torch.randn(1, 1, 96, 96, 96)
traced_model = torch.jit.trace(model, example_input)

mlmodel = ct.convert(
    traced_model,
    inputs=[ct.TensorType(name="input_volume", shape=(1, 1, 96, 96, 96))],
    outputs=[ct.TensorType(name="segmentation_logits")],
    minimum_deployment_target=ct.target.iOS16,
    compute_precision=ct.precision.FLOAT16,
    convert_to="mlprogram"
)

mlmodel.save("KidneySegmentation.mlpackage")
```

### 5.2 Swift Segmentation Service

```swift
// KidneySegmentationService.swift

@MainActor
public final class KidneySegmentationService: ObservableObject {
    @Published public private(set) var isProcessing = false
    @Published public private(set) var processingProgress: Double = 0

    private var model: MLModel?

    public func segmentAndOptimize(
        volumeData: Data,
        dimensions: (Int, Int, Int),
        spacing: (Double, Double, Double),
        sclSlope: Double,
        sclInter: Double
    ) async throws -> SegmentationResult {

        // Stage 2a: Convert to HU
        let huVolume = convertToHU(data: volumeData, slope: sclSlope, intercept: sclInter)

        // Stage 2b: Resample to 96³
        let resampledVolume = resampleVolume(huVolume, to: (96, 96, 96))

        // Stage 2c: Normalize
        let normalizedVolume = normalizeHU(resampledVolume)  // [-200, 400] → [0, 1]

        // Stage 3: Run Core ML inference
        let segmentationMask = try await runInference(normalizedVolume)

        // Stage 3b: Post-process (morphological opening)
        let refinedMask = postProcessMask(segmentationMask)

        // Stage 4: Compute optimal window from masked voxels
        let windowResult = computeOptimalWindow(huVolume: huVolume, mask: refinedMask)

        return SegmentationResult(
            calMin: windowResult.calMin,
            calMax: windowResult.calMax,
            // ...
        )
    }
}
```

### 5.3 Model Performance

| Metric | Expected Value |
|--------|----------------|
| Model Size | ~50 MB |
| Inference Time (A16+) | 3-5 seconds |
| Kidney Parenchyma Dice | 0.89 |
| Memory Usage | ~200 MB peak |

### 5.4 Hybrid Mode

Use Phase 1 for preview, Phase 2 for final optimization:

```swift
// HybridKidneyCalibration.swift

public class HybridKidneyCalibration {
    let algorithmicService: CTPresetService
    let mlService: KidneySegmentationService

    /// Quick preview using algorithmic approach
    public func applyQuickPreview(volumeIndex: Int) async throws -> KidneyAnalysisResult {
        return try await algorithmicService.applyKidneyAdaptivePreset(volumeIndex: volumeIndex)
    }

    /// High-accuracy using ML segmentation
    public func applyMLOptimized(volumeData: Data, ...) async throws -> SegmentationResult {
        // Show Phase 1 result first for immediate feedback
        let quickResult = try await applyQuickPreview(volumeIndex: 0)

        // Then run ML in background
        let mlResult = try await mlService.segmentAndOptimize(volumeData: volumeData, ...)

        // Update with ML result when ready
        return mlResult
    }
}
```

### 5.5 Alternative Model: Dense V-Net (NiftyNet)

For environments where SegResNet is unavailable or a lighter model is preferred, the reference Dense V-Net can be converted to Core ML:

**Model Comparison:**

| Aspect | SegResNet (Primary) | Dense V-Net (Alternative) |
|--------|---------------------|---------------------------|
| Framework | MONAI (PyTorch) | NiftyNet (TensorFlow 1.x) |
| Input Size | 96³ | 144³ |
| Model Size | ~50 MB | ~10 MB |
| Kidneys | Both (bilateral) | **Left only** |
| Output Classes | 5 | 9 |
| Accuracy | Higher (Dice ~0.89) | Moderate (Dice ~0.82) |

**Conversion Script (TensorFlow → Core ML):**

```python
# convert_dense_vnet.py

import tensorflow as tf
import coremltools as ct
import numpy as np

# Load NiftyNet Dense V-Net weights
# Note: Requires NiftyNet installation and weight extraction
weights_path = "dense_vnet_abdominal_ct_weights/model.ckpt"

# Build the Dense V-Net architecture
# (Simplified - actual implementation requires NiftyNet graph reconstruction)

# Option 1: Use TensorFlow SavedModel if available
# Option 2: Use ONNX as intermediate format
#   pip install tf2onnx onnx-coreml

# Convert via ONNX (recommended for TF1.x models)
import tf2onnx
import onnx

# Export to ONNX
onnx_model, _ = tf2onnx.convert.from_saved_model(
    saved_model_path,
    input_signature=[tf.TensorSpec([1, 144, 144, 144, 1], tf.float32, name="input")]
)

# Save ONNX
onnx.save(onnx_model, "dense_vnet.onnx")

# Convert ONNX to Core ML
mlmodel = ct.converters.onnx.convert(
    model="dense_vnet.onnx",
    minimum_ios_deployment_target="16.0"
)

mlmodel.save("DenseVNetAbdominal.mlpackage")
```

> **Recommendation**: Use Dense V-Net only as a fallback or for left-kidney-only use cases. The SegResNet model provides bilateral kidney support with higher accuracy.

**Dense V-Net Label Mapping (for left kidney extraction):**

```typescript
// Label indices from Dense V-Net 9-class output
const DENSE_VNET_LABELS = {
  0: 'background',
  1: 'esophagus',
  2: 'stomach',
  3: 'duodenum',
  4: 'pancreas',
  5: 'liver',
  6: 'gallbladder',
  7: 'spleen',
  8: 'left_kidney'  // Use this for kidney window optimization
}
```

---

## 6. Integration Guide

### 6.1 File Structure

After implementation, the project structure:

```
NiiVue/
├── React/
│   └── src/
│       └── bridge/
│           ├── ctAdaptiveEngine.ts           # Extended with kidney presets
│           ├── ctUrinaryPresets.ts           # Existing
│           ├── kidneyPresetCalculator.ts     # NEW: Main calculator
│           ├── gaussianMixtureModel.ts       # NEW: GMM implementation
│           ├── gradientAnalyzer.ts           # NEW: Gradient analysis
│           ├── entropyOptimizer.ts           # NEW: Window optimization
│           ├── spatialROIEstimator.ts        # NEW: Anatomical ROI
│           ├── kidneyColormapGenerator.ts    # NEW: Transfer function
│           └── __tests__/
│               └── groundTruthValidation.test.ts  # NEW: Validation tests
│
├── NiiVue/
│   ├── Services/
│   │   ├── CTPresetService.swift             # Extended
│   │   ├── CTPresetService+Kidney.swift      # NEW: Kidney extension
│   │   └── KidneySegmentationService.swift   # NEW: Core ML service
│   │
│   ├── Web/
│   │   └── WebViewManager.swift              # Bridge updates
│   │
│   └── Resources/
│       └── KidneySegmentation.mlmodelc       # NEW: Compiled Core ML model
│
├── NiiVueTests/
│   └── GroundTruthValidationTests.swift      # NEW: Swift validation tests
│
└── docs/
    └── plans/
        └── 2026-01-15-kidney-colormap-auto-calibration-implementation-guide.md

# Reference Data (external, not in main project)
/Users/leandroalmeida/MRIcro/Reference_not_included_in_project_for_working_with_development/anatomical_groups/
├── dense_vnet_abdominal_ct_model_zoo_data/
│   ├── 100_CT.nii                            # Ground truth CT volume
│   └── 100_Label.nii                         # Ground truth segmentation labels
├── dense_vnet_abdominal_ct_weights.tar       # Alternative model weights
├── anatomical_groups.py                       # TotalSegmentator color reference
└── dense_vnet_abdominal_ct_code_config/
    ├── config.ini                             # NiftyNet configuration
    └── dice_hinge.py                          # Custom loss function reference
```

### 6.2 Step-by-Step Implementation

#### Step 1: Create TypeScript Files

1. Create `kidneyPresetCalculator.ts` with all algorithm classes
2. Export bridge functions to `window` object
3. Call `registerKidneyPresetBridge(nv)` in `App.tsx` initialization

#### Step 2: Extend Swift Services

1. Add `CTPresetService+Kidney.swift` extension
2. Update `WebViewManager` to handle new message types
3. Add UI controls in `ContentView.swift`

#### Step 3: Add Core ML Model (Phase 2)

1. Run model conversion script
2. Add `.mlpackage` to Xcode project
3. Implement `KidneySegmentationService.swift`

#### Step 4: Update UI

Add preset selector to CT Presets sheet:

```swift
// In ContentView.swift

Picker("CT Preset", selection: $selectedPreset) {
    Text("🎯 Kidney Auto-Detect").tag("ct_kidney_adaptive")
    Text("🧊 Kidney 3D Render").tag("ct_kidney_3d_render")
    Text("🔄 Urinary Auto-Detect").tag("ct_urinary_adaptive")
    // ...
}
.onChange(of: selectedPreset) { newValue in
    Task {
        try await ctPresetService.applyPreset(volumeIndex: 0, presetId: newValue)
    }
}
```

### 6.3 API Reference

#### TypeScript API

```typescript
// Apply kidney-optimized preset
window.applyKidneyAdaptivePreset(volumeIndex: number): ExtendedAnalysisResult

// Apply 3D rendering optimized preset
window.applyKidney3DRenderPreset(volumeIndex: number): ExtendedAnalysisResult

// Get detailed analysis without applying
window.getKidneyAnalysisDetails(volumeIndex: number): KidneyAnalysisResult

// List all available presets
window.listCTPresets(): CTPresetType[]

// Apply any preset by ID
window.applyCTPreset(volumeIndex: number, preset: string): ExtendedAnalysisResult
```

#### Swift API

```swift
// CTPresetService
func applyKidneyAdaptivePreset(volumeIndex: Int) async throws -> KidneyAnalysisResult
func applyKidney3DRenderPreset(volumeIndex: Int) async throws -> KidneyAnalysisResult
func getKidneyAnalysisDetails(volumeIndex: Int) async throws -> KidneyAnalysisResult
func listAllPresets() async throws -> [CTPresetInfo]
func applyPreset(volumeIndex: Int, presetId: String) async throws -> KidneyAnalysisResult

// KidneySegmentationService (Phase 2)
func segmentAndOptimize(volumeData: Data, dimensions: (Int, Int, Int), ...) async throws -> SegmentationResult
```

---

## 7. Testing Strategy

### 7.1 Unit Tests

```typescript
// kidneyPresetCalculator.test.ts

describe('KidneyPresetCalculator', () => {
  describe('GMM fitting', () => {
    it('should identify kidney component in enhanced CT', () => {
      const histogram = createMockHistogram({
        peaks: [{ hu: 40, weight: 0.3 }, { hu: 120, weight: 0.15 }]
      })
      const gmm = GaussianMixtureModel.fitOptimal(histogram)

      expect(gmm.kidneyComponent).toBeDefined()
      expect(gmm.kidneyComponent?.tissueType).toBe('kidney_enhanced')
    })

    it('should handle non-standard intercept', () => {
      const volume = createMockVolume({ sclInter: -8192 })
      const result = KidneyPresetCalculator.analyze(volume)

      expect(result.calMin).toBeGreaterThan(-200)
      expect(result.calMax).toBeLessThan(500)
    })
  })

  describe('Entropy optimization', () => {
    it('should maximize entropy within kidney HU range', () => {
      const histogram = createMockHistogram({ /* ... */ })
      const result = EntropyOptimizer.optimize(histogram, 50, 250, [80, 180])

      expect(result.entropy).toBeGreaterThan(5)  // Good entropy
      expect(result.optimalCalMin).toBeGreaterThanOrEqual(50)
      expect(result.optimalCalMax).toBeLessThanOrEqual(250)
    })
  })
})
```

### 7.2 Integration Tests

```swift
// KidneyPresetIntegrationTests.swift

class KidneyPresetIntegrationTests: XCTestCase {
    func testApplyKidneyAdaptivePreset() async throws {
        let webViewManager = WebViewManager()
        let service = CTPresetService(webViewManager: webViewManager)

        // Load test volume
        try await webViewManager.loadVolume(url: testVolumeURL)

        // Apply preset
        let result = try await service.applyKidneyAdaptivePreset(volumeIndex: 0)

        // Verify window is in reasonable range for kidney
        XCTAssertGreaterThan(result.calMin, -200)
        XCTAssertLessThan(result.calMax, 500)
        XCTAssertGreaterThan(result.windowWidth, 100)
        XCTAssertGreaterThan(result.confidence, 0.5)
    }
}
```

### 7.3 Visual Validation

Manual testing checklist:

- [ ] CT_abdomen.nii.gz: Kidneys visible, orange color
- [ ] JOAO_ANDRADE_GONCALVES DICOM: Kidneys visible (previously failed)
- [ ] Unenhanced CT: Kidneys subtly visible
- [ ] Arterial phase CT: Cortex brighter than medulla
- [ ] Excretory phase CT: Collecting system bright
- [ ] Different scanner vendors: Siemens, GE, Philips

### 7.4 Ground Truth Validation (Dense V-Net Reference Data)

Use the provided labeled CT volume to validate algorithm accuracy against known kidney locations:

**Reference Data Location:**
```
/Users/leandroalmeida/MRIcro/Reference_not_included_in_project_for_working_with_development/anatomical_groups/dense_vnet_abdominal_ct_model_zoo_data/
├── 100_CT.nii       # Input CT volume (6MB)
└── 100_Label.nii    # Ground truth labels (3MB)
```

**Ground Truth Validation Test (TypeScript):**

```typescript
// groundTruthValidation.test.ts

import * as nifti from 'nifti-reader-js'
import { KidneyPresetCalculator } from './kidneyPresetCalculator'

const DENSE_VNET_KIDNEY_LABEL = 8  // left_kidney in Dense V-Net output

describe('Ground Truth Validation', () => {
  let ctVolume: NVImage
  let labelVolume: Int16Array
  let groundTruthKidneyStats: { mean: number; std: number; min: number; max: number }

  beforeAll(async () => {
    // Load reference CT and labels
    ctVolume = await loadNifti('100_CT.nii')
    labelVolume = await loadNiftiLabels('100_Label.nii')

    // Extract ground truth kidney voxel statistics
    groundTruthKidneyStats = computeKidneyStatsFromLabels(
      ctVolume, labelVolume, DENSE_VNET_KIDNEY_LABEL
    )
  })

  it('should detect kidney HU range within ground truth bounds', () => {
    const result = KidneyPresetCalculator.analyze(ctVolume)

    // Computed calMin should be close to actual kidney min HU
    expect(result.calMin).toBeGreaterThanOrEqual(groundTruthKidneyStats.min - 30)
    expect(result.calMin).toBeLessThanOrEqual(groundTruthKidneyStats.mean - groundTruthKidneyStats.std)

    // Computed calMax should capture most kidney tissue
    expect(result.calMax).toBeGreaterThanOrEqual(groundTruthKidneyStats.mean + groundTruthKidneyStats.std)
    expect(result.calMax).toBeLessThanOrEqual(groundTruthKidneyStats.max + 50)
  })

  it('should achieve >80% kidney voxel coverage in window', () => {
    const result = KidneyPresetCalculator.analyze(ctVolume)

    // Count kidney voxels within computed window
    let inWindow = 0
    let totalKidney = 0

    for (let i = 0; i < labelVolume.length; i++) {
      if (labelVolume[i] === DENSE_VNET_KIDNEY_LABEL) {
        totalKidney++
        const huValue = ctVolume.toHU(i)
        if (huValue >= result.calMin && huValue <= result.calMax) {
          inWindow++
        }
      }
    }

    const coverage = inWindow / totalKidney
    expect(coverage).toBeGreaterThan(0.8)
  })

  it('should identify correct GMM component as kidney', () => {
    const result = KidneyPresetCalculator.analyze(ctVolume)

    // GMM kidney component mean should be within 1 std of ground truth mean
    expect(result.gmmResult.kidneyComponent?.mean).toBeGreaterThan(
      groundTruthKidneyStats.mean - groundTruthKidneyStats.std * 1.5
    )
    expect(result.gmmResult.kidneyComponent?.mean).toBeLessThan(
      groundTruthKidneyStats.mean + groundTruthKidneyStats.std * 1.5
    )
  })
})

function computeKidneyStatsFromLabels(
  ct: NVImage,
  labels: Int16Array,
  kidneyLabel: number
): { mean: number; std: number; min: number; max: number } {
  const kidneyHUs: number[] = []

  for (let i = 0; i < labels.length; i++) {
    if (labels[i] === kidneyLabel) {
      kidneyHUs.push(ct.toHU(i))
    }
  }

  const mean = kidneyHUs.reduce((a, b) => a + b, 0) / kidneyHUs.length
  const std = Math.sqrt(
    kidneyHUs.reduce((acc, hu) => acc + Math.pow(hu - mean, 2), 0) / kidneyHUs.length
  )

  return {
    mean,
    std,
    min: Math.min(...kidneyHUs),
    max: Math.max(...kidneyHUs)
  }
}
```

**Swift Integration Test with Ground Truth:**

```swift
// GroundTruthValidationTests.swift

class GroundTruthValidationTests: XCTestCase {
    private let referenceDataPath = "/Users/leandroalmeida/MRIcro/Reference_not_included_in_project_for_working_with_development/anatomical_groups/dense_vnet_abdominal_ct_model_zoo_data"

    func testKidneyDetectionAgainstGroundTruth() async throws {
        let ctURL = URL(fileURLWithPath: "\(referenceDataPath)/100_CT.nii")
        let labelURL = URL(fileURLWithPath: "\(referenceDataPath)/100_Label.nii")

        // Load ground truth statistics
        let groundTruthStats = try await computeGroundTruthKidneyStats(
            ctURL: ctURL,
            labelURL: labelURL,
            kidneyLabel: 8  // Dense V-Net left_kidney
        )

        // Run our algorithm
        let webViewManager = WebViewManager()
        try await webViewManager.loadVolume(url: ctURL)
        let result = try await CTPresetService(webViewManager: webViewManager)
            .applyKidneyAdaptivePreset(volumeIndex: 0)

        // Validate against ground truth
        XCTAssertGreaterThan(result.calMin, groundTruthStats.min - 30,
            "calMin should be close to ground truth minimum")
        XCTAssertLessThan(result.calMax, groundTruthStats.max + 50,
            "calMax should not exceed ground truth maximum by much")

        // Window should capture most kidney tissue
        let coverage = computeWindowCoverage(
            ctURL: ctURL,
            labelURL: labelURL,
            calMin: result.calMin,
            calMax: result.calMax,
            kidneyLabel: 8
        )
        XCTAssertGreaterThan(coverage, 0.8,
            "At least 80% of kidney voxels should be within computed window")
    }
}
```

**Expected Ground Truth Statistics for `100_CT.nii`:**

| Metric | Expected Value | Notes |
|--------|----------------|-------|
| Kidney voxel count | ~15,000-25,000 | Left kidney only |
| Mean HU | ~80-120 | Depends on contrast phase |
| Std HU | ~30-50 | Parenchyma variation |
| Min HU | ~30-50 | Medulla/cortex junction |
| Max HU | ~150-200 | Enhanced cortex |

---

## 8. Performance Considerations

### 8.1 Phase 1 Performance

| Operation | Time Complexity | Typical Duration |
|-----------|-----------------|------------------|
| Histogram computation | O(n) | 50-100 ms |
| GMM fitting | O(k × n × i) | 100-200 ms |
| Gradient analysis | O(n/64) sampled | 100-150 ms |
| Entropy optimization | O(grid²) | 50-100 ms |
| **Total** | - | **300-550 ms** |

Where:
- n = number of voxels (~50-100 million)
- k = number of GMM components (5-8)
- i = EM iterations (~50-100)

### 8.2 Phase 2 Performance

| Operation | Time (A16+ Neural Engine) |
|-----------|---------------------------|
| Resampling to 96³ | ~200 ms |
| Core ML inference | 2-4 seconds |
| Mask post-processing | ~100 ms |
| Window computation | ~50 ms |
| **Total** | **3-5 seconds** |

### 8.3 Optimization Tips

1. **Voxel sampling**: For histogram/gradient, sample every 4-8 voxels
2. **ROI focus**: Use spatial priors to reduce analysis region
3. **Caching**: Cache GMM results for same volume
4. **Background processing**: Run Phase 2 asynchronously
5. **Progressive disclosure**: Show Phase 1 immediately, refine with Phase 2

---

## 9. Appendices

### 9.1 HU Reference Values

| Tissue | HU Range | Notes |
|--------|----------|-------|
| Air | -1000 | Reference |
| Lung | -700 to -600 | |
| Fat | -120 to -80 | |
| Water | 0 | Reference |
| Kidney (unenhanced) | 20-50 | |
| Kidney (enhanced) | 80-200 | Depends on phase |
| Blood | 35-55 | |
| Blood (enhanced) | 150-300 | |
| Muscle | 35-55 | |
| Bone (cortical) | 1000+ | |

### 9.2 MRIcro CT_kidneys Reference

From MRIcro source code (`nii_img.mm`):

```objc
case 23: //CT_kidneys
    numNodes = 3;
    nodes[1] = makeRGBAnode(255,129,0,88,103);   // Orange, alpha=88, at 40%
    nodes[2] = makeRGBAnode(255,255,255,228,256); // White, alpha=228, at 100%
    break;

// Window values (nii_WindowController.m):
if (idx == 23) {//CT_kidneys
    darkEdit.doubleValue = 114;
    brightEdit.doubleValue = 302;
}
```

### 9.3 Troubleshooting

**Issue: Kidneys not visible after applying preset**

1. Check `scl_slope` and `scl_inter` in NIfTI header
2. Verify HU calculation: `HU = raw × slope + intercept`
3. Ensure intercept is reasonable (-1024 is standard)
4. Check confidence score - low confidence may indicate unusual volume

**Issue: Colors inverted or incorrect**

1. Verify colormap registration succeeded
2. Check `cal_min < cal_max`
3. Ensure volume ID matches applied colormap

**Issue: Performance degradation**

1. Reduce sampling rate in gradient analysis
2. Limit GMM components to 5
3. Use smaller entropy optimization grid
4. Consider async processing for Phase 2

### 9.4 References

1. MRIcro GitHub: https://github.com/neurolabusc/MRIcro
2. NiiVue GitHub: https://github.com/niivue/niivue
3. MONAI Model Zoo: https://monai.io/model-zoo.html
4. Core ML Documentation: https://developer.apple.com/documentation/coreml
5. Hounsfield Scale: https://radiopaedia.org/articles/hounsfield-unit
6. Dense V-Net Paper: Gibson et al. (2018) "Automatic multi-organ segmentation on abdominal CT with dense v-networks" https://doi.org/10.1109/TMI.2018.2806309
7. TotalSegmentator: https://github.com/wasserth/TotalSegmentator
8. NiftyNet: https://github.com/NifTK/NiftyNet
9. 3DSlicer TotalSegmentator Extension: https://github.com/lassoan/SlicerTotalSegmentator

### 9.5 Dense V-Net Reference Solution

This section documents the third-party Dense V-Net solution used for ground truth validation and alternative model development.

**Source Publication:**
> Eli Gibson, Francesco Giganti, Yipeng Hu, Ester Bonmati, Steve Bandula, Kurinchi Gurusamy, Brian Davidson, Stephen P. Pereira, Matthew J. Clarkson and Dean C. Barratt (2017), "Automatic multi-organ segmentation on abdominal CT with dense v-networks", IEEE Transactions on Medical Imaging, https://doi.org/10.1109/TMI.2018.2806309

**Model Architecture:**

Dense V-Net is a 3D fully convolutional network that combines:
- Dense feature stacking (inspired by DenseNet)
- V-Net encoder-decoder structure
- Skip connections for multi-resolution features

**NiftyNet Configuration (from `config.ini`):**

```ini
[ct]
spatial_window_size = (144, 144, 144)
interp_order = 1
axcodes = (A, R, S)

[NETWORK]
name = dense_vnet
batch_size = 6

[SEGMENTATION]
num_classes = 9
```

**Label Mapping (9 classes):**

| Label ID | Organ | Clinical Relevance |
|----------|-------|-------------------|
| 0 | Background | N/A |
| 1 | Esophagus | GI tract |
| 2 | Stomach | GI tract |
| 3 | Duodenum | GI tract |
| 4 | Pancreas | Adjacent organ |
| 5 | Liver | Adjacent organ |
| 6 | Gallbladder | Adjacent organ |
| 7 | Spleen | Adjacent organ |
| 8 | **Left Kidney** | **Target organ** |

**Dice + Hinge Loss Function:**

The model uses a custom loss that combines Dice loss with hinge penalties to handle class imbalance:

```python
# From dice_hinge.py
def dice(prediction, ground_truth, weight_map=None):
    dice_numerator = 2.0 * tf.sparse_reduce_sum(one_hot * prediction, reduction_axes=[0])
    dice_denominator = tf.reduce_sum(tf.square(prediction)) + tf.sparse_reduce_sum(one_hot)

    dice_score = dice_numerator / (dice_denominator + epsilon)

    # Hinge penalties for low-scoring classes
    h1 = tf.square(tf.minimum(0.1, dice_score) * 10 - 1)
    h2 = tf.square(tf.minimum(0.01, dice_score) * 100 - 1)

    return 1.0 - tf.reduce_mean(dice_score) + tf.reduce_mean(h1) * 10 + tf.reduce_mean(h2) * 10
```

This loss helps prevent the model from ignoring small organs (like kidneys) in favor of larger organs (like liver).

**TotalSegmentator Color Standards (PyVista Integration):**

From `anatomical_groups.py`, the TotalSegmentator color scheme provides clinically-recognized organ colors:

```python
# Kidney colors from TotalSegmentator / 3DSlicer
names_to_colors = {
    'kidney_left':  (190, 135, 85),   # Brownish-orange
    'kidney_right': (185, 135, 95),   # Similar brownish-orange
    # Additional organs for context
    'liver':        (150, 100, 70),
    'spleen':       (160, 80, 60),
    'pancreas':     (255, 180, 100),
}

# Filter labels by anatomical group
def filter_labels(label_names, search_terms):
    return [label for label in label_names if any(term in label for term in search_terms)]

# Kidney-related filter
kidney_terms = ['kidney']
kidney_labels = filter_labels(all_labels, kidney_terms)
# Returns: ['kidney_left', 'kidney_right']
```

**Preprocessing Requirements:**

For optimal Dense V-Net performance, input CT must be:
1. Cropped to rib-cage and abdominal cavity
2. In Hounsfield units
3. Voxels outside FOV set to -1000
4. Resampled to 144³ with appropriate spacing

**Limitations:**

- Only segments **left kidney** (not bilateral)
- Requires TensorFlow 1.x (legacy)
- Higher memory requirements (144³ vs 96³)
- No fine-grained kidney structure segmentation (no cortex/medulla/pelvis)

---

## Changelog

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-15 | Initial implementation guide |
| 1.1.0 | 2026-01-15 | Added Dense V-Net reference solution: ground truth validation (7.4), alternative model (5.5), TotalSegmentator colors (4.6), reference assets (3.4), appendix (9.5) |

---

**End of Document**
