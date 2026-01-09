import { describe, expect, test, vi } from 'vitest'

import { AdaptiveWindowCalculator, ColormapGenerator, CTAdaptiveEngine, HistogramAnalyzer, PhaseDetector } from './ctAdaptiveEngine'

describe('HistogramAnalyzer.compute', () => {
  test('converts raw voxels to HU using scl_slope/scl_inter and returns finite percentiles', () => {
    const volume: any = {
      img: new Int16Array([0, 1, 2, 3, 4, 5]),
      hdr: { scl_slope: 2.0, scl_inter: 10.0 }
    }

    const result = HistogramAnalyzer.compute(volume)

    expect(result.totalVoxels).toBe(6)
    expect(result.globalMin).toBe(10)
    expect(result.globalMax).toBe(20)
    expect(result.percentiles.p2).toBeGreaterThanOrEqual(result.globalMin)
    expect(result.percentiles.p98).toBeLessThanOrEqual(result.globalMax)
    expect(result.percentiles.p50).toBeCloseTo(14, 1)
  })

  test('treats scl_slope = 0 as 1.0 (invalid header protection)', () => {
    const volume: any = {
      img: new Int16Array([0, 10]),
      hdr: { scl_slope: 0.0, scl_inter: 0.0 }
    }

    const result = HistogramAnalyzer.compute(volume)
    expect(result.globalMin).toBe(0)
    expect(result.globalMax).toBe(10)
  })

  test('handles constant-valued volumes without division-by-zero', () => {
    const volume: any = {
      img: new Int16Array([5, 5, 5]),
      hdr: { scl_slope: 1.0, scl_inter: 0.0 }
    }

    const result = HistogramAnalyzer.compute(volume)

    expect(result.globalMin).toBe(5)
    expect(result.globalMax).toBe(5)
    expect(result.totalVoxels).toBe(3)
    expect(result.bins).toHaveLength(1001)
    expect(result.bins[0]).toBe(3)
    expect(result.binEdges).toHaveLength(1002)
    expect(new Set(result.binEdges).size).toBe(1)
    expect(result.percentiles).toEqual({ p2: 5, p50: 5, p98: 5 })
  })
})

describe('PhaseDetector.classify', () => {
  function histogramForTest(partial: Partial<any>): any {
    return {
      bins: new Array(1001).fill(0),
      binEdges: new Array(1002).fill(0),
      peaks: [],
      percentiles: { p2: 0, p50: 0, p98: 0 },
      globalMin: -1024,
      globalMax: 3071,
      totalVoxels: 100,
      ...partial
    }
  }

  test('classifies corticomedullary when an arterial peak >211 HU exceeds 5% voxels', () => {
    const histogram = histogramForTest({
      peaks: [{ binIndex: 1, value: 10, huValue: 250, isLocal: true }],
      totalVoxels: 100,
      percentiles: { p2: 0, p50: 110, p98: 400 }
    })

    const result = PhaseDetector.classify(histogram)
    expect(result.phase).toBe('corticomedullary')
    expect(result.confidence).toBeCloseTo(0.95, 2)
  })

  test('classifies excretory when a 200-400 HU peak exceeds 3% voxels but arterial threshold is not met', () => {
    const histogram = histogramForTest({
      peaks: [{ binIndex: 1, value: 4, huValue: 300, isLocal: true }],
      totalVoxels: 100,
      percentiles: { p2: 0, p50: 120, p98: 450 }
    })

    const result = PhaseDetector.classify(histogram)
    expect(result.phase).toBe('excretory')
    expect(result.confidence).toBeCloseTo(0.9, 2)
  })

  test('classifies nephrographic when a parenchymal peak exists and median is 60-120 HU', () => {
    const histogram = histogramForTest({
      peaks: [{ binIndex: 1, value: 50, huValue: 110, isLocal: true }],
      totalVoxels: 100,
      percentiles: { p2: 0, p50: 100, p98: 200 }
    })

    const result = PhaseDetector.classify(histogram)
    expect(result.phase).toBe('nephrographic')
    expect(result.confidence).toBeCloseTo(0.85, 2)
  })

  test('classifies unenhanced when median <80 HU and there are no peaks >150 HU', () => {
    const histogram = histogramForTest({
      peaks: [{ binIndex: 1, value: 50, huValue: 40, isLocal: true }],
      totalVoxels: 100,
      percentiles: { p2: -100, p50: 40, p98: 120 }
    })

    const result = PhaseDetector.classify(histogram)
    expect(result.phase).toBe('unenhanced')
    expect(result.confidence).toBeCloseTo(0.9, 2)
  })

  test('falls back to delayed when histogram is ambiguous', () => {
    const histogram = histogramForTest({
      peaks: [{ binIndex: 1, value: 1, huValue: 500, isLocal: true }],
      totalVoxels: 100,
      percentiles: { p2: 0, p50: 160, p98: 1000 }
    })

    const result = PhaseDetector.classify(histogram)
    expect(result.phase).toBe('delayed')
    expect(result.confidence).toBeCloseTo(0.7, 2)
  })
})

