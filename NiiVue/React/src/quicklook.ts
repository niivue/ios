/**
 * Quick Look preview page.
 *
 * Separate from `bridge.ts` on purpose. The app's bridge is a two-way control
 * surface — drawing, saving, settings, twelve setters. A preview is read-only
 * and single-shot: the host hands over one request, the page reports back once,
 * and nothing else is ever driven from outside. Sharing `bridge.ts` here would
 * mean shipping the drawing and export paths into an extension that must not
 * have them.
 *
 * Milestone 4 scope: voxel previews. NIfTI, MGH/MGZ, NRRD and MetaImage load
 * through one path — every NiiVue volume reader normalizes into a NIfTI header
 * — into a fixed 2×2 layout, with sanitized header metadata in the strip.
 * Meshes and tracts are Milestone 5.
 */
import {
  NiiVue,
  SHOW_RENDER,
  SLICE_TYPE,
  type CustomLayoutTile,
  type NVImage,
} from '@niivue/niivue'
import { describeVolume } from './preview-metadata'

/** Native → page. One request per preview; the host never sends a second. */
export interface PreviewRequest {
  /** Opaque same-origin route to the document. Only this page can resolve it. */
  url: string
  displayName: string
  /** Bytes on disk, for the metadata strip. */
  fileSize?: number
  /** Which NiiVue loader the file needs. Classified natively, by extension. */
  family: 'volume' | 'mesh'
}

/** Page → native. Exactly one terminal message (`loaded` or `failed`) per request. */
type HostMessage =
  | { stage: 'ready' }
  | { stage: 'loaded'; metadata: Record<string, string> }
  | { stage: 'failed'; code: FailureCode; message: string }

/**
 * Structured so the native side can react without parsing prose. Mirrored by
 * `PreviewFailure` in `PreviewViewController.swift`; the two travel as bare
 * strings, so keep them in sync.
 */
export type FailureCode =
  | 'graphics-unavailable'
  | 'unreadable'
  | 'unsupported'
  | 'timeout'
  | 'cancelled'
  | 'resource-limit'
  | 'internal'

/** One sentence per code. Concise, and never a filesystem path. */
const failureText: Record<FailureCode, string> = {
  'graphics-unavailable': 'This Mac could not provide the graphics needed to render a preview.',
  unreadable: 'This file could not be read.',
  unsupported: 'This file type cannot be previewed.',
  timeout: 'This file took too long to load.',
  cancelled: 'The preview was cancelled.',
  'resource-limit': 'This file is too large to preview.',
  internal: 'This file could not be previewed.',
}

declare global {
  interface Window {
    niivuePreview?: {
      render(request: PreviewRequest): Promise<void>
      /** Native-detected failures, shown here so the panel is never blank. */
      fail(code: FailureCode): void
    }
  }
}

/**
 * `window.webkit` is deliberately NOT redeclared here. `bridge.ts` already
 * augments it for the app's own channels, and the two entries share one global
 * namespace — a second declaration is a type conflict, and widening the app's
 * channel union to include a preview-only handler would couple two pages that
 * should stay independent. A local structural cast keeps them apart.
 */
function post(message: HostMessage): void {
  const handler = (
    window as unknown as {
      webkit?: { messageHandlers?: { qlPreview?: { postMessage: (m: string) => void } } }
    }
  ).webkit?.messageHandlers?.qlPreview
  handler?.postMessage(JSON.stringify(message))
}

const el = <T extends HTMLElement>(id: string): T => document.getElementById(id) as T
const stage = {
  canvas: el<HTMLCanvasElement>('gl'),
  loading: el<HTMLDivElement>('loading'),
  fallback: el<HTMLDivElement>('fallback'),
  fallbackDetail: el<HTMLDivElement>('fallback-detail'),
  meta: el<HTMLDivElement>('meta'),
}

/** Never leave a blank canvas — the product contract's hard rule. */
function showFallback(detail: string): void {
  stage.loading.hidden = true
  stage.fallback.hidden = false
  stage.fallbackDetail.textContent = detail
}

function showMetadata(name: string, pairs: Record<string, string>): void {
  stage.meta.textContent = ''
  const title = document.createElement('div')
  title.className = 'name'
  title.textContent = name
  stage.meta.append(title)
  for (const [key, value] of Object.entries(pairs)) {
    const pair = document.createElement('span')
    pair.className = 'pair'
    const strong = document.createElement('b')
    strong.textContent = value
    pair.append(`${key} `, strong)
    stage.meta.append(pair)
  }
  stage.meta.hidden = false
}

/**
 * The metadata strip stays visible while an overlay covers the canvas. That is
 * the product contract's "metadata fallback": the file is intact and its header
 * is worth showing, there is simply no ordinary voxel view to draw — a complex
 * or single-slice volume, say. Distinct from `fail`, which is an error.
 */
function showMetadataOnly(name: string, pairs: Record<string, string>, reason: string): void {
  showMetadata(name, pairs)
  showFallback(`No image preview for this file — ${reason}.`)
}

/**
 * Keep the drawing buffer matched to the CSS box as Finder resizes the panel.
 * Without this the canvas keeps its initial backing size and goes soft — the
 * preview is resizable by definition, so this is not optional polish.
 */
function trackSize(nv: NiiVue): () => void {
  const observer = new ResizeObserver(() => {
    const ratio = window.devicePixelRatio || 1
    const { clientWidth, clientHeight } = stage.canvas
    if (!clientWidth || !clientHeight) return
    stage.canvas.width = Math.round(clientWidth * ratio)
    stage.canvas.height = Math.round(clientHeight * ratio)
    nv.drawScene()
  })
  observer.observe(stage.canvas)
  return () => observer.disconnect()
}

