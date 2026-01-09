import type { NVImage } from '@niivue/niivue'

export interface Peak {
  binIndex: number
  value: number
  huValue: number
  isLocal: boolean
}

export interface HistogramResult {
  bins: number[]
  binEdges: number[]
  peaks: Peak[]
  percentiles: {
    p2: number
    p50: number
    p98: number
  }
  globalMin: number
  globalMax: number
  totalVoxels: number
}

export type CTUrographyPhase = 'unenhanced' | 'corticomedullary' | 'nephrographic' | 'excretory' | 'delayed'

export interface PhaseResult {
  phase: CTUrographyPhase
  confidence: number
  reasoning?: string
}

export interface WindowResult {
  calMin: number
  calMax: number
  recommendedColormap: string
  windowWidth: number
  windowLevel: number
}

export interface CustomColormap {
  min: number
  max: number
  R: number[]
  G: number[]
  B: number[]
  A: number[]
  I: number[]
}

export interface AdaptiveAnalysisResult {
  histogram: HistogramResult
  phase: PhaseResult
  window: WindowResult
  colormap: CustomColormap
}

export class HistogramAnalyzer {
  static compute(volume: NVImage): HistogramResult {
    if (!volume || !(volume as any).img || !(volume as any).hdr) {
      throw new Error('Invalid NVImage: missing img or hdr')
    }

    const img = (volume as any).img as ArrayLike<number>
    const hdr = (volume as any).hdr as { scl_slope?: number; scl_inter?: number }

    const sclSlope = hdr.scl_slope ?? 1.0
    const sclInter = hdr.scl_inter ?? 0.0
    const effectiveSlope = sclSlope === 0 ? 1.0 : sclSlope

    const toHU = (raw: number): number => raw * effectiveSlope + sclInter

    let globalMin = Infinity
    let globalMax = -Infinity
    let totalVoxels = 0

    for (let i = 0; i < img.length; i++) {
      const hu = toHU((img as any)[i] as number)
      if (!isFinite(hu)) continue
      if (hu < globalMin) globalMin = hu
      if (hu > globalMax) globalMax = hu
      totalVoxels++
    }

    if (totalVoxels === 0) {
      throw new Error('Invalid volume: no finite voxel values')
    }

    const nBins = 1001

    if (globalMax === globalMin) {
      const bins = new Array(nBins).fill(0)
      bins[0] = totalVoxels
      const binEdges = new Array(nBins + 1).fill(globalMin)
      return {
        bins,
        binEdges,
        peaks: [],
        percentiles: { p2: globalMin, p50: globalMin, p98: globalMin },
        globalMin,
        globalMax,
        totalVoxels
      }
    }

    const binWidth = (globalMax - globalMin) / nBins
    const bins = new Array(nBins).fill(0)

    const binEdges = new Array(nBins + 1)
    for (let i = 0; i <= nBins; i++) {
      binEdges[i] = globalMin + i * binWidth
    }

    for (let i = 0; i < img.length; i++) {
      const hu = toHU((img as any)[i] as number)
      if (!isFinite(hu)) continue
      const binIndex = Math.floor((hu - globalMin) / binWidth)
      const clampedIndex = Math.max(0, Math.min(nBins - 1, binIndex))
      bins[clampedIndex]++
    }

    const peaks: Peak[] = []
    for (let i = 1; i < nBins - 1; i++) {
      if (bins[i] > bins[i - 1] && bins[i] > bins[i + 1]) {
        const huValue = binEdges[i] + binWidth / 2
        peaks.push({ binIndex: i, value: bins[i], huValue, isLocal: true })
      }
    }

    peaks.sort((a, b) => b.value - a.value)
    const keyPeaks: Peak[] = peaks.slice(0, 5)

    const arterialCandidate = peaks.find((p) => p.huValue > 211)
    const excretoryCandidate = peaks.find((p) => p.huValue >= 200 && p.huValue <= 400)
    const nephroCandidate = peaks.find((p) => p.huValue >= 80 && p.huValue <= 150)

    for (const candidate of [arterialCandidate, excretoryCandidate, nephroCandidate]) {
      if (candidate && !keyPeaks.some((p) => p.binIndex === candidate.binIndex)) {
        keyPeaks.push(candidate)
      }
    }

    let cumSum = 0
    let p2: number | undefined
    let p50: number | undefined
    let p98: number | undefined

    const p2Target = totalVoxels * 0.02
    const p50Target = totalVoxels * 0.5
    const p98Target = totalVoxels * 0.98

    for (let i = 0; i < nBins; i++) {
      cumSum += bins[i]
      if (p2 === undefined && cumSum >= p2Target) p2 = binEdges[i]
      if (p50 === undefined && cumSum >= p50Target) p50 = binEdges[i]
      if (p98 === undefined && cumSum >= p98Target) p98 = binEdges[i]
    }

    return {
      bins,
      binEdges,
      peaks: keyPeaks,
      percentiles: {
        p2: p2 ?? globalMin,
        p50: p50 ?? globalMin,
        p98: p98 ?? globalMax
      },
      globalMin,
      globalMax,
      totalVoxels
    }
  }
}

