import type { Niivue } from '@niivue/niivue'

import { CTAdaptiveEngine } from './ctAdaptiveEngine'
import { isIOSWebView, postToIOS } from './iosMessaging'

export function applyAdaptiveCTUrinaryPreset(nv: Niivue, volumeIndex: number): void {
  const result = CTAdaptiveEngine.applyAdaptivePreset(nv as any, volumeIndex)

  if (isIOSWebView()) {
    postToIOS('updateUI', {
      type: 'ctPresetAnalysis',
      payload: {
        phase: result.phase.phase,
        confidence: result.phase.confidence,
        calMin: result.window.calMin,
        calMax: result.window.calMax,
        windowWidth: result.window.windowWidth,
        windowLevel: result.window.windowLevel,
        colormap: 'ct_urinary_adaptive'
      }
    })
  }
}

export function listCTUrinaryPresets(): string[] {
  return ['ct_urinary_adaptive', 'ct_urinary_combined', 'ct_urinary_excretory', 'ct_urinary_stones']
}

export function applyCTUrinaryPreset(nv: Niivue, volumeIndex: number, presetName: string): void {
  const volume: any = (nv as any).volumes?.[volumeIndex]
  if (!volume) {
    throw new Error(`No volume at index ${volumeIndex}`)
  }

  switch (presetName) {
    case 'ct_urinary_adaptive':
      applyAdaptiveCTUrinaryPreset(nv, volumeIndex)
      break

    case 'ct_urinary_combined':
      applyFixedCombinedPreset(nv, volume)
      break

    case 'ct_urinary_excretory':
      applyFixedExcretoryPreset(nv, volume)
      break

    case 'ct_urinary_stones':
      applyFixedStonesPreset(nv, volume)
      break

    default:
      throw new Error(`Unknown CT urinary preset: ${presetName}`)
  }
}

function applyFixedCombinedPreset(nv: Niivue, volume: any): void {
  volume.cal_min = 100
  volume.cal_max = 300
  ;(nv as any).setColormap?.(volume.id, 'ct_kidneys')
  ;(nv as any).updateGLVolume?.()
  ;(nv as any).drawScene?.()
}

function applyFixedExcretoryPreset(nv: Niivue, volume: any): void {
  volume.cal_min = 100
  volume.cal_max = 400
  ;(nv as any).setColormap?.(volume.id, 'ct_kidneys')
  ;(nv as any).updateGLVolume?.()
  ;(nv as any).drawScene?.()
}

function applyFixedStonesPreset(nv: Niivue, volume: any): void {
  volume.cal_min = -100
  volume.cal_max = 600
  ;(nv as any).setColormap?.(volume.id, 'bone')
  ;(nv as any).updateGLVolume?.()
  ;(nv as any).drawScene?.()
}
