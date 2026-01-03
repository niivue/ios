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