export class PhaseDetector {
  private static readonly ARTERIAL_THRESHOLD_HU = 211
  private static readonly ARTERIAL_MIN_VOXEL_FRACTION = 0.05

  private static readonly EXCRETORY_MIN_HU = 200
  private static readonly EXCRETORY_MAX_HU = 400
  private static readonly EXCRETORY_MIN_VOXEL_FRACTION = 0.03

  private static readonly NEPHROGRAPHIC_MIN_HU = 80
  private static readonly NEPHROGRAPHIC_MAX_HU = 150
  private static readonly NEPHROGRAPHIC_MIN_MEDIAN_HU = 60
  private static readonly NEPHROGRAPHIC_MAX_MEDIAN_HU = 120

  private static readonly UNENHANCED_MAX_MEDIAN_HU = 80
  private static readonly UNENHANCED_MAX_ENHANCEMENT_HU = 150

  static classify(histogram: HistogramResult): PhaseResult {
    const { peaks, percentiles, totalVoxels } = histogram

    const arterialPeak = peaks.find((p) => p.huValue > PhaseDetector.ARTERIAL_THRESHOLD_HU)
    if (arterialPeak && arterialPeak.value > totalVoxels * PhaseDetector.ARTERIAL_MIN_VOXEL_FRACTION) {
      return {
        phase: 'corticomedullary',
        confidence: 0.95,
        reasoning:
          `Arterial peak detected at ${arterialPeak.huValue.toFixed(1)} HU ` +
          `(${((arterialPeak.value / totalVoxels) * 100).toFixed(1)}% of voxels)`
      }
    }

    const excretoryPeak = peaks.find(
      (p) => p.huValue >= PhaseDetector.EXCRETORY_MIN_HU && p.huValue <= PhaseDetector.EXCRETORY_MAX_HU
    )
    if (excretoryPeak && excretoryPeak.value > totalVoxels * PhaseDetector.EXCRETORY_MIN_VOXEL_FRACTION) {
      return {
        phase: 'excretory',
        confidence: 0.9,
        reasoning:
          `High-density peak at ${excretoryPeak.huValue.toFixed(1)} HU ` +
          `(${((excretoryPeak.value / totalVoxels) * 100).toFixed(1)}% of voxels)`
      }
    }

    const nephroPeak = peaks.find(
      (p) => p.huValue >= PhaseDetector.NEPHROGRAPHIC_MIN_HU && p.huValue <= PhaseDetector.NEPHROGRAPHIC_MAX_HU
    )
    if (
      nephroPeak &&
      percentiles.p50 >= PhaseDetector.NEPHROGRAPHIC_MIN_MEDIAN_HU &&
      percentiles.p50 <= PhaseDetector.NEPHROGRAPHIC_MAX_MEDIAN_HU
    ) {
      return {
        phase: 'nephrographic',
        confidence: 0.85,
        reasoning: `Parenchymal peak at ${nephroPeak.huValue.toFixed(1)} HU, median ${percentiles.p50.toFixed(1)} HU`
      }
    }

    if (
      percentiles.p50 < PhaseDetector.UNENHANCED_MAX_MEDIAN_HU &&
      !peaks.some((p) => p.huValue > PhaseDetector.UNENHANCED_MAX_ENHANCEMENT_HU)
    ) {
      return {
        phase: 'unenhanced',
        confidence: 0.9,
        reasoning: `Low median (${percentiles.p50.toFixed(1)} HU), no enhancement detected`
      }
    }

    return {
      phase: 'delayed',
      confidence: 0.7,
      reasoning: 'Ambiguous histogram distribution, defaulting to delayed phase'
    }
  }
}

