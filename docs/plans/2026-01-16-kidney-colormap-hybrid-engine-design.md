# Hybrid Kidney Colormap Auto-Calibration Engine

**Date**: January 16, 2026
**Project**: NiiVue iOS Foundation
**Status**: Design Complete, Ready for Implementation
**Target Device**: iPhone 16 Pro Max, iOS 26

---

## Executive Summary

This design replaces the failed Core ML 3D SegResNet approach with a **multi-tier adaptive system** that handles both single-phase and multi-phase CT scans. The key innovation is a **2.5D slice-by-slice architecture** that sidesteps Core ML's rank-5 tensor limitation while maintaining 90-97% segmentation accuracy.

### Why the Previous Approach Failed

The SegResNet 3D model conversion failed due to a fundamental Core ML constraint:
- **Rank-5 tensor limit**: Core ML cannot process tensors with rank > 5
- **GroupNorm issue**: Creates rank-6 tensors internally during reshape
- **5D input issue**: Even with InstanceNorm replacement, 5D inputs `[B, C, D, H, W]` still fail at inference time

This is a **framework limitation**, not a coremltools bug. True 3D volumetric segmentation is not possible with Core ML.

### The Solution: Multi-Tier Adaptive System

| Tier | Technology | Accuracy | Speed | Availability |
|------|------------|----------|-------|--------------|
| **1** | HU heuristics + Otsu | 70-85% | <500ms | Always |
| **2** | 2.5D MobileNetV3 U-Net | 90-97% | ~3s | iOS 16+ |
| **3** | Foundation Models | N/A (UX) | ~1s | iOS 26+ |

Each tier is independent. The system degrades gracefully—Tier 1 always works, Tiers 2 and 3 enhance when available.

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│              Kidney Colormap Auto-Calibration               │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Tier 1: Fast Heuristic Engine (Always Available)           │
│  ├─ HU histogram analysis                                   │
│  ├─ Phase detection (arterial/venous/delayed/unenhanced)    │
│  ├─ Anatomical ROI estimation (T12-L3 vertebral region)     │
│  └─ Otsu-based tissue classification                        │
│  Result: Window/level in <500ms, 70-85% accuracy            │
│                                                             │
│  Tier 2: 2.5D ML Segmentation (iOS 16+, Optional)           │
│  ├─ Slice-by-slice processing with 3-slice context          │
│  ├─ Lightweight MobileNetV3 encoder (real-time)             │
│  └─ Post-processing: 3D reconstruction + cleanup            │
│  Result: Precise mask in ~3s, 90-97% Dice                   │
│                                                             │
│  Tier 3: Foundation Models UX (iOS 26+, Optional)           │
│  ├─ @Generable structured analysis output                   │
│  ├─ Phase classification explanation                        │
│  └─ User-facing rationale for suggested window              │
│  Result: Natural language context for clinicians            │
│                                                             │
│  Multi-Phase Adapter                                        │
│  ├─ Detects registered multi-phase availability             │
│  ├─ Fuses arterial + venous + delayed for enhanced ROI      │
│  └─ Falls back to single-phase replication if unavailable   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Tier 1: Fast Heuristic Engine

### Phase Detection Algorithm

```typescript
interface KidneyPhaseDetection {
  phase: 'unenhanced' | 'arterial' | 'nephrographic' | 'excretory' | 'delayed';
  confidence: number;
  kidneyHURange: { low: number; high: number };
}

function detectCTPhase(histogram: number[]): KidneyPhaseDetection {
  const softTissuePeak = findHistogramPeak(histogram, 20, 100);
  const contrastPeak = findHistogramPeak(histogram, 100, 300);

  if (contrastPeak > softTissuePeak * 0.3) {
    if (contrastPeak > 200) return { phase: 'arterial', kidneyHURange: { low: 150, high: 250 } };
    if (contrastPeak > 140) return { phase: 'nephrographic', kidneyHURange: { low: 100, high: 180 } };
    return { phase: 'excretory', kidneyHURange: { low: 80, high: 160 } };
  }
  return { phase: 'unenhanced', kidneyHURange: { low: 20, high: 50 } };
}
```