/**
 * Exactly one terminal message per preview, from whichever of the three racing
 * sources gets there first: the load finishing, the page failing, or the host
 * calling `fail` on a timeout. The native side gates its Quick Look completion
 * too; this gate is what stops a *second* message being posted at all.
 */
let settled = false
let nv: NiiVue | undefined

/**
 * There is deliberately no abort of an in-flight load here. NiiVue owns the
 * fetch and exposes no signal, and the real cancellation path is native: Quick
 * Look tears the web view down, WebKit stops the scheme task, and
 * `PreviewSchemeHandler` returns out of its read loop. An `AbortController` on
 * this side would only look like cancellation.
 */
function fail(code: FailureCode, detail?: string): void {
  if (settled) return
  settled = true
  showFallback(failureText[code])
  post({ stage: 'failed', code, message: detail ?? code })
}

/**
 * The fixed four-quadrant layout from the product contract, in reading order:
 * Axial, Coronal, Sagittal, Render. `customLayout` overrides every built-in
 * layout mode, so a preview cannot drift with NiiVue's multiplanar heuristics
 * the way `multiplanarType` would.
 */
const QUADRANTS: CustomLayoutTile[] = [
  { sliceType: SLICE_TYPE.AXIAL, position: [0, 0, 0.5, 0.5] },
  { sliceType: SLICE_TYPE.CORONAL, position: [0.5, 0, 0.5, 0.5] },
  { sliceType: SLICE_TYPE.SAGITTAL, position: [0, 0.5, 0.5, 0.5] },
  { sliceType: SLICE_TYPE.RENDER, position: [0.5, 0.5, 0.5, 0.5] },
]

async function render(request: PreviewRequest): Promise<void> {
  if (!nv) {
    fail('graphics-unavailable')
    return
  }
  if (request.family === 'mesh') {
    // Milestone 5. Saying so is better than drawing an empty render tile.
    fail('unsupported', 'mesh')
    return
  }
  let volume: NVImage
  try {
    await nv.loadVolumes([
      {
        url: request.url,
        // Load-bearing: NiiVue infers the reader from the name, and the opaque
        // document route carries no extension of its own.
        name: request.displayName,
        // 4D files keep frame zero only. The total is still reported — see
        // `nTotalFrame4D` in the summary — so the strip stays honest about what
        // the file contains versus what is on screen.
        limitFrames4D: 1,
      },
    ])
    if (settled) return
    if (nv.volumes.length === 0) {
      fail('unsupported', 'no volume produced')
      return
    }
    volume = nv.volumes[0]
  } catch (error) {
    if (settled) return
    const message = error instanceof Error ? error.message : String(error)
    // NiiVue refuses some valid files outright — complex and 128-bit NIfTI
    // among them — and "could not be read" would blame the file for being
    // damaged when it is merely unsupported. Matching the message is coarse,
    // but it degrades to `unreadable`, which is what it would have said anyway.
    fail(/unsupported datatype/i.test(message) ? 'unsupported' : 'unreadable', message)
    return
  }

  const summary = describeVolume(volume, request.displayName, request.fileSize)
  settled = true
  stage.loading.hidden = true

  if (!summary.displayable) {
    // A successful request that has nothing to draw. Reported as `loaded`, not
    // `failed`: the native side would replace our panel — and its metadata —
    // with Quick Look's generic one.
    showMetadataOnly(request.displayName, summary.pairs, summary.reason ?? 'unsupported data')
    post({ stage: 'loaded', metadata: { ...summary.pairs, displayable: 'false' } })
    return
  }

  nv.customLayout = QUADRANTS
  // Draw all three orientations at one physical scale rather than zooming each
  // to fill its quadrant, so the panels are comparable.
  nv.isEqualSize = true
  nv.isOrientationTextVisible = true
  showMetadata(request.displayName, summary.pairs)
  nv.drawScene()
  post({ stage: 'loaded', metadata: { ...summary.pairs, displayable: 'true' } })
}

// Installed before NiiVue is constructed so the host can always reach `fail`,
// including when the graphics context is what failed.
window.niivuePreview = { render, fail }

async function main(): Promise<void> {
  try {
    nv = new NiiVue({
      logLevel: 'warn',
      backgroundColor: [0, 0, 0, 1],
      // Same reasoning as the app: naming a backend lets the constructor
      // downgrade to webgl2 up front instead of failing an init and swapping in
      // a fresh canvas. WKWebView has no navigator.gpu today.
      backend: 'webgpu',
      isOrientCubeVisible: false,
      isRadiological: false, // "neurological orientation" from the product contract
      showRender: SHOW_RENDER.ALWAYS,
      // Centred crosshair. This is also NiiVue's default, but the contract
      // names it, and a default is not a guarantee across versions.
      crosshairPos: [0.5, 0.5, 0.5],
      // Enables the depth-disabled pass that draws the crosshair through a
      // volume render. Named for meshes; not mesh-only. See the app's bridge.ts.
      meshXRay: 0.05,
    })
    await nv.attachToCanvas(stage.canvas)
  } catch (error) {
    // Both graphics backends are gone. The native side turns this into its own
    // fallback view; without the message it would see a black rectangle.
    nv = undefined
    fail('graphics-unavailable', error instanceof Error ? error.message : String(error))
    return
  }

  trackSize(nv)
  post({ stage: 'ready' })
}

void main()
