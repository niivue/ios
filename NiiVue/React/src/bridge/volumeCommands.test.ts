import { describe, expect, it, vi } from 'vitest'

import {
  addVolumesFromUrls,
  applyViewerState,
  drawOtsu,
  exportViewerState,
  loadMeshesFromUrls,
  removeVolumeByIndex,
} from './volumeCommands'

describe('volumeCommands (Phase 2 UI extensions)', () => {
  it('addVolumesFromUrls calls niivue.addVolumesFromUrl with url+name', async () => {
    const nv: any = {
      addVolumesFromUrl: vi.fn(async () => []),
    }

    await addVolumesFromUrls(nv, [
      { url: 'niivue://app/files/a', name: 'mask-a.nii.gz' },
      { url: 'niivue://app/files/b', name: 'mask-b.nii.gz' },
    ])

    expect(nv.addVolumesFromUrl).toHaveBeenCalledWith([
      { url: 'niivue://app/files/a', name: 'mask-a.nii.gz' },
      { url: 'niivue://app/files/b', name: 'mask-b.nii.gz' },
    ])
  })

  it('loadMeshesFromUrls calls niivue.loadMeshes with url+name', async () => {
    const nv: any = {
      loadMeshes: vi.fn(async () => nv),
    }

    await loadMeshesFromUrls(nv, [
      { url: 'niivue://app/files/m1', name: 'lh.pial.gii' },
      { url: 'niivue://app/files/m2', name: 'rh.pial.gii' },
    ])

    expect(nv.loadMeshes).toHaveBeenCalledWith([
      { url: 'niivue://app/files/m1', name: 'lh.pial.gii' },
      { url: 'niivue://app/files/m2', name: 'rh.pial.gii' },
    ])
  })

  it('exportViewerState returns a stable JSON string', () => {
    const nv: any = {
      volumes: [
        { colormap: 'gray', opacity: 0.5, frame4D: 2 },
        { colormap: 'hot', opacity: 1.0 },
      ],
    }

    const json = exportViewerState(nv)
    expect(JSON.parse(json)).toEqual({
      volumes: [
        { colormap: 'gray', opacity: 0.5, frame4D: 2 },
        { colormap: 'hot', opacity: 1.0, frame4D: 0 },
      ],
    })
  })

  it('applyViewerState applies per-volume settings by index', () => {
    const nv: any = {
      volumes: [{ id: 'v1' }, { id: 'v2' }],
      setColormap: vi.fn(),
      setOpacity: vi.fn(),
      setFrame4D: vi.fn(),
    }

    applyViewerState(nv, JSON.stringify({
      volumes: [
        { colormap: 'gray', opacity: 0.5, frame4D: 2 },
        { colormap: 'hot', opacity: 1.0, frame4D: 0 },
      ],
    }))

    expect(nv.setColormap).toHaveBeenCalledWith('v1', 'gray')
    expect(nv.setOpacity).toHaveBeenCalledWith(0, 0.5)
    expect(nv.setFrame4D).toHaveBeenCalledWith('v1', 2)

    expect(nv.setColormap).toHaveBeenCalledWith('v2', 'hot')
    expect(nv.setOpacity).toHaveBeenCalledWith(1, 1.0)
    expect(nv.setFrame4D).toHaveBeenCalledWith('v2', 0)
  })

  it('removeVolumeByIndex calls niivue.removeVolumeByIndex for valid indices', () => {
    const nv: any = {
      volumes: [{ id: 'v1' }, { id: 'v2' }],
      removeVolumeByIndex: vi.fn(),
    }

    removeVolumeByIndex(nv, 1)

    expect(nv.removeVolumeByIndex).toHaveBeenCalledWith(1)
  })

  it('drawOtsu temporarily uses global_min/global_max and restores cal_min/cal_max', () => {
    const volume: any = {
      cal_min: 0,
      cal_max: 100,
      global_min: -1024,
      global_max: 3071,
    }

    const nv: any = {
      volumes: [volume],
      drawOtsu: vi.fn(() => {
        expect(volume.cal_min).toBe(volume.global_min)
        expect(volume.cal_max).toBe(volume.global_max)
      }),
    }

    drawOtsu(nv, 3)

    expect(nv.drawOtsu).toHaveBeenCalledWith(3)
    expect(volume.cal_min).toBe(0)
    expect(volume.cal_max).toBe(100)
  })
})