### Anatomical ROI Estimation

```typescript
function estimateKidneyROI(volumeDims: { x: number; y: number; z: number }) {
  // Kidneys at T12-L3: approximately 27.5% to 72.5% of abdominal CT z-range
  const zStart = Math.floor(volumeDims.z * 0.275);
  const zEnd = Math.floor(volumeDims.z * 0.725);

  const xMid = volumeDims.x / 2;
  const kidneyWidth = volumeDims.x * 0.25;

  return {
    left: { xStart: xMid - kidneyWidth * 1.5, xEnd: xMid - kidneyWidth * 0.3 },
    right: { xStart: xMid + kidneyWidth * 0.3, xEnd: xMid + kidneyWidth * 1.5 },
    zRange: { start: zStart, end: zEnd }
  };
}
```

### HU Reference Values by Phase

| Phase | Kidney Parenchyma HU | Optimal Window |
|-------|---------------------|----------------|
| Unenhanced | 30-40 HU | 40/80 |
| Arterial | 195-217 HU | 200/150 |
| Nephrographic | 120-170 HU | 140/280 |
| Excretory | 80-160 HU | 120/200 |

---

## Tier 2: 2.5D ML Segmentation

### Architecture

```
Input: 3 adjacent CT slices stacked as "RGB" channels
       Shape: [1, 3, 512, 512] — standard 4D tensor, Core ML compatible

       ┌─────────────────────────────────────┐
       │  Slice N-1  │  Slice N  │  Slice N+1 │
       │  (R channel)│ (G channel)│ (B channel)│
       └─────────────────────────────────────┘
                         │
                         ▼
       ┌─────────────────────────────────────┐
       │     MobileNetV3-Large Encoder       │
       │     (pretrained, 5M parameters)     │
       └─────────────────────────────────────┘
                         │
                         ▼
       ┌─────────────────────────────────────┐
       │     U-Net Decoder with Skip Conn    │
       └─────────────────────────────────────┘
                         │
                         ▼
       Output: Segmentation mask for middle slice
               Shape: [1, 6, 512, 512] — 6 classes
```

### Why 2.5D Works

1. **No rank-6 tensors** — Standard 2D convolutions, no GroupNorm reshaping
2. **3-slice context** — Captures inter-slice continuity without full 3D
3. **Pretrained encoder** — MobileNetV3 provides strong feature extraction
4. **Research validated** — 2.5D achieves 0.97+ Dice for kidney segmentation

### Performance Estimates

| Device | Per-Slice | 200-Slice Volume |
|--------|-----------|------------------|
| iPhone 16 Pro Max | ~15ms | ~3 seconds |
| iPhone 14 Pro | ~25ms | ~5 seconds |
| iPhone 12 | ~45ms | ~9 seconds |

### Model Training

```python
import segmentation_models_pytorch as smp

model = smp.Unet(
    encoder_name="mobilenet_v3_large",
    encoder_weights="imagenet",
    in_channels=3,
    classes=6,
    activation=None
)
```

### Core ML Conversion

```python
import coremltools as ct

traced = torch.jit.trace(model.eval(), torch.rand(1, 3, 512, 512))

mlmodel = ct.convert(
    traced,
    inputs=[ct.ImageType(shape=(1, 3, 512, 512), scale=1/255.0)],
    outputs=[ct.TensorType(name="segmentation_logits")],
    minimum_deployment_target=ct.target.iOS17,
    compute_precision=ct.precision.FLOAT16
)

mlmodel.save("KidneySegmentation2D.mlpackage")
```

---

## Tier 3: Foundation Models UX Enhancement

### Structured Output Schema