describe('AdaptiveWindowCalculator.compute', () => {
  function histogramForTest(partial: Partial<any>): any {
    return {
      peaks: [],
      percentiles: { p2: 0, p50: 0, p98: 0 },
      globalMin: -1024,
      globalMax: 3071,
      totalVoxels: 100,
      ...partial
    }
  }

  test('unenhanced window clamps to [-100, 600] using percentiles', () => {
    const histogram = histogramForTest({ percentiles: { p2: -200, p50: 0, p98: 1000 } })
    const result = AdaptiveWindowCalculator.compute({ phase: 'unenhanced', confidence: 1 }, histogram)
    expect(result.calMin).toBe(-100)
    expect(result.calMax).toBe(600)
  })

  test('corticomedullary window centers on arterial peak when available', () => {
    const histogram = histogramForTest({
      peaks: [{ binIndex: 1, value: 10, huValue: 250, isLocal: true }],
      percentiles: { p2: 0, p50: 110, p98: 400 }
    })
    const result = AdaptiveWindowCalculator.compute({ phase: 'corticomedullary', confidence: 1 }, histogram)
    expect(result.windowWidth).toBeCloseTo(150, 6)
    expect(result.calMin).toBeCloseTo(175, 6)
    expect(result.calMax).toBeCloseTo(325, 6)
  })

  test('delayed window enforces minimum width of 50 HU', () => {
    const histogram = histogramForTest({
      percentiles: { p2: 10, p50: 15, p98: 20 }
    })
    const result = AdaptiveWindowCalculator.compute({ phase: 'delayed', confidence: 1 }, histogram)
    expect(result.calMin).toBe(10)
    expect(result.calMax).toBe(60)
    expect(result.windowWidth).toBe(50)
  })

  test('invalid percentile inputs fall back to histogram globalMin/globalMax safely', () => {
    const histogram = histogramForTest({
      globalMin: 0,
      globalMax: 100,
      percentiles: { p2: Number.NaN, p50: 0, p98: Number.NaN }
    })
    const result = AdaptiveWindowCalculator.compute({ phase: 'delayed', confidence: 1 }, histogram)
    expect(result.calMin).toBe(0)
    expect(result.calMax).toBe(100)
  })
})

describe('ColormapGenerator.generate', () => {
  test('returns a 256-entry RGBA transfer function and preserves window min/max', () => {
    const window: any = { calMin: 60, calMax: 180, recommendedColormap: 'ct_kidneys', windowWidth: 120, windowLevel: 120 }
    const phase: any = { phase: 'nephrographic', confidence: 1 }

    const cmap = ColormapGenerator.generate(window, phase)

    expect(cmap.min).toBe(60)
    expect(cmap.max).toBe(180)
    expect(cmap.R).toHaveLength(256)
    expect(cmap.G).toHaveLength(256)
    expect(cmap.B).toHaveLength(256)
    expect(cmap.A).toHaveLength(256)
    expect(cmap.I).toHaveLength(256)
    expect(cmap.I[0]).toBe(0)
    expect(cmap.I[255]).toBe(255)
  })
})

describe('CTAdaptiveEngine.applyAdaptivePreset', () => {
  test('registers a custom colormap, sets cal_min/cal_max, and refreshes rendering', () => {
    const volume: any = {
      id: 'vol-1',
      img: new Int16Array([0, 1, 2, 3, 4, 5]),
      hdr: { scl_slope: 1.0, scl_inter: 0.0 }
    }

    const nv: any = {
      volumes: [volume],
      addColormap: vi.fn(),
      setColormap: vi.fn(),
      updateGLVolume: vi.fn(),
      drawScene: vi.fn()
    }

    CTAdaptiveEngine.applyAdaptivePreset(nv, 0)

    expect(nv.addColormap).toHaveBeenCalledWith('ct_urinary_adaptive', expect.any(Object))
    expect(nv.setColormap).toHaveBeenCalledWith('vol-1', 'ct_urinary_adaptive')
    expect(Number.isFinite(volume.cal_min)).toBe(true)
    expect(Number.isFinite(volume.cal_max)).toBe(true)
    expect(volume.cal_max - volume.cal_min).toBeGreaterThanOrEqual(50)
    expect(nv.updateGLVolume).toHaveBeenCalled()
    expect(nv.drawScene).toHaveBeenCalled()
  })
})