export class AdaptiveWindowCalculator {
  static compute(phaseResult: PhaseResult, histogram: HistogramResult): WindowResult {
    const { phase } = phaseResult
    const { percentiles, peaks } = histogram

    let calMin: number
    let calMax: number
    let recommendedColormap: string

    switch (phase) {
      case 'unenhanced':
        calMin = Math.max(percentiles.p2, -100)
        calMax = Math.min(percentiles.p98, 600)
        recommendedColormap = 'ct_urinary_stones'
        break

      case 'corticomedullary': {
        const arterialPeak = peaks.find((p) => p.huValue > 211)
        if (arterialPeak) {
          const center = arterialPeak.huValue
          const width = 150
          calMin = center - width / 2
          calMax = center + width / 2
        } else {
          calMin = 150
          calMax = 300
        }
        recommendedColormap = 'ct_urinary_combined'
        break
      }

      case 'nephrographic':
        calMin = Math.max(percentiles.p2, 60)
        calMax = Math.min(percentiles.p98, 180)
        recommendedColormap = 'ct_kidneys'
        break

      case 'excretory': {
        const excretoryPeak = peaks.find((p) => p.huValue >= 200 && p.huValue <= 400)
        calMin = 100
        calMax = excretoryPeak ? Math.min(excretoryPeak.huValue + 100, 450) : 400
        recommendedColormap = 'ct_urinary_excretory'
        break
      }

      case 'delayed':
      default:
        calMin = percentiles.p2
        calMax = percentiles.p98
        recommendedColormap = 'ct_kidneys'
        break
    }

    const CT_HU_MIN = -1024
    const CT_HU_MAX = 3071

    calMin = Math.max(calMin, CT_HU_MIN)
    calMax = Math.min(calMax, CT_HU_MAX)

    const MIN_WIDTH = 50
    if (calMax - calMin < MIN_WIDTH) {
      const desiredMax = calMin + MIN_WIDTH
      if (desiredMax <= CT_HU_MAX) {
        calMax = desiredMax
      } else {
        calMax = CT_HU_MAX
        calMin = Math.max(CT_HU_MIN, calMax - MIN_WIDTH)
      }
    }

    if (!isFinite(calMin) || !isFinite(calMax) || calMax <= calMin) {
      calMin = Math.max(histogram.globalMin, CT_HU_MIN)
      calMax = Math.min(histogram.globalMax, CT_HU_MAX)

      if (!isFinite(calMin) || !isFinite(calMax) || calMax <= calMin) {
        calMin = 0
        calMax = 50
      }
    }

    return {
      calMin,
      calMax,
      recommendedColormap,
      windowWidth: calMax - calMin,
      windowLevel: (calMax + calMin) / 2
    }
  }
}

type ColorNode = { hu: number; rgb: [number, number, number] }
type AlphaNode = { hu: number; alpha: number }

