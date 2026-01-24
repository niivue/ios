import { describe, expect, test, vi } from 'vitest'

import { applyCTUrinaryPreset, listCTUrinaryPresets } from './ctUrinaryPresets'

describe('ctUrinaryPresets', () => {
  test('applyCTUrinaryPreset posts ctPresetAnalysis via updateUI when running inside iOS WKWebView', () => {
    const volume: any = {
      id: 'v1',
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

    const previousWebkit = (window as any).webkit
    const postMessage = vi.fn()
    ;(window as any).webkit = {
      messageHandlers: {
        updateUI: { postMessage }
      }
    }

    try {
      applyCTUrinaryPreset(nv, 0, 'ct_urinary_adaptive')
    } finally {
      ;(window as any).webkit = previousWebkit
    }

    expect(postMessage).toHaveBeenCalled()
    const json = String(postMessage.mock.calls[0]?.[0] ?? '')
    expect(json).toContain('"type":"ctPresetAnalysis"')
    expect(json).toContain('"phase"')
    expect(json).toContain('"calMin"')
    expect(json).toContain('"calMax"')
    expect(json).toContain('"colormap":"ct_urinary_adaptive"')
  })

  test('listCTUrinaryPresets returns a stable preset list', () => {
    expect(listCTUrinaryPresets()).toEqual([
      'ct_urinary_adaptive',
      'ct_urinary_combined',
      'ct_urinary_excretory',
      'ct_urinary_stones'
    ])
  })

  test('applyCTUrinaryPreset applies fixed stones preset (bone, -100..600)', () => {
    const volume: any = { id: 'v1' }
    const nv: any = {
      volumes: [volume],
      setColormap: vi.fn(),
      updateGLVolume: vi.fn(),
      drawScene: vi.fn()
    }

    applyCTUrinaryPreset(nv, 0, 'ct_urinary_stones')

    expect(volume.cal_min).toBe(-100)
    expect(volume.cal_max).toBe(600)
    expect(nv.setColormap).toHaveBeenCalledWith('v1', 'bone')
    expect(nv.updateGLVolume).toHaveBeenCalled()
    expect(nv.drawScene).toHaveBeenCalled()
  })

  test('applyCTUrinaryPreset applies fixed combined preset (ct_kidneys, 100..300)', () => {
    const volume: any = { id: 'v1' }
    const nv: any = {
      volumes: [volume],
      setColormap: vi.fn(),
      updateGLVolume: vi.fn(),
      drawScene: vi.fn()
    }

    applyCTUrinaryPreset(nv, 0, 'ct_urinary_combined')

    expect(volume.cal_min).toBe(100)
    expect(volume.cal_max).toBe(300)
    expect(nv.setColormap).toHaveBeenCalledWith('v1', 'ct_kidneys')
    expect(nv.updateGLVolume).toHaveBeenCalled()
    expect(nv.drawScene).toHaveBeenCalled()
  })

  test('applyCTUrinaryPreset applies fixed excretory preset (ct_kidneys, 100..400)', () => {
    const volume: any = { id: 'v1' }
    const nv: any = {
      volumes: [volume],
      setColormap: vi.fn(),
      updateGLVolume: vi.fn(),
      drawScene: vi.fn()
    }

    applyCTUrinaryPreset(nv, 0, 'ct_urinary_excretory')

    expect(volume.cal_min).toBe(100)
    expect(volume.cal_max).toBe(400)
    expect(nv.setColormap).toHaveBeenCalledWith('v1', 'ct_kidneys')
    expect(nv.updateGLVolume).toHaveBeenCalled()
    expect(nv.drawScene).toHaveBeenCalled()
  })

  test('applyCTUrinaryPreset applies adaptive preset via CTAdaptiveEngine pipeline', () => {
    const volume: any = {
      id: 'v1',
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

    applyCTUrinaryPreset(nv, 0, 'ct_urinary_adaptive')

    expect(nv.setColormap).toHaveBeenCalledWith('v1', 'ct_urinary_adaptive')
    expect(nv.addColormap).toHaveBeenCalledWith('ct_urinary_adaptive', expect.any(Object))
  })

  test('applyCTUrinaryPreset throws on unknown preset', () => {
    const nv: any = { volumes: [{ id: 'v1' }] }
    expect(() => applyCTUrinaryPreset(nv, 0, 'nope')).toThrow(/Unknown CT urinary preset/)
  })
})
