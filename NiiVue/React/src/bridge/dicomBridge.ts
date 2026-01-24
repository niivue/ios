/**
 * DICOM bridge for iOS integration.
 * Provides manifest-based DICOM series loading through the custom niivue:// URL scheme.
 */

import { NVImage } from '@niivue/niivue'
import { dicomLoader, dicomLoaderFromBundleUrl } from './dicomLoaderMainThread'
import { logToIOS } from './iosMessaging'

type DicomInputItem = { name: string; data: ArrayBuffer | Uint8Array }

async function fetchWithOk(url: string | URL): Promise<Response> {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`Fetch failed (${response.status}): ${response.statusText}`)
  }
  return response
}

function describeError(error: unknown): string {
  if (error instanceof Error) {
    return error.stack || error.message || String(error)
  }
  if (typeof error === 'string') {
    return error
  }
  try {
    return JSON.stringify(error)
  } catch {
    return String(error)
  }
}

function parseManifestText(text: string): string[] {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
}

async function fetchDicomFilesFromManifest(
  manifestUrl: string,
  options: { concurrency: number; progressIntervalMs: number } = { concurrency: 8, progressIntervalMs: 750 }
): Promise<DicomInputItem[]> {
  const concurrency = Math.max(1, Math.floor(options.concurrency))
  const progressIntervalMs = Math.max(200, Math.floor(options.progressIntervalMs))

  const manifest = new URL(manifestUrl, window.location.href)
  const manifestResponse = await fetchWithOk(manifest)
  const manifestText = await manifestResponse.text()
  const fileNames = parseManifestText(manifestText)

  if (fileNames.length < 1) {
    throw new Error('DICOM manifest contained no filenames.')
  }

  const total = fileNames.length
  const results: DicomInputItem[] = new Array(total)
  let nextIndex = 0
  let completed = 0
  let lastProgressLog = 0

  async function worker(): Promise<void> {
    while (true) {
      const index = nextIndex
      nextIndex += 1
      if (index >= total) {
        return
      }

      const name = fileNames[index]
      const fileUrl = new URL(name, manifest)
      const response = await fetchWithOk(fileUrl)
      const data = await response.arrayBuffer()
      results[index] = { name, data }

      completed += 1
      const now = Date.now()
      if (now - lastProgressLog >= progressIntervalMs || completed === total) {
        lastProgressLog = now
        logToIOS('info', `[DICOM] Fetch progress: ${completed}/${total}`)
      }
    }
  }

  logToIOS('info', `[DICOM] Fetch start: ${total} file(s) (concurrency=${concurrency})`)
  await Promise.all(Array.from({ length: concurrency }, () => worker()))
  logToIOS('info', `[DICOM] Fetch complete: ${completed}/${total}`)
  return results
}

/**
 * Load a DICOM series from a manifest URL.
 * The manifest is a text file containing one DICOM filename per line.
 * Niivue will resolve each filename relative to the manifest URL.
 *
 * @param nv - Niivue instance
 * @param manifestUrl - URL to the manifest file (e.g., niivue://app/dicom/series1/niivue-manifest.txt)
 * @returns Promise that resolves when loading is complete
 */
export function loadDicomSeriesFromManifest(nv: any, manifestUrl: string): Promise<null> {
  // Important for iOS WKWebView bridging:
  // - `WKWebView.callAsyncJavaScript` can fail if any awaited Promise resolves to an unsupported type
  // - Niivue's built-in DICOM manifest loader fetches slices sequentially, which is too slow for large series on-device.
  //
  // We:
  // 1) Fetch the manifest + DICOM slices with bounded concurrency
  // 2) Run dcm2niix (WASM) via our custom loader
  // 3) Load the converted NIfTI bytes into Niivue
  // 4) Resolve to `null` so Swift can safely bridge the Promise.
  const start = Date.now()
  return (async (): Promise<null> => {
    const manifest = new URL(manifestUrl, window.location.href)
    const bundleUrl = new URL('bundle.bin', manifest)

    try {
      const niftiFiles = await dicomLoaderFromBundleUrl(bundleUrl.toString())
      if (!Array.isArray(niftiFiles) || niftiFiles.length < 1) {
        throw new Error('DICOM conversion succeeded but returned no NIfTI outputs.')
      }

      // Prefer the first output (typical for a CT series).
      const first = niftiFiles[0]
      if (!first?.data || !(first.data instanceof ArrayBuffer)) {
        throw new Error('Invalid NIfTI output: missing ArrayBuffer.')
      }
      const name = typeof first.name === 'string' && first.name.length > 0 ? first.name : 'dicom.nii'

      // Load from ArrayBuffer and replace current scene volumes.
      nv.closeDrawing?.()
      nv.volumes = []
      nv.updateGLVolume?.()

      const nvimage = await NVImage.loadFromUrl({ url: first.data, name })
      nv.addVolume(nvimage)
      nv.drawScene?.()

      const elapsedMs = Date.now() - start
      logToIOS('info', `[DICOM] Load (bundle) complete in ${elapsedMs}ms`)
      return null
    } catch (error) {
      logToIOS('warn', `[DICOM] Bundle loader failed; falling back to per-file fetch: ${describeError(error)}`)
    }

    const dicomFiles = await fetchDicomFilesFromManifest(manifestUrl, { concurrency: 4, progressIntervalMs: 750 })
    const niftiFiles = await dicomLoader(dicomFiles)
    if (!Array.isArray(niftiFiles) || niftiFiles.length < 1) {
      throw new Error('DICOM conversion succeeded but returned no NIfTI outputs.')
    }

    // Prefer the first output (typical for a CT series).
    const first = niftiFiles[0]
    if (!first?.data || !(first.data instanceof ArrayBuffer)) {
      throw new Error('Invalid NIfTI output: missing ArrayBuffer.')
    }
    const name = typeof first.name === 'string' && first.name.length > 0 ? first.name : 'dicom.nii'

    // Load from ArrayBuffer and replace current scene volumes.
    nv.closeDrawing?.()
    nv.volumes = []
    nv.updateGLVolume?.()

    const nvimage = await NVImage.loadFromUrl({ url: first.data, name })
    nv.addVolume(nvimage)
    nv.drawScene?.()

    const elapsedMs = Date.now() - start
    logToIOS('info', `[DICOM] Load (manifest) complete in ${elapsedMs}ms`)
    return null
  })()
}