export class ColormapGenerator {
  static generate(window: WindowResult, phase: PhaseResult): CustomColormap {
    const { calMin, calMax } = window

    const R = new Array<number>(256)
    const G = new Array<number>(256)
    const B = new Array<number>(256)
    const A = new Array<number>(256)
    const I = Array.from({ length: 256 }, (_, i) => i)

    let colorNodes: ColorNode[]
    let alphaNodes: AlphaNode[]

    switch (phase.phase) {
      case 'corticomedullary':
        colorNodes = [
          { hu: calMin, rgb: [0, 0, 0] },
          { hu: 150, rgb: [255, 80, 80] },
          { hu: 211, rgb: [255, 200, 200] },
          { hu: calMax, rgb: [255, 255, 255] }
        ]
        alphaNodes = [
          { hu: calMin, alpha: 0.0 },
          { hu: 150, alpha: 0.2 },
          { hu: 211, alpha: 0.8 },
          { hu: calMax, alpha: 0.95 }
        ]
        break

      case 'excretory':
        colorNodes = [
          { hu: calMin, rgb: [0, 0, 0] },
          { hu: 200, rgb: [0, 100, 200] },
          { hu: calMax, rgb: [200, 255, 255] }
        ]
        alphaNodes = [
          { hu: calMin, alpha: 0.0 },
          { hu: 150, alpha: 0.2 },
          { hu: 200, alpha: 0.7 },
          { hu: calMax, alpha: 0.95 }
        ]
        break

      case 'unenhanced':
        colorNodes = [
          { hu: calMin, rgb: [0, 0, 0] },
          { hu: 400, rgb: [255, 255, 0] },
          { hu: calMax, rgb: [255, 255, 255] }
        ]
        alphaNodes = [
          { hu: calMin, alpha: 0.0 },
          { hu: 100, alpha: 0.0 },
          { hu: 400, alpha: 0.7 },
          { hu: calMax, alpha: 0.9 }
        ]
        break

      case 'nephrographic':
      case 'delayed':
      default:
        colorNodes = [
          { hu: calMin, rgb: [0, 0, 0] },
          { hu: calMin + (calMax - calMin) * 0.4, rgb: [255, 129, 0] },
          { hu: calMax, rgb: [255, 255, 255] }
        ]
        alphaNodes = [
          { hu: calMin, alpha: 0.0 },
          { hu: calMin + (calMax - calMin) * 0.4, alpha: 0.34 },
          { hu: calMax, alpha: 0.89 }
        ]
        break
    }

    for (let i = 0; i < 256; i++) {
      const t = i / 255
      const hu = calMin + (calMax - calMin) * t

      let lowerNode = colorNodes[0]
      let upperNode = colorNodes[colorNodes.length - 1]
      for (let j = 0; j < colorNodes.length - 1; j++) {
        if (hu >= colorNodes[j].hu && hu <= colorNodes[j + 1].hu) {
          lowerNode = colorNodes[j]
          upperNode = colorNodes[j + 1]
          break
        }
      }

      const nodeRange = upperNode.hu - lowerNode.hu
      const localT = nodeRange === 0 ? 0 : (hu - lowerNode.hu) / nodeRange
      R[i] = Math.floor(lowerNode.rgb[0] + (upperNode.rgb[0] - lowerNode.rgb[0]) * localT)
      G[i] = Math.floor(lowerNode.rgb[1] + (upperNode.rgb[1] - lowerNode.rgb[1]) * localT)
      B[i] = Math.floor(lowerNode.rgb[2] + (upperNode.rgb[2] - lowerNode.rgb[2]) * localT)
    }

    for (let i = 0; i < 256; i++) {
      const t = i / 255
      const hu = calMin + (calMax - calMin) * t

      let lowerNode = alphaNodes[0]
      let upperNode = alphaNodes[alphaNodes.length - 1]
      for (let j = 0; j < alphaNodes.length - 1; j++) {
        if (hu >= alphaNodes[j].hu && hu <= alphaNodes[j + 1].hu) {
          lowerNode = alphaNodes[j]
          upperNode = alphaNodes[j + 1]
          break
        }
      }

      const nodeRange = upperNode.hu - lowerNode.hu
      const localT = nodeRange === 0 ? 0 : (hu - lowerNode.hu) / nodeRange
      const alpha = lowerNode.alpha + (upperNode.alpha - lowerNode.alpha) * localT
      A[i] = Math.floor(alpha * 255)
    }

    return { min: calMin, max: calMax, R, G, B, A, I }
  }

  static register(nv: any, name: string, colormap: CustomColormap): void {
    if (nv && typeof nv.addColormap === 'function') {
      nv.addColormap(name, colormap)
      return
    }
    // Intentionally silent: app should remain usable even if registration fails.
  }
}

export class CTAdaptiveEngine {
  static analyze(volume: NVImage): AdaptiveAnalysisResult {
    const histogram = HistogramAnalyzer.compute(volume)
    const phase = PhaseDetector.classify(histogram)
    const window = AdaptiveWindowCalculator.compute(phase, histogram)
    const colormap = ColormapGenerator.generate(window, phase)
    return { histogram, phase, window, colormap }
  }

  static applyAdaptivePreset(nv: any, volumeIndex: number): AdaptiveAnalysisResult {
    const volume = nv?.volumes?.[volumeIndex]
    if (!volume) {
      throw new Error(`No volume at index ${volumeIndex}`)
    }

    const result = CTAdaptiveEngine.analyze(volume)

    const cmapName = 'ct_urinary_adaptive'
    ColormapGenerator.register(nv, cmapName, result.colormap)

    if (typeof nv?.setColormap === 'function') {
      nv.setColormap(volume.id, cmapName)
    }

    volume.cal_min = result.window.calMin
    volume.cal_max = result.window.calMax

    nv?.updateGLVolume?.()
    nv?.drawScene?.()

    return result
  }
}
