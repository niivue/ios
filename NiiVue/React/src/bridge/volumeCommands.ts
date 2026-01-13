/**
 * Phase 2 Task 3: Volume colormap and opacity commands
 *
 * These functions bridge Swift to Niivue volume controls.
 * Volume operations use index (position in volumes array) for opacity
 * and ID (UUID) for colormap, following Niivue's API conventions.
 */

import { Niivue } from '@niivue/niivue'

/**
 * Set the colormap for a volume by index
 * @param nv - The Niivue instance
 * @param volumeIndex - Index of the volume in nv.volumes
 * @param colormap - Name of the colormap (e.g., "gray", "hot", "red")
 */
export function setColormap(nv: Niivue, volumeIndex: number, colormap: string): void {
  const volume = nv.volumes[volumeIndex]
  if (!volume) {
    console.warn(`[volumeCommands] No volume at index ${volumeIndex}`)
    return
  }
  nv.setColormap(volume.id, colormap)
}

/**
 * Set the opacity for a volume by index
 * @param nv - The Niivue instance
 * @param volumeIndex - Index of the volume in nv.volumes
 * @param opacity - Opacity value (0.0 to 1.0)
 */
export function setOpacity(nv: Niivue, volumeIndex: number, opacity: number): void {
  nv.setOpacity(volumeIndex, opacity)
}

/**
 * Get the list of available colormaps
 * @param nv - The Niivue instance
 * @returns Array of colormap names
 */
export function listColormaps(nv: Niivue): string[] {
  return nv.colormaps()
}

/**
 * Phase 2 Task 4: Set the 4D frame for a volume by index
 * @param nv - The Niivue instance
 * @param volumeIndex - Index of the volume in nv.volumes
 * @param frame - Frame number to display (0-indexed)
 */
export function setFrame4D(nv: Niivue, volumeIndex: number, frame: number): void {
  const volume = nv.volumes[volumeIndex]
  if (!volume) {
    console.warn(`[volumeCommands] No volume at index ${volumeIndex}`)
    return
  }
  nv.setFrame4D(volume.id, frame)
}

// Phase 2 Task 5: Segmentation/Draw Tooling Pack

/**
 * Undo the last drawing operation
 * @param nv - The Niivue instance
 */
export function drawUndo(nv: Niivue): void {
  nv.drawUndo()
}

/**
 * Set the opacity for drawings
 * @param nv - The Niivue instance
 * @param opacity - Opacity value (0.0 to 1.0)
 */
export function setDrawOpacity(nv: Niivue, opacity: number): void {
  nv.setDrawOpacity(opacity)
}

/**
 * Set the colormap for drawings
 * @param nv - The Niivue instance
 * @param colormap - Name of the colormap
 */
export function setDrawColormap(nv: Niivue, colormap: string): void {
  nv.setDrawColormap(colormap)
}

/**
 * Enable or disable click-to-segment mode
 * @param nv - The Niivue instance
 * @param enabled - Whether click-to-segment is enabled
 */
export function setClickToSegmentEnabled(nv: Niivue, enabled: boolean): void {
  nv.opts.clickToSegment = enabled
}

/**
 * Apply Otsu thresholding to the drawing bitmap.
 *
 * Note: Niivue's internal `findOtsu` uses `volume.cal_min/cal_max` as histogram bounds.
 * When CT presets/windowing narrow this range, Otsu can become unstable or produce empty masks.
 * To make segmentation robust, temporarily widen the histogram bounds to `global_min/global_max`.
 *
 * @param nv - The Niivue instance
 * @param levels - (2-4) number of classes to segment into
 */
export function drawOtsu(nv: Niivue, levels: number): void {
  const volume = (nv.volumes as any[] | undefined)?.[0]
  if (!volume) {
    console.warn('[volumeCommands] drawOtsu skipped: no volumes loaded')
    return
  }

  const originalCalMin = volume.cal_min
  const originalCalMax = volume.cal_max
  const globalMin = volume.global_min
  const globalMax = volume.global_max

  try {
    if (typeof globalMin === 'number' && typeof globalMax === 'number') {
      volume.cal_min = globalMin
      volume.cal_max = globalMax
    }
    nv.drawOtsu(levels)
  } finally {
    volume.cal_min = originalCalMin
    volume.cal_max = originalCalMax
  }
}