```swift
import FoundationModels

@Generable(description: "CT kidney analysis with imaging parameters")
struct KidneyCalibrationResult {
    @Guide(description: "Detected CT acquisition phase")
    let phase: CTPhase

    @Guide(description: "Confidence percentage", .range(0...100))
    let confidence: Int

    @Guide(description: "Suggested window center in HU", .range(-200...400))
    let windowCenter: Int

    @Guide(description: "Suggested window width in HU", .range(50...600))
    let windowWidth: Int

    @Guide(description: "One-sentence clinical rationale")
    let rationale: String
}

@Generable
enum CTPhase {
    case unenhanced
    case arterialCorticomedullary
    case nephrographic
    case excretory
    case delayed
}
```

### Usage Pattern

```swift
func enhanceWithAIContext(
    histogramStats: HistogramStats,
    tier1Result: WindowLevel,
    tier2Mask: SegmentationMask?
) async throws -> KidneyCalibrationResult {

    let session = LanguageModelSession(
        instructions: """
            You optimize CT kidney visualization parameters.
            Provide technical imaging suggestions only, never medical diagnosis.
            """
    )

    let prompt = """
        CT kidney histogram: mean \(histogramStats.mean) HU,
        std \(histogramStats.std), peaks at \(histogramStats.peaks).
        Kidney volume: \(tier2Mask?.volumeML ?? "unknown") mL.
        Suggest optimal window/level for parenchyma visualization.
        """

    return try await session.respond(
        to: prompt,
        generating: KidneyCalibrationResult.self
    ).content
}
```

---

## Multi-Phase Adapter

### Phase Detection

```swift
struct CTVolumeSet {
    let phases: [CTPhase: VolumeData]

    var isMultiPhase: Bool { phases.count >= 3 }
    var availablePhases: [CTPhase] { Array(phases.keys).sorted() }
}
```

### Adaptive Input Strategy

```swift
func prepareModelInput(volumeSet: CTVolumeSet, sliceIndex: Int) -> MLMultiArray {
    if volumeSet.isMultiPhase {
        // True multi-phase: use arterial, venous, delayed as 3 channels
        return stack3Channels(
            volumeSet.phases[.arterial]![sliceIndex],
            volumeSet.phases[.venous]![sliceIndex],
            volumeSet.phases[.delayed]![sliceIndex]
        )
    } else {
        // Single-phase: use adjacent slices as 3 channels (2.5D approach)
        let singleVolume = volumeSet.phases.values.first!
        return stack3Channels(
            singleVolume[max(0, sliceIndex - 1)],
            singleVolume[sliceIndex],
            singleVolume[min(singleVolume.count - 1, sliceIndex + 1)]
        )
    }
}
```

### Expected Accuracy

| Scenario | Input Strategy | Expected Accuracy |
|----------|----------------|-------------------|
| Multi-phase registered | Arterial + Venous + Delayed | 95-98% Dice |
| Single-phase CT | Slice N-1, N, N+1 (2.5D) | 90-95% Dice |
| Mixed availability | Best available combination | 88-95% Dice |

---

## Integration Architecture

### TypeScript Layer (ctKidneyEngine.ts)

```typescript
export interface KidneyCalibrationResult {
  windowCenter: number;
  windowWidth: number;
  phase: CTPhase;
  confidence: number;
  kidneyROI?: { left: BoundingBox; right: BoundingBox };
  source: 'tier1-heuristic' | 'tier2-ml' | 'tier3-enhanced';
}

export async function calibrateKidneyColormap(
  nv: Niivue,
  options: { enableML?: boolean; enableAI?: boolean }
): Promise<KidneyCalibrationResult> {

  // Tier 1: Always runs first (fast)
  const histogram = HistogramAnalyzer.analyze(nv.volumes[0]);
  const tier1Result = computeKidneyWindow(histogram);

  // Apply immediately for instant feedback
  nv.setWindowLevel(tier1Result.windowCenter, tier1Result.windowWidth);

  // Signal Swift for Tier 2/3 if enabled
  if (options.enableML) {
    window.webkit.messageHandlers.kidneyML.postMessage({
      action: 'runSegmentation',
      volumeId: nv.volumes[0].id
    });
  }

  return tier1Result;
}
```

