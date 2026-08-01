# NiiVue web viewer

The rendering half of the NiiVue iOS app: a React + Vite + TypeScript page that
hosts [`@niivue/niivue`](https://www.npmjs.com/package/@niivue/niivue) **1.0.0-rc.11**
on a single canvas. The SwiftUI app loads the production build (`dist/index.html`)
into a `WKWebView` over a custom `niivue-app://` scheme, served straight out of the
app bundle by `BundleSchemeHandler` — there is no server and no network access at
runtime. (It used to load over `file://`; that needed two private WebKit
preferences to get past CORS on module scripts, so the scheme handler replaced it.)

The dependency is pinned to an exact pre-release version, not a `^` range: the
NiiVue API can move between release candidates.

## Scripts

```bash
npm ci          # clean, lockfile-respecting install
npm run dev      # vite --host --open — opens a browser; also binds on the LAN
                 # so a device can reach it. Loads the app's sample volume.
npm run build    # tsc -b && vite build -> ./dist, which Xcode copies into the app
npm run lint
npm run preview  # serve the production build locally
```

`NiiVue.xcodeproj` runs the build in a build phase, so an Xcode build picks up
source changes automatically (and runs `npm ci` first on a fresh clone).

## The native bridge

[`src/bridge.ts`](src/bridge.ts) is the whole contract with the host app. It
installs `window.niivueBridge` — the functions `WebViewManager` (in
`../NiiVue/ContentView.swift`) calls — and posts events back through
`window.webkit.messageHandlers`.

### Web → native

| Channel | Payload | Handled by |
| --- | --- | --- |
| `updateUI` | the literal string `"ready"` | sets `isViewerReady = true` |
| `locationChange` | `JSON.stringify(e.detail.mm)` | `private(set) var location` |
| `logMessage` | diagnostics; printed as `niivue: …` in the Xcode console | `print` |

### Native → web

| Function | Transport |
| --- | --- |
| `loadImageURL(url, fileName) → Promise<boolean>` | `callAsyncJavaScript`; the URL is a same-origin opaque route served by the native scheme handler |
| `saveDrawing() → Promise<string>` | `callAsyncJavaScript`; returns a base64 `.nii.gz` |
| `setSliceType(n)` · `setLayout(n)` · `setDragMode(n)` | `evaluateJavaScript` |
| `setCrosshairVisible(b)` | `evaluateJavaScript` |
| `setOrientationText(b)` · `setOrientationCube(b)` · `setRadiological(b)` | `evaluateJavaScript` |
| `setPenValue(value, isFilled, drawingEnabled)` | `evaluateJavaScript` |
| `moveCrosshairInVox(x, y, z)` · `setCrosshairColor()` | `evaluateJavaScript` |

### Readiness contract

Nothing may be sent before the page posts `updateUI`. `WebViewManager.load()`
resets `isViewerReady` to `false` on every page load, and calls made while it is
`false` are **dropped and logged, not queued**. On readiness the host replays its
current state (selected image, then all viewer settings).

`loadImageURL` calls are serialised through an internal queue. Superseded requests
return `false` before NiiVue fetches them, so rapid file selections do not create
another source buffer for work the user no longer wants.

Outside a `WKWebView` the `postToHost` calls are no-ops, so `npm run dev` works in
a normal browser. It also self-loads the app's sample volume (see below), so the
page is useful without a host — but the native paths (document picker, save to
Files, the readiness handshake) can only be exercised on a simulator or device.

## Notes

- **The canvas is created imperatively** in [`src/App.tsx`](src/App.tsx) rather than
  rendered by React. When WebGPU is unavailable NiiVue falls back to WebGL2 by
  swapping in a fresh canvas element, which would strand a React-owned ref.
  `bridge.ts` names `backend: 'webgpu'` explicitly rather than leaving it unset, so
  the constructor's `enforceBackendAvailability()` downgrades to `webgl2` up front
  when `navigator.gpu` is absent — as it is in WKWebView today — and the failed-init
  canvas swap never happens. The imperative canvas also keeps StrictMode teardown
  clean.
- `vite.config.ts` sets `base: './'` so asset references stay relative to whatever
  origin serves the page, and `build.target: 'safari16'` to match the app's
  `IPHONEOS_DEPLOYMENT_TARGET` of 16.4.
  **Those two are coupled**: `saveDrawing` gzips with `CompressionStream`, which
  needs Safari/WKWebView 16.4+.
- `publicDir: '../NiiVue/samples'` is what lets `npm run dev` serve the app's demo
  volume, and `build.copyPublicDir: false` keeps that 4 MB file **out** of `dist/` —
  Xcode bundles `samples/` separately, so copying it would duplicate it in the app.
- `saveVolume({ filename: '' })` returns bytes; any non-empty filename makes NiiVue
  trigger a browser *download* instead. That is why gzip is done by hand.
- The host refuses imports over **256 MB** (`ContentView.maxImportBytes`) as a
  simple input/storage policy. The selected file is then streamed through the
  native same-origin scheme handler; it is not copied into a base64 JS argument.
  `setDragMode` targets NiiVue's `primaryDragMode` (the left / one-finger drag),
  defaulting to `DRAG_MODE.crosshair`.
