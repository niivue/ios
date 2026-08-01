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

/**
 * Sentinel for work abandoned because the viewer was torn down. The host checks
 * for it so a teardown is not reported to the user as a bad file.
 */
export const TEARDOWN_ERROR = 'niivue-bridge: viewer torn down'

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
  loadImageURL(url: string, fileName: string): Promise<boolean>
  saveDrawing(): Promise<string>
  setCrosshairColor(): void
  setSliceType(sliceType: number): void
  setLayout(layout: number): void
  setCrosshairVisible(visible: boolean): void
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
    // Naming a backend matters: with `backend` unset, attachToCanvas tries WebGPU,
    // fails, and swaps in a fresh canvas to fall back. Asking for 'webgpu'
    // explicitly lets the constructor's enforceBackendAvailability() downgrade to
    // 'webgl2' up front when navigator.gpu is absent — as it is in WKWebView today
    // — so no failed init and no canvas swap. WebGPU is still used where present.
    backend: 'webgpu',
    // Start in the state the SwiftUI toggles default to. Note that the crosshair
    // is deliberately left at its 1.0 default of visible — see setCrosshairVisible.
    isOrientCubeVisible: false,
    // Always show the 3D render tile alongside the 2D planes in multiplanar
    // views (the pre-1.0 `multiplanarForceRender` option).
    showRender: SHOW_RENDER.ALWAYS,
    // `primaryDragMode` is the LEFT/one-finger drag, `secondaryDragMode` the
    // right drag. NiiVue 1.0 defaults primary to `crosshair` (drag moves the
    // crosshair) and secondary to `contrast`; keep that — 0.41's single
    // `dragMode` defaulted to contrast, which is not the same gesture model.
    primaryDragMode: DRAG_MODE.crosshair,
  })
  // Every operation that touches the volume or the drawing runs on this single
  // chain. Loads alone are not enough: a save reads the volume, so a load that
  // interleaved with saveVolume/gzip would export the wrong image.
  let volumeQueue: Promise<void> = Promise.resolve()
  let destroyed = false
  /** Newest requested load. Older queued loads compare against it and drop. */
  let loadGeneration = 0

  /** Queue `job`, keeping the chain alive if it rejects. Rejects to the caller. */
  function enqueue<T>(job: () => Promise<T>): Promise<T> {
    const run = volumeQueue.then(() => {
      // Work queued before teardown must not run against a destroyed controller.
      if (destroyed) throw new Error(TEARDOWN_ERROR)
      return job()
    })
    volumeQueue = run.then(
      () => {},
      () => {},
    )
    return run
  }

  const onLocationChange = (e: CustomEvent<NiiVueLocation>): void => {
    postToHost('locationChange', JSON.stringify(e.detail.mm))
  }
  nv.addEventListener('locationChange', onLocationChange)

  const destroy = (): void => {
    // Set first: anything still queued sees this and bails instead of mutating a
    // destroyed controller or holding its payload alive.
    destroyed = true
    nv.removeEventListener('locationChange', onLocationChange)
    nv.destroy()
  }

  try {
    await nv.attachToCanvas(canvas)
  } catch (error) {
    // Both graphics backends failed. NiiVue paints GRAPHICS_UNAVAILABLE_MESSAGE on
    // the canvas, but destroy() clears it again, so without this the host sees a
    // black rectangle and every later command is silently dropped.
    postToHost('updateUI', `error: ${error instanceof Error ? error.message : String(error)}`)
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
    async loadImageURL(url, fileName) {
      // Keep rapid selections ordered: NiiVue replaces its volume only after the
      // new file has been prepared, so overlapping calls can otherwise finish in
      // the opposite order from the user's selections.
      loadGeneration += 1
      const generation = loadGeneration
      return enqueue(async () => {
        // A newer pick arrived while this one waited. Return before fetching:
        // the URL transport keeps stale requests from allocating another source
        // buffer, and the native handler can stop serving a superseded task.
        if (generation !== loadGeneration) return false
        // Load BEFORE closing the drawing. loadVolumes throws on a file NiiVue
        // cannot parse, and closing first would destroy the user's drawing over
        // a volume that then stays on screen — silent data loss on a bad pick.
        await nv.loadVolumes([{ url, name: fileName }])
        // A newer request or teardown may have arrived while the source was
        // loading. Do not commit the old request's drawing mutation.
        if (destroyed || generation !== loadGeneration) return false
        // The drawing belonged to the volume just replaced; its dimensions need
        // not match the new one, so it goes only once the swap has succeeded.
        nv.closeDrawing()
        postToHost('logMessage', `loaded ${fileName}`)
        return true
      })
    },

    async saveDrawing() {
      // On the queue, not merely after it: the export reads the current volume
      // and drawing, so a load must not swap them out mid-save. This also
      // serialises repeated save taps.
      return enqueue(async () => {
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
        const zipped = await gzip(img)
        if (destroyed) throw new Error(TEARDOWN_ERROR)
        return bytesToBase64(zipped)
      })
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

    /**
     * NiiVue 1.0 has a single crosshair renderer for both the in-plane 2D cross
     * and the 3D cross, gated entirely on `is3DCrosshairVisible` (see
     * NVViewGL.draw: `tile.space !== 'global3d' && md.ui.is3DCrosshairVisible`).
     * `crosshairWidth` is only the cylinder radius. So unlike 0.41.1, 2D and 3D
     * crosshair visibility cannot be controlled separately — hence one toggle.
     */
    setCrosshairVisible(visible) {
      nv.is3DCrosshairVisible = visible
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

  // `npm run dev` has no native host, and loadImageURL is the native-only import
  // path — so the page would just sit on the placeholder.
  // Load the app's sample volume instead (dev only; never in the shipped build,
  // where the host supplies the image and this file is not served).
  if (import.meta.env.DEV && !window.webkit) {
    nv.loadVolumes([{ url: `${import.meta.env.BASE_URL}T1w_DEMO.nii.gz` }]).catch(
      (err: unknown) => console.warn('dev sample volume failed to load', err),
    )
  }

  return () => {
    destroy()
    if (window.niivueBridge === bridge) {
      delete window.niivueBridge
    }
  }
}