/**
 * Remove a volume from the viewer by index.
 * @param nv - The Niivue instance
 * @param volumeIndex - Index of the volume in nv.volumes
 */
export function removeVolumeByIndex(nv: Niivue, volumeIndex: number): void {
  if (volumeIndex < 0 || volumeIndex >= nv.volumes.length) {
    console.warn(`[volumeCommands] No volume at index ${volumeIndex}`)
    return
  }
  const anyNv = nv as any
  if (typeof anyNv.removeVolumeByIndex !== 'function') {
    console.warn('[volumeCommands] removeVolumeByIndex not available on Niivue instance')
    return
  }
  anyNv.removeVolumeByIndex(volumeIndex)
}

// Phase 2 UI: Import + Sessions helpers

export type UrlNamedItem = {
  url: string
  name: string
}

/**
 * Build a niivue:// URL for a preprocessed volume served by the native app.
 *
 * Path format:
 * `niivue://app/preprocessed/<studyID>/<itemID>/<parametersHash>/preprocessed.nii(.gz)`
 */
export function buildPreprocessedVolumeUrl(
  studyID: string,
  itemID: string,
  parametersHash: string,
  fileName: string = 'preprocessed.nii'
): string {
  return `niivue://app/preprocessed/${studyID}/${itemID}/${parametersHash}/${fileName}`
}

/**
 * Add volumes (e.g., label masks / overlay textures) without clearing existing volumes.
 * @param nv - The Niivue instance
 * @param volumes - Array of {url, name}
 */
export async function addVolumesFromUrls(nv: Niivue, volumes: UrlNamedItem[]): Promise<void> {
  await nv.addVolumesFromUrl(volumes as any)
}

/**
 * Load meshes from URLs.
 * @param nv - The Niivue instance
 * @param meshes - Array of {url, name}
 */
export async function loadMeshesFromUrls(nv: Niivue, meshes: UrlNamedItem[]): Promise<void> {
  await nv.loadMeshes(meshes as any)
}

/**
 * Export a thin viewer state snapshot that can be persisted on iOS.
 * Avoids nv.json() because it can include large encoded image blobs.
 */
export function exportViewerState(nv: Niivue): string {
  const volumes = (nv.volumes as any[]).map((v) => ({
    colormap: v.colormap,
    opacity: v.opacity,
    frame4D: v.frame4D ?? 0,
  }))

  return JSON.stringify({ volumes })
}

export type ViewerStateVolume = {
  colormap?: string
  opacity?: number
  frame4D?: number
}

export type ViewerStateSnapshot = {
  volumes: ViewerStateVolume[]
}

/**
 * Apply a viewer state snapshot (previously exported with `exportViewerState`) to the current viewer.
 * This does not load volumes; it only updates per-volume settings for currently loaded volumes.
 */
export function applyViewerState(nv: Niivue, json: string): void {
  let parsed: any
  try {
    parsed = JSON.parse(json)
  } catch (error) {
    console.warn('[volumeCommands] Failed to parse viewer state JSON', error)
    return
  }

  const snapshot = parsed as ViewerStateSnapshot
  if (!snapshot || !Array.isArray(snapshot.volumes)) {
    console.warn('[volumeCommands] Invalid viewer state JSON shape')
    return
  }

  snapshot.volumes.forEach((state, index) => {
    const volume = (nv.volumes as any[])[index]
    if (!volume || !state) return

    if (typeof state.colormap === 'string') {
      setColormap(nv, index, state.colormap)
    }
    if (typeof state.opacity === 'number') {
      setOpacity(nv, index, state.opacity)
    }
    if (typeof state.frame4D === 'number') {
      setFrame4D(nv, index, state.frame4D)
    }
  })
}