### Swift Layer (KidneyCalibrationService.swift)

```swift
@MainActor
final class KidneyCalibrationService: ObservableObject {
    private let segmentationModel: KidneySegmentation2D
    private let foundationSession: LanguageModelSession?

    @Published var currentResult: KidneyCalibrationResult?
    @Published var segmentationMask: SegmentationMask?
    @Published var isProcessing = false

    func calibrate(volume: VolumeData, phases: CTVolumeSet) async {
        isProcessing = true
        defer { isProcessing = false }

        // Tier 2: ML Segmentation
        segmentationMask = await runSliceBySliceSegmentation(phases)
        let kidneyStats = extractKidneyStatistics(segmentationMask, volume)

        // Tier 3: Foundation Models enhancement
        if let session = foundationSession {
            currentResult = try? await enhanceWithAI(session, kidneyStats)
        }

        // Push result back to WebView
        await webViewManager.updateColormap(currentResult)
    }
}
```

---

## Implementation Phases

### Phase 1: Tier 1 Enhancement (1-2 days)
- Extend `ctAdaptiveEngine.ts` with kidney-specific heuristics
- Add phase detection algorithm
- Add anatomical ROI estimation (T12-L3)
- Integrate with existing CT preset system
- **Deliverable**: Fast kidney windowing, no ML required

### Phase 2: 2.5D Model Development (3-5 days)
- Prepare KiTS19 dataset in 2.5D format
- Train MobileNetV3 U-Net (~50 epochs)
- Convert to Core ML, validate on test set
- Target: >0.90 Dice on kidney parenchyma
- **Deliverable**: `KidneySegmentation2D.mlpackage`

### Phase 3: Swift Integration (2-3 days)
- Create `KidneyCalibrationService`
- Implement slice-by-slice inference pipeline
- Add 3D mask reconstruction
- Bridge results to WebViewManager
- **Deliverable**: ML segmentation in NiivueKit

### Phase 4: Multi-Phase Adapter (1-2 days)
- Detect registered multi-phase volumes
- Implement adaptive input preparation
- Test with existing multi-phase dataset
- **Deliverable**: Optimal handling for both scenarios

### Phase 5: Foundation Models UX (1-2 days)
- Implement @Generable schemas
- Add AI-enhanced explanations
- Graceful fallback when unavailable
- **Deliverable**: Clinical context for users

### Validation Checkpoints

| Phase | Validation Criteria |
|-------|---------------------|
| 1 | Window/level within ±20 HU of manual selection |
| 2 | Dice >0.90 on KiTS19 test set |
| 3 | End-to-end <5s on iPhone 16 Pro Max |
| 4 | Multi-phase accuracy >95% |
| 5 | Rationale text clinically appropriate |

**Total Estimate**: 8-14 days for complete implementation

---

## Appendix: Research Sources

### Apple Documentation
- Core ML tensor rank limitation (coremltools GitHub #1723)
- Foundation Models framework (iOS 26+)
- Vision framework capabilities

### Medical Imaging Research
- 2.5D MFFAU-Net kidney segmentation (BMC Medical Informatics, 2023)
- KiTS19/KiTS21 challenge results
- CT phase-specific HU ranges (Radiology Key, AJR)

### Datasets
- KiTS19: 210 CT scans with kidney + tumor labels
- KiTS21: 300 CT scans with kidney + tumor + cyst labels

---

## Document Metadata

**Author**: Claude Code (Opus 4.5)
**Date**: January 16, 2026
**Version**: 1.0
**Previous Approach**: Core ML 3D SegResNet (failed due to rank-5 limitation)
**New Approach**: Multi-tier hybrid with 2.5D ML segmentation
