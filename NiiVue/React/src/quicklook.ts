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
 * Milestone 2 scope: the shell, the message contract, and the layout. The
 * request carries no document URL yet — the scoped transport is Milestone 3 —
 * so `renderRequest` completes on a synthetic request without touching document
 * bytes, which is exactly this milestone's exit gate.
 */
import { NiiVue, SHOW_RENDER, SLICE_TYPE } from '@niivue/niivue'

/** Native → page. One request per preview; the host never sends a second. */
export interface PreviewRequest {
  /** Same-origin URL for the document. Absent until Milestone 3. */
  url?: string
  displayName: string
  /** Bytes on disk, for the metadata strip. */
  fileSize?: number
  /** Which loader to use. `synthetic` renders nothing and is the M2 gate. */
  family: 'volume' | 'mesh' | 'synthetic'
}

/** Page → native. Exactly one terminal message (`loaded` or `failed`) per request. */
type HostMessage =
  | { stage: 'ready' }
  | { stage: 'loaded'; metadata: Record<string, string> }
  | { stage: 'failed'; code: FailureCode; message: string }

/** Structured so the native side can react without parsing prose. */
export type FailureCode =
  | 'graphics-unavailable'
  | 'unreadable'
  | 'unsupported'
  | 'timeout'
  | 'internal'

declare global {
  interface Window {
    niivuePreview?: { render(request: PreviewRequest): Promise<void> }
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

export function formatBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes < 0) return '—'
  const units = ['B', 'KB', 'MB', 'GB']
  let value = bytes
  let unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit += 1
  }
  return `${value < 10 && unit > 0 ? value.toFixed(1) : Math.round(value)} ${units[unit]}`
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

async function main(): Promise<void> {
  let nv: NiiVue
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
      // Enables the depth-disabled pass that draws the crosshair through a
      // volume render. Named for meshes; not mesh-only. See the app's bridge.ts.
      meshXRay: 0.05,
    })
    await nv.attachToCanvas(stage.canvas)
  } catch (error) {
    // Both graphics backends are gone. The native side turns this into its own
    // fallback view; without the message it would see a black rectangle.
    const message = error instanceof Error ? error.message : String(error)
    showFallback('This Mac could not provide the graphics needed to render a preview.')
    post({ stage: 'failed', code: 'graphics-unavailable', message })
    return
  }

  trackSize(nv)

  window.niivuePreview = {
    async render(request: PreviewRequest): Promise<void> {
      try {
        if (request.family === 'synthetic' || !request.url) {
          // Milestone 2 gate: prove the whole shell round-trips without reading
          // a single document byte. Milestone 3 replaces this branch.
          nv.sliceType = SLICE_TYPE.MULTIPLANAR
          stage.loading.hidden = true
          showMetadata(request.displayName, {
            status: 'preview shell ready',
            size: formatBytes(request.fileSize ?? -1),
          })
          post({ stage: 'loaded', metadata: { synthetic: 'true' } })
          return
        }
        showFallback('This file type cannot be previewed yet.')
        post({ stage: 'failed', code: 'unsupported', message: request.family })
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error)
        showFallback('This file could not be read.')
        post({ stage: 'failed', code: 'unreadable', message })
      }
    },
  }

  post({ stage: 'ready' })
}

void main()
