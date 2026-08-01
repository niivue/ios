/**
 * Bridge between the SwiftUI host and NiiVue.
 *
 * The native side drives the viewer with `webView.evaluateJavaScript(...)` /
 * `callAsyncJavaScript(...)` against the `window.niivueBridge` functions
 * installed here, and receives events back through
 * `window.webkit.messageHandlers.*`.
 */
import {
  DRAG_MODE,
  type NiiVueLocation,
  NiiVue,
  SHOW_RENDER,
} from '@niivue/niivue'

/** Message handler names registered by `WebViewManager` on the Swift side. */
type HostChannel = 'updateUI' | 'logMessage' | 'locationChange'

declare global {
  interface Window {
    niivueBridge?: NiiVueBridge
    webkit?: {
      messageHandlers?: Partial<
        Record<HostChannel, { postMessage: (message: string) => void }>
      >
    }
  }
}

/** Post to the native host. A no-op in a plain browser (`npm run dev`). */
function postToHost(channel: HostChannel, message: string): void {
  window.webkit?.messageHandlers?.[channel]?.postMessage(message)
}

function base64ToBytes(base64: string): Uint8Array<ArrayBuffer> {
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes
}

/**
 * gzip in JS rather than via `saveVolume({ filename: 'x.nii.gz' })`: a non-empty
 * filename makes NiiVue trigger a browser download instead of handing back the
 * bytes, and the host expects a `.nii.gz` payload it can write itself.
 */
async function gzip(bytes: Uint8Array): Promise<Uint8Array> {
  const stream = new Blob([bytes as BlobPart])
    .stream()
    .pipeThrough(new CompressionStream('gzip'))
  return new Uint8Array(await new Response(stream).arrayBuffer())
}

function bytesToBase64(bytes: Uint8Array): string {
  // Chunked so the spread never exceeds the JS argument limit on big volumes.
  const CHUNK = 0x8000
  let binary = ''
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK))
  }
  return btoa(binary)
}

export interface NiiVueBridge {
  loadBase64Image(base64: string, fileName: string): Promise<void>
  saveDrawing(): Promise<string>
  setCrosshairColor(): void
  setSliceType(sliceType: number): void
  setLayout(layout: number): void
  set3dCrosshairVisible(visible: boolean): void
  set2dCrosshairVisible(visible: boolean): void
  setOrientationText(visible: boolean): void
  setOrientationCube(visible: boolean): void
  setRadiological(isRadiological: boolean): void
  setDragMode(dragMode: number): void
  setPenValue(value: number, isFilled: boolean, drawingEnabled: boolean): void
  moveCrosshairInVox(x: number, y: number, z: number): void
}

/**
 * Attach NiiVue to `canvas`, install the host bridge on `window`, and tell the
 * native side the viewer is ready. Returns a teardown for React strict mode.
 */
export async function startNiiVue(
  canvas: HTMLCanvasElement,
  isCancelled: () => boolean = () => false,
): Promise<() => void> {
  const nv = new NiiVue({
    // 'debug' also paints a backend badge across the top of the canvas, so keep
    // the shipped app quieter.
    logLevel: 'warn',
    placeholderText: 'Loading…',
    backgroundColor: [0, 0, 0, 1],
    // WKWebView does not expose WebGPU today. NiiVue would fall back on its own,
    // but only after a failed init that swaps the canvas element; asking for the
    // backend we can actually get skips that on every launch. Where WebGPU does
    // appear, this picks it up automatically.
    backend: 'gpu' in navigator ? 'webgpu' : 'webgl2',
    // Start in the state the SwiftUI toggles default to (1.0 turns the
    // orientation cube and the 3D crosshair on by default; the app does not).
    isOrientCubeVisible: false,
    is3DCrosshairVisible: false,
    // Always show the 3D render tile alongside the 2D planes in multiplanar
    // views (the pre-1.0 `multiplanarForceRender` option).
    showRender: SHOW_RENDER.ALWAYS,
    // Matches the drag behaviour the iOS UI exposes by default.
    primaryDragMode: DRAG_MODE.contrast,
  })
  let volumeLoadQueue: Promise<void> = Promise.resolve()

  const onLocationChange = (e: CustomEvent<NiiVueLocation>): void => {
    postToHost('locationChange', JSON.stringify(e.detail.mm))
  }
  nv.addEventListener('locationChange', onLocationChange)

  const destroy = (): void => {
    nv.removeEventListener('locationChange', onLocationChange)
    nv.destroy()
  }

  try {
    await nv.attachToCanvas(canvas)
  } catch (error) {
    destroy()
    throw error
  }

  // React StrictMode can tear down an effect while attachToCanvas is pending.
  // Do not publish a bridge for a controller that is already obsolete.
  if (isCancelled()) {
    destroy()
    return () => {}
  }

  const bridge: NiiVueBridge = {
    async loadBase64Image(base64, fileName) {
      // Keep rapid selections ordered: NiiVue replaces its volume only after
      // the new file has been prepared, so overlapping calls can otherwise
      // finish in the opposite order from the user's selections.
      const load = volumeLoadQueue.then(async () => {
        // The name matters: NiiVue infers the reader from the file extension.
        const file = new File([base64ToBytes(base64)], fileName)
        nv.closeDrawing()
        await nv.loadVolumes([{ url: file, name: fileName }])
        postToHost('logMessage', `loaded ${fileName}`)
      })
      volumeLoadQueue = load.catch(() => {})
      await load
    },

    async saveDrawing() {
      await volumeLoadQueue
      // An empty filename makes saveVolume return the bytes instead of
      // triggering a browser download.
      const img = await nv.saveVolume({
        filename: '',
        isSaveDrawing: true,
        volumeByIndex: 0,
      })
      if (!(img instanceof Uint8Array)) {
        return ''
      }
      return bytesToBase64(await gzip(img))
    },

    setCrosshairColor() {
      nv.crosshairColor = [0, 1, 0, 0.5]
    },

    setSliceType(sliceType) {
      nv.sliceType = sliceType
    },

    setLayout(layout) {
      nv.multiplanarType = layout
    },

    set3dCrosshairVisible(visible) {
      nv.is3DCrosshairVisible = visible
    },

    set2dCrosshairVisible(visible) {
      nv.crosshairWidth = visible ? 1 : 0
    },

    setOrientationText(visible) {
      nv.isOrientationTextVisible = visible
    },

    setOrientationCube(visible) {
      nv.isOrientCubeVisible = visible
    },

    setRadiological(isRadiological) {
      nv.isRadiological = isRadiological
    },

    setDragMode(dragMode) {
      nv.primaryDragMode = dragMode
    },

    setPenValue(value, isFilled, drawingEnabled) {
      // 1.0 no longer creates the drawing bitmap implicitly; without one the
      // pen is inert.
      if (drawingEnabled && !nv.drawingVolume) {
        nv.createEmptyDrawing()
      }
      nv.drawIsEnabled = drawingEnabled
      nv.drawPenValue = value
      nv.drawPenFilled = isFilled
      nv.drawPenAutoClose = isFilled
    },

    moveCrosshairInVox(x, y, z) {
      nv.moveCrosshairInVox(x, y, z)
    },
  }

  window.niivueBridge = bridge
  postToHost('updateUI', 'ready')

  return () => {
    destroy()
    if (window.niivueBridge === bridge) {
      delete window.niivueBridge
    }
  }
}
