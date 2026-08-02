# CLAUDE.md — NiiVue iOS

Context for working on this repo. Written for a session starting cold.

## What this is

A SwiftUI app (`NiiVue/NiiVue/`) that hosts a React + Vite + TypeScript page
(`NiiVue/React/`) inside a `WKWebView`, rendering medical images with
`@niivue/niivue`. The page is served from the app bundle over a custom
`niivue-app://` scheme (see `BundleSchemeHandler`) — no server, no network, works
offline. All UI chrome is native SwiftUI; the web page
is only a canvas.

Bundle id `com.niivue.mobile`. Ships for iPhone, iPad, and macOS (Mac Catalyst).

| Path | Role |
| --- | --- |
| `NiiVue/NiiVue/ContentView.swift` | All native UI + `WebViewManager` — the entire Swift side of the bridge. Also holds `DocumentPicker`, `DocumentExporter` and `BundleSchemeHandler`; there are **no separate files** for them, so grep rather than looking for `BundleSchemeHandler.swift` |
| `NiiVue/NiiVue/NiiVueApp.swift`, `SharedData.swift` | App entry; `SharedData` is injected but inert — see Known scaffolding |
| `NiiVue/React/src/bridge.ts` | **The whole JS contract**: NiiVue setup, `window.niivueBridge`, host messaging |
| `NiiVue/React/src/App.tsx` | ~43 lines; creates the canvas imperatively, calls `startNiiVue` |
| `NiiVue/React/vite.config.ts` | `base: './'`, `build.target: 'safari16'`, dev-only `publicDir` |
| `NiiVue/NiiVue/samples/T1w_DEMO.nii.gz` | Demo volume, auto-loaded at launch |

## Toolchain

- **Node 20.19+ / 22.13+ / 24+.** Vite 8 needs `^20.19.0 || >=22.12.0`; ESLint 10
  is the stricter one at `^20.19.0 || ^22.13.0 || >=24`. Verified on Node 26.4.0 / npm 11.17.0.
- Homebrew `node`/`npm` live at `/opt/homebrew/bin`, which is **not** on a bare
  login PATH — the Xcode script phase exports it explicitly for this reason.
- Xcode 26.2 verified. Project `objectVersion = 56`, `SWIFT_VERSION = 5.0`.
- Key deps: `@niivue/niivue` **1.0.0-rc.11** (exact pin, pre-release) ·
  `react`/`react-dom` ^19.2 · `vite` ^8.2 · `typescript` ^5.9.3 · `eslint` ^10.8 ·
  `typescript-eslint` ^8.65 · `@vitejs/plugin-react` ^6.
- Do not drop TypeScript below 5.7 — `bridge.ts` uses the `Uint8Array<ArrayBuffer>`
  generic form.
- `npm run dev` (`vite --host --open`) **self-loads the app's sample volume**, so
  the page is useful without a native host. `vite.config.ts` sets
  `publicDir: '../NiiVue/samples'` to serve it and `build.copyPublicDir: false` to
  keep the 4 MB file **out** of `dist/` (Xcode bundles `samples/` separately —
  copying it would duplicate it in the app). The fallback in `bridge.ts` is gated
  on `import.meta.env.DEV && !window.webkit`, so it cannot fire in the shipped app.
  Dev mode still cannot exercise the native paths (document picker, save to Files,
  readiness handshake) — those need the simulator or a device.
- `./scripts/check-signing.sh` reports keychain identities, the Apple team each
  belongs to, and which targets can build. Reads `$APPLE_TEAM_ID` / `$APPLE_ID`
  (both are in the developer's shell profile here). Exits non-zero when the team
  has no *development* certificate — note a **Developer ID Application** cert signs
  shipping/notarized apps and does NOT satisfy day-to-day development builds.

## Build and run

```bash
cd NiiVue/React && npm ci               # once; dist/ and node_modules/ are gitignored

cd NiiVue
xcodebuild -project NiiVue.xcodeproj -scheme NiiVue \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

xcodebuild -project NiiVue.xcodeproj -scheme NiiVue \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build
```

- Build phase order is load-bearing: **ShellScript → CopyFiles → Sources →
  Frameworks → Resources.** The script phase runs the web build; CopyFiles copies
  the folder references `React/dist` and `NiiVue/samples` into the bundle as
  `NiiVue.app/dist/` and `NiiVue.app/samples/`.
- The phase declares no outputs, so it runs every build. The resulting Xcode
  warning is expected.
- Requires an installed iOS **simulator runtime**, not just the SDK, or `actool`
  fails with `No available simulator runtimes`. Install with
  `xcodebuild -downloadPlatform iOS`.
- `DEVELOPMENT_TEAM = VJ2G5D3BY7` is hardcoded; simulator builds sign locally and
  ignore it.
- There is no shared scheme (`NiiVue.xcodeproj/xcshareddata/xcschemes/` does not
  exist). Harmless — verified by cloning to a temp dir and deleting all
  `xcuserdata/`: `xcodebuild -list` still reports the `NiiVue` scheme because
  xcodebuild autocreates it. No Xcode round-trip needed.

## Platform constraints — do not change casually

`IPHONEOS_DEPLOYMENT_TARGET = 16.4` ↔ `vite build.target: 'safari16'` ↔
`CompressionStream` (Safari 16.4+), used by `gzip()` in `bridge.ts`. **Lowering the
deployment target silently breaks `saveDrawing` at runtime.**

Raising it above 17 is what would be needed before "modernising" the 15
single-parameter `.onChange(of:)` calls in `ContentView.swift` — but that drops
iOS 16 devices. The current form is correct for the target and the compiler emits
no deprecation warnings at 16.4 (the two-parameter overload is not yet available);
leave it.

**Mac Catalyst is enabled** (`SUPPORTS_MACCATALYST = YES`,
`SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO`). Consequences:

- Catalyst compiles as iOS, so `#if os(macOS)` is **unreachable**. The correct test
  is `#if targetEnvironment(macCatalyst)` (see `dragLabel` in `ContentView.swift`).
- `UIDocumentPickerViewController` is backed by `NSOpenPanel` (import) and
  `NSSavePanel` (export, via `DocumentExporter`), which need
  `com.apple.security.files.user-selected.read-write` in the entitlements. It is
  there; removing it breaks opening and saving on Mac only.
- Catalyst ignores `presentationDetents` and sizes a sheet from its content, so the
  settings panel measures the window (`windowHeight`) and asks for an explicit
  frame. Without that it renders far smaller than its contents.
- Do **not** add `macosx` to `SUPPORTED_PLATFORMS`; `SUPPORTS_MACCATALYST` alone is
  enough, and adding it makes Xcode offer a native-macOS destination that cannot
  compile (the code is UIKit).

## The bridge contract

**Native → web** — `window.niivueBridge`, 12 functions. `loadImageURL` and
`saveDrawing` are `async` and are invoked with `callAsyncJavaScript`; everything
else goes through `WebViewManager.call()` → `evaluateJavaScript`.

**Web → native** — `window.webkit.messageHandlers`:

| Channel | Payload |
| --- | --- |
| `updateUI` | `"ready"` → sets `isViewerReady = true`. **Any other body is a startup failure**: `bridge.ts` posts `error: <message>` when both graphics backends fail in `attachToCanvas`, and Swift turns it into the "viewer could not start" alert. Without it the host sees a black canvas and silently drops every call |
| `locationChange` | `JSON.stringify(e.detail.mm)` |
| `logMessage` | printed as `niivue: …` |

**Readiness handshake — the important part:**

1. `WebViewManager.load()` sets `isViewerReady = false` before loading
   `niivue-app://app/index.html`, so it resets on every reload.
2. The page posts `updateUI` only after `attachToCanvas` resolves and
   `window.niivueBridge` is assigned.
3. Every native call guards on `isViewerReady`; early calls are **dropped and
   logged, never queued**.
4. `ContentView.onChange(of: isViewerReady)` replays state: demo/selected image,
   then `applyViewerSettings()`.
5. Every volume- and drawing-touching op runs on one `enqueue` chain in
   `bridge.ts` — loads AND saves. A save that merely `await`ed the queue could be
   overtaken by a load. `destroy()` sets `destroyed` first so queued work bails.
   Superseded loads compare `loadGeneration` and return **before** fetching, so
   three rapid picks do not materialise three source buffers. Teardown checks
   again after the load before closing the drawing.

**Load / recovery invariants — each of these is load-bearing and looks like noise.**

- `loadImage(from:userInitiated:)` — only a *user pick* passes `true`, and only
  `true` calls `allowAutoReload()`. The recovery path re-reads through the same
  function; if it re-armed the guard there, a volume that kills the content
  process would be retried forever. The demo load also passes `false`.
- `pendingImageURL` is separate from `pickedDocumentURL`. A failed replacement
  therefore leaves the accepted filename and drawing intact.
- The bridge completion is generation-scoped: `request == imageLoadRequest` and
  `loadingImageRequest == request`. Two quick picks can complete out of order, and
  an older completion cannot accept its URL or clear the newer pending selection.
- The import size check **fails closed**: an unreadable size refuses the file rather
  than passing the cap as zero.
- `BundleSchemeHandler` validates `url.host` and checks containment on **path
  components**, not `hasPrefix` — `/root` is a string prefix of `/rootlike/secret`,
  so a prefix test would re-open the traversal hole that moving off `file://` closed.
  Bundle paths resolve symlinks, and picked files use one opaque token under the
  same origin. The file read is chunked at 1 MiB — that bounds the *Swift*
  allocation, **not** the peak: `WKURLSchemeTask` has no flow control, so the web
  content process still buffers the whole response.
- **Every `WKURLSchemeTask` callback goes through `deliver(_:_:)`, on the main
  queue.** Messaging a stopped task raises an Objective-C exception that Swift
  cannot catch — a hard crash. `webView(_:stop:)` arrives on the main queue and
  WebKit marks the task stopped *before* calling it, so no lock can make a
  background "check the flag, then send" pair atomic against it; sharing the queue
  is what does. `deliver` is `sync` on purpose, so the read loop waits for each
  chunk instead of piling a whole volume onto the main queue as pending blocks.
- The scheme handler's `document` slot holds exactly **one** file, and the request
  path carries `token` *and* filename, both matched exactly. That is safe only
  because `bridge.ts` drops a superseded load **before** fetching — otherwise an
  older pick would fetch a token a newer pick had already overwritten. The two are
  a cross-language pair; do not remove either half alone.
- The filename in the token route is percent-encoded with
  `addingPercentEncoding(withAllowedCharacters: .alphanumerics)`. The `URLComponents.path`
  setter leaves a literal `%` alone, so `a%2Fb.nii` came back from `url.path` as
  `a/b.nii` — four path components, and a refused load.
- `response(for:fileURL:mime:)` returns **nil rather than a header-less
  `URLResponse`** when `HTTPURLResponse` cannot be built. The old `??` fallback
  failed *open*, serving the page with no CSP and no `nosniff`.
- The navigation delegate allows only `niivue-app://app/...` **and rejects any path
  under `/document`**. The picked-file route is fetch-only; it must never become the
  top-level document.
- The staged export file is removed in `onFinish` on **both** save and cancel, and
  again from `.onChange(of: exportPresented)`. `onFinish` covers only the two
  delegate outcomes — a swipe-dismissed SwiftUI sheet dismantles the representable
  without calling either, leaving a full-size volume in `tmp/` and a non-nil
  `exportURL` that makes the next save orphan another one. The second removal is
  idempotent and cannot race the export: the picker copies the file before its
  callback fires.
- `saveDrawing` reports a `SaveOutcome`, not `URL?`. Collapsing every failure to
  `nil` told the user "draw something first" when the real cause was a failed gzip,
  an unwritable temp directory, or a torn-down page. `.superseded` exists so the
  caller still clears `saveInFlight` while staying quiet — the recovery alert
  already explains that case, and dropping the callback instead left the share
  button permanently disabled.
- Swift's `teardownError` string must stay in sync with `TEARDOWN_ERROR` in
  `bridge.ts`. It is the one consumer of that sentinel; without it a teardown is
  reported to the user as a bad drawing.
- `recoveryMessage` is reset to `nil` after the alert consumes it, or two identical
  messages in a row compare equal and the second never fires `onChange`.
- The readiness watchdog is **generation-scoped** (`loadGeneration`). A single
  latch let an earlier load's 20 s timer fire during a later load's startup: it
  raised a spurious "did not finish starting" AND latched the watchdog off for the
  load actually at risk — wrong in both directions.
- Crash recovery latches only when the repeat termination lands within
  `crashLoopWindow` (60 s). WebKit also evicts the content process after prolonged
  backgrounding, which is benign; an unconditional latch made that permanently
  unrecoverable and blamed the user's image for it.
- **A latched crash loop must have a way out.** When the guard declines to reload
  it sets `pageIsDead`, and `allowAutoReload()` — reached only from a real user
  pick — reloads the page. Without that the latch was terminal: `WebView.onAppear`
  has already fired and never fires again, so nothing else calls `load()`; the
  remedy the alert suggests (open a smaller image) hit `guard isViewerReady` and
  did nothing, and the app stayed a black rectangle until it was force-quit.
- Every content-process termination marks the page not ready. A second crash in
  the crash window therefore disables native calls instead of leaving a dead page
  looking ready; page-session tokens discard late WebKit completions.
- The export `.sheet` is attached to the **root view**, not to `shareButton`.
  `shareButton` only exists `if drawingEnabled`, so a save completing after the user
  turned drawing off would set `exportPresented` on a view that no longer exists —
  no panel, and the staged temp file orphaned because `onFinish` never ran.
- `DocumentPicker.importTypes` is deliberately `[.data]`. NiiVue reads 13 formats
  (mgh/mgz, nrrd/nhdr, mha/mhd, mif/mih, AFNI head/brik, npy/npz, vmr/v16, src,
  fib, ecat, iwi.cbor, images) and almost none have a registered system UTI, so a
  `UTType(filenameExtension:)` list greys them out. Narrowing it to `["nii","gz"]`
  was a capability regression; the failure alert carries the validation instead.
- The load-failure alert deliberately does **not** say "not a NIfTI image". The same
  path also covers the renderer being killed and the bridge being torn down.

**Content-process recovery.** `webViewWebContentProcessDidTerminate` reloads the
page, which re-runs the whole handshake above. That reload re-sends the same
volume — so if the volume is what exhausted memory, an unguarded reload loops
forever. Recovery is therefore **one-shot per image**, re-armed in `loadImage`
when the user picks a new file, and the user is told the drawing was lost (it
lives only in the page). Do not remove the guard.

**Enums cross the bridge as bare ints** with no shared definition. Verified to
match NiiVue's constants today:

- `SliceTypes` ↔ `SLICE_TYPE`: Axial 0, Coronal 1, Sagittal 2, Multiplanar 3, Render 4
- `LayoutTypes` ↔ `MULTIPLANAR_TYPE`: Auto 0, Column 1, Grid 2, Row 3
- `DragTypes` ↔ `DRAG_MODE`: none 0, contrast 1, measurement 2, pan 3, slicer3D 4,
  **crosshair 8**. The Swift enum is deliberately non-contiguous; NiiVue's own
  `DRAG_MODE` is contiguous 0–9 (5 callbackOnly, 6 roiSelection, 7 angle,
  9 windowing simply are not exposed in the UI).

### Drag gestures

`setDragMode` writes **`primaryDragMode`** — the LEFT / one-finger drag.
`secondaryDragMode` (the right drag) is left at NiiVue's `contrast` default and is
not exposed in the UI. NiiVue 1.0 defaults primary to `DRAG_MODE.crosshair`, so a
left drag moves the crosshair; 0.41 had a single `dragMode` defaulting to
`contrast`, which is a different gesture model — do not "restore" it. The settings
label names the gesture (`left drag` on Catalyst, `one-finger drag` on iOS)
because the old "(right click)" label described the wrong button. See
`examples/vox.gestures.html` in the NiiVue repo for the reference UI.

## NiiVue 0.41.1 → 1.0.0-rc.11 API map

The migration (commit `278d9ce`) is the main reason this file exists.

| 0.41.1 | 1.0.0-rc.11 |
| --- | --- |
| `import { Niivue, NVImage }` | `import { NiiVue, DRAG_MODE, SHOW_RENDER, type NiiVueLocation }` |
| `nv.setSliceType(n)` | `nv.sliceType = n` |
| `nv.setMultiplanarLayout(n)` | `nv.multiplanarType = n` |
| `nv.opts.multiplanarForceRender = true` | `showRender: SHOW_RENDER.ALWAYS` (ctor) |
| `nv.opts.dragMode = n` | `nv.primaryDragMode = n` |
| `nv.opts.show3Dcrosshair = b` + `crosshairWidth` as a 2D on/off | **collapsed** into `nv.is3DCrosshairVisible = b` alone — see the crosshair note below |
| `nv.opts.isOrientCube = b` | `nv.isOrientCubeVisible = b` |
| `nv.opts.crosshairWidth = n` | `nv.crosshairWidth = n` — **radius only**, not visibility |
| `nv.setCrosshairColor([…])` | `nv.crosshairColor = […]` |
| `nv.setRadiologicalConvention(b)` | `nv.isRadiological = b` |
| `nv.setCornerOrientationText(b)` | **removed** — only `nv.isOrientationTextVisible = b`; corner-vs-edge placement is gone |
| `nv.setDrawingEnabled(b)` | `nv.drawIsEnabled = b` |
| `nv.setPenValue(v, isFilled)` | `nv.drawPenValue` / `nv.drawPenFilled` / `nv.drawPenAutoClose` |
| drawing bitmap created implicitly | **must call `nv.createEmptyDrawing()`** when `nv.drawingVolume == null`, or the pen is silently inert |
| `nv.saveImage({…})` → `Uint8Array` (sync) | `await nv.saveVolume({…})` → `Promise<boolean \| Uint8Array>` — **async**, hence `callAsyncJavaScript` on the Swift side |
| `NVImage.loadFromBase64(…)` + `addVolume` | `await nv.loadVolumes([{ url, name: fileName }])` — `url` is the opaque same-origin route from `BundleSchemeHandler`, and the filename remains load-bearing because NiiVue infers the reader from it |
| `nv.onLocationChange = fn` | `nv.addEventListener('locationChange', fn)`; coords at `e.detail.mm` |
| `loadingText` | `placeholderText` |
| (WebGL2 only) | `backend: 'webgpu' \| 'webgl2'`; `nv.destroy()` now exists and should be called on teardown |

1.0 turns `isOrientCubeVisible` and `is3DCrosshairVisible` **on** by default. The
constructor forces the orientation cube off to match the SwiftUI toggle, and
deliberately leaves the crosshair alone.

### `meshXRay` is not mesh-only

The constructor sets `meshXRay: 0.05`. Despite the name, any non-zero value gates
a whole extra render pass — `gl/NVViewGL.ts`, `if (xrayAlpha > 0)` — that re-draws
the **crosshair** with depth testing disabled, in addition to any meshes. With a
volume and no mesh loaded that is the entire visible effect: the crosshair can be
traced faintly *through* the rendered head instead of only appearing as stubs
where it exits the surface. It is a constructor option (`NVTypes.ts`) mapped to
`model.mesh.xRay`, and there is a `nv.meshXRay` setter if it ever needs a toggle.
0.05 is deliberately faint — enough to locate the crosshair in 3D, not enough to
read as an artefact.

### The crosshair trap (cost a real regression once)

`is3DCrosshairVisible` is badly named: it gates **every** crosshair, not just the
3D one. One renderer draws both the in-plane 2D cross and the 3D cross:

```ts
// gl/NVViewGL.ts:987-991, mirrored in wgpu/NVViewGPU.ts:1288-1294
if (tile.space !== 'global3d' && md.ui.is3DCrosshairVisible && !isMosaicTile && …)
  this.crosshairRenderer.draw(…)
```

`shouldCullCylinder` (`view/NVCrosshair.ts:116`) is what turns it into a flat cross
on a 2D tile. `crosshairWidth` is only the cylinder **radius** (`gl/crosshair.ts:97`).

Consequence: **2D and 3D crosshair visibility cannot be controlled separately in
1.0.** The first migration pass carried the 0.41 two-flag model over
(`is3DCrosshairVisible: false` plus "2D crosshair" → `crosshairWidth`) and the app
shipped with no crosshair at all. The UI is now one `Crosshair` toggle. Do not
re-split it.

The NiiVue 1.0 source is checked out at `/Users/chris/src/mono/packages/niivue/src`
(`NVControlBase.ts` is the public API) — read it rather than guessing at behaviour.

## Non-obvious decisions — don't "clean these up"

- **Imperative canvas** in `App.tsx`: a failed WebGPU init makes NiiVue swap in a
  fresh canvas element, stranding a React ref.
- **`saveVolume({ filename: '' })`** returns bytes; a non-empty filename triggers a
  browser *download* instead. Hence the hand-rolled `CompressionStream` gzip.
- **`bytesToBase64` chunks at 0x8000** — spreading a whole volume into
  `String.fromCharCode` blows the JS argument limit.
- **`isCancelled()` guard** in `startNiiVue`: StrictMode can unmount while
  `attachToCanvas` is pending; a stale controller must not publish the bridge.
- **`WeakScriptMessageHandler`** exists only so `WKUserContentController` does not
  retain `WebViewManager`.
- **`imageLoadRequest` generation counter**: the accepted and pending URLs are
  separate; stale completions are discarded so a slow load cannot clobber a newer
  pick.
- **`Bundle.main.url(…)!` for `dist` is deliberate** — the build phase guarantees
  it; nil means the build is broken and should crash loudly.
- **`logLevel: 'warn'`** is deliberate: `'debug'` paints a backend badge across the
  canvas.
- **`backend: 'webgpu'` is named explicitly, not omitted.** With `backend` unset,
  `attachToCanvas` tries WebGPU, fails, and swaps in a fresh canvas to fall back.
  Naming it lets the constructor's `enforceBackendAvailability()` downgrade to
  `webgl2` up front when `navigator.gpu` is absent (as in WKWebView). Probing
  `navigator.gpu` yourself is redundant — the library already does it.
- **The page is served over `niivue-app://`, not `file://`.** Vite emits
  `<script type="module" crossorigin>`, and a `file://` page is an opaque origin,
  so module loading is CORS-blocked. The app used to work around that with two
  undocumented WebKit preferences set via KVC (`allowFileAccessFromFileURLs`,
  `allowUniversalAccessFromFileURLs`) — private API, an App Store risk, an
  uncatchable `NSUnknownKeyException` if WebKit renamed them, and read access to
  the whole container for page JS. `BundleSchemeHandler` gives the page an
  ordinary origin instead. Do not reintroduce `loadFileURL`.
- **`ContentView.maxImportBytes` caps imports at 256 MB.** This is an input/storage
  policy, not a complete decompressed-voxel bound. The source itself is served by
  the scoped, chunked scheme transport; do not reintroduce a base64 file bridge.
- **The selected file remains a URL, not a retained payload.** `asCopy: false`
  keeps the security-scoped source available for recovery, and `WebViewManager`
  stops that scope when it is replaced or deinitialized.
- **`loadVolumes` runs BEFORE `closeDrawing`** in `bridge.ts`. Reversing them
  destroys the user's drawing whenever NiiVue rejects the new file, while leaving
  the old volume on screen. Covered by regression check #2 below.
- **`closeDrawing` runs even when the load has been superseded**, and the
  generation check comes *after* it. `loadVolumes` swaps the volume without
  touching `drawingVolume`, so the instant that await resolves the drawing is
  stale — and returning early there stranded a previous volume's drawing on top of
  a newly-live one whenever a second, failing pick followed a slow first one:
  wrong dimensions on screen, wrong header on save. Returning early *before*
  `loadVolumes` is still right; returning early after it is not.

## Verification

There is **no native test target with real assertions** — `NiiVueTests.swift` and
`NiiVueUITests*.swift` are untouched Xcode templates. The web-side bridge checks
*are* now real and in the repo (see Regression tests below). The actual loop is:

```bash
cd NiiVue/React && npm run lint && npm run build && npm run test:bridge
cd ../ && xcodebuild -project NiiVue.xcodeproj -scheme NiiVue \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
xcrun simctl install booted <path>/NiiVue.app && xcrun simctl launch booted com.niivue.mobile
xcrun simctl io booted screenshot /tmp/shot.png
```

Manual checks that have regressed historically: document picking, drawing, saving
to Files, page reload, rapid successive image selections, demo auto-load.

Web inspection: `webView.isInspectable = true`, `#if DEBUG`-gated → Safari →
Develop → simulator/device. Release builds are not inspectable.

Expected non-issues: the ~1.5 MB single-chunk Vite bundle-size warning, and the
"run script phase will run during every build" warning.

## Known scaffolding (intentional, not bugs)

- `setCrosshairColor` is defined on both sides but never called by any UI.
- `SharedData` is *injected but inert*: `NiiVueApp` creates it and `ContentView`
  declares `@EnvironmentObject var sharedData`, so deleting only the file breaks
  the build — remove all three sites together. Its `location` is never written.
  `WebViewManager.location` is written but no view reads it. It is deliberately **not** `@Published` — it updates per pointer-move, and
  publishing it re-evaluated `ContentView`'s whole body at drag rate.
- `com.apple.security.network.client` is granted but unused — the app fetches
  nothing.
- `UIFileSharingEnabled` in `Info.plist` is now **inert**. It used to expose the
  Documents folder in the Files app back when drawings were written there; since
  `DocumentExporter` landed, nothing writes to Documents at all (grep for
  `documentsDirectory` returns nothing). Safe to delete — earlier revisions of this
  file said the opposite.

## Regression tests — now in the repo

`NiiVue/React/tests/bridge-regression.mjs`, run with `npm run test:bridge`. It
drives the built `dist/` in headless Chromium over a throwaway http server, so it
exercises the same bytes the app bundles. **12 checks, all passing as of this
round.** Earlier revisions of this file said these were off-repo folklore to
"recreate if useful"; they are not, and every external review since has flagged
their absence.

1. **Smoke** — load the sample, exercise the 10 bridge setters, paint a pen stroke,
   `saveDrawing`, then gunzip the base64 and assert the NIfTI header
   (188×256×190, `DT_UINT8`) and a non-zero painted-voxel count.
2. **Corrupt file** — paint a stroke, then load garbage. The drawing must survive
   and `loadImageURL` must reject.
3. **Left drag** — with `primaryDragMode = crosshair`, a left drag must emit
   `locationChange` events and move the crosshair several mm.

Playwright is deliberately **not** a `package.json` dependency: the Xcode build
phase runs `npm ci` on a fresh clone, and compiling the app should not pull a
browser-automation stack. The harness resolves a local install first, then a
global one. Install with `npm i -D playwright && npx playwright install chromium`.

What this still does not cover, and what an external review will keep asking for:
everything native. Document picking, the save panel, security-scoped provider
files, the readiness handshake and content-process recovery need a simulator, a
device, or a Mac.

## Release readiness

**Public deployment is NOT approved.** The owner's triage after audit round 2 was
"developer addresses these, then external auditor re-reviews". Do not treat the
list below as ordinary backlog — the four items marked *blocker* were release
blockers, and the earlier "none is blocking" ranking in this file was wrong.

Status of the four blockers, all addressed and awaiting re-review:

| Blocker | Status |
| --- | --- |
| Import memory amplification | **Addressed at the transport layer** — imports use an opaque same-origin URL and bounded native reads; the *import* path has no Swift base64 string, WebKit base64 argument, `atob`, or retained `_sourceFile`. Note the **export** path still does: `bytesToBase64` → WebKit string → `Data(base64Encoded:)`. That is a separate, smaller, user-initiated peak — do not read this row as "the base64 chain is gone repo-wide". The 256 MB source cap remains an input policy; NiiVue's decompressed voxel allocation still needs representative-device measurement. |
| Private WebKit file access | **Addressed** — replaced by `BundleSchemeHandler` (`WKURLSchemeHandler`). No private KVC remains. |
| `+` button destroying the drawing | **Addressed** — the picker no longer clears `drawingEnabled`; the drawing is discarded only after a new volume actually loads, and cancelling leaves everything intact. |
| Catalyst saves unreachable | **Addressed** — `DocumentExporter` presents `NSSavePanel` on Catalyst / Files "Save to" on iOS. Nothing is written to Documents behind the user's back. |

The import limit is still a policy, not a complete memory guarantee. The expensive
native-to-web base64 chain has been removed; the remaining peak is the handler's
current read chunk, the browser fetch buffer, and NiiVue's decoded volume. Do not
raise the limit until representative compressed/decompressed volumes have been
measured on the supported devices.

## Open items (not blocking, but each needs a decision)

1. **Delete the React layer.** `App.tsx` + `main.tsx` only create a canvas and call
   `startNiiVue` — there is no React UI anywhere. Replacing them with ~7 lines of
   plain TS drops 7 of the 15 dependencies and makes the StrictMode cancellation
   machinery (`isCancelled`, the teardown closure, the bridge-identity guard)
   unnecessary rather than merely correct. ~120 lines, no behaviour change.
2. **Collapse the settings plumbing.** Every viewer setting is currently written in
   four places (a `@State`, an `.onChange`, a line in `applyViewerSettings()`, a
   Swift wrapper, plus two TS sites). A `ViewerSettings` struct + one
   `setOptions(dict)` bridge call would make it two. Note the per-setting cost of
   pushing all of them at once is zero — every NiiVue setter ends in a
   `requestAnimationFrame`-coalesced `drawScene()`.
3. **Smaller:** `ContentView.swift` is ~1300 lines and splits cleanly into
   three files; dead code confirmed on both sides (`setCrosshairColor`,
   `SharedData`, the `locationChange` round-trip, a stray duplicate `dist` file
   reference in the `NiiVueUITests` group). The picker type filter and
   `Coordinator.isValidFileType` are **done** — no longer open.

## Findings resolved in round 4 (the round that reviewed the transport itself)

The transport landed in `32569d3`; this round audited **that code**, not the code
it replaced. Every finding below is a defect in the round-3 fixes.

- **`WKURLSchemeTask` callbacks raced `stop()` → hard crash.** The cancellation
  flag was checked on a background queue and the send happened after it, while
  `stop` arrived on the main queue. Messaging a stopped task raises an
  uncatchable ObjC exception. Fixed by confining the flag and every `task.*` call
  to the main queue (`deliver(_:_:)`), which also deleted `ReadState`'s lock.
- **A latched crash loop was terminal.** Nothing called `load()` again, and the
  remedy the alert suggested did nothing. Fixed with `pageIsDead` +
  `allowAutoReload()`.
- **A superseded load stranded a stale drawing on a live volume.** `closeDrawing`
  now runs whenever `loadVolumes` succeeded, before the generation check.
- **Swipe-dismissing the export sheet orphaned a full-size temp file.**
  `onFinish` only covers the two delegate outcomes; cleanup is now also on
  `.onChange(of: exportPresented)`.
- **Every export failure said "draw something first."** Replaced `URL?` with
  `SaveOutcome`; `TEARDOWN_ERROR` finally has a Swift consumer.
- **`%` in a filename refused the load** (`URLComponents.path` does not escape it),
  and the `HTTPURLResponse` fallback failed *open*, dropping CSP and `nosniff`.
  Both fixed.

Verified this round, no change needed: path containment and symlink handling in
`BundleSchemeHandler` (no escape constructible), the `imageLoadRequest` /
`loadingImageRequest` generation pair, `pageSession`, the generation-scoped
watchdog, `enqueue`'s liveness, `WeakScriptMessageHandler`, and the CSP against
the actual bundle (no WebAssembly, the one `new Function` is a guarded cbor-x
probe, both workers are blob/self).

**Refuted:** a claim that `reads`' `ObjectIdentifier` keys could collide via
address reuse. The dispatched closure holds the task strongly until after
`finishRead` runs, so the old task cannot be deallocated first.

## Still open, with a decision attached

- **No file coordination on picked files.** `asCopy: false` removed the picker's
  implicit materialisation. A non-downloaded iCloud item or a third-party File
  Provider file reports a correct logical size (so the cap check passes) but
  `FileHandle(forReadingFrom:)` may fail or read a placeholder, and a concurrent
  writer can change the file mid-stream. It degrades to the "could not open"
  alert, so it is a capability regression, not a hole. The fix is
  `NSFileCoordinator` around the read, or refusing on
  `ubiquitousItemDownloadingStatus` at pick time — **not applied**, because it
  needs real provider files on a device to validate, which this round could not do.
- **The document token and security scope are never released.** Both live until
  replaced, and `WebViewManager` is a `@StateObject`, so `deinit` effectively never
  runs. Defence-in-depth only (the page is our own code under a self-only CSP).
  **Not applied**: clearing the token when `loadImageURL` resolves assumes NiiVue
  never re-fetches the URL lazily, which is not established for all 13 readers.
- **`prepareDocumentAccess` runs before the size check**, so a rejected oversized
  pick drops the *accepted* image's scope and holds the rejected one's. Self-heals
  — the recovery replay re-acquires — and the early call is load-bearing, because
  `.fileSizeKey` on a security-scoped URL needs the scope open. Left alone.
- **Refactors, ranked** (from this round's refactor pass, none applied — the round
  that fixes ordering bugs is the wrong one in which to restructure the code they
  live in): delete the `locationChange` round-trip (dead, and it costs a
  `JSON.stringify` + IPC per pointer-move on the *default* gesture, ≈ −15 lines) ·
  delete `setCrosshairColor`, `SharedData` (3 sites) and the stray `dist` file
  reference at `project.pbxproj:152` (≈ −30) · derive `incrementText` /
  `decrementText` / `sliceTypeText` from `sliceType` instead of storing them, and
  merge `incrementSlice`/`decrementSlice` (≈ −27; also fixes two masked
  initialisation gaps) · then open items 2, 1, 3 in that order.

## Quick Look preview extension (in progress)

`quicklook_plan.md` is the plan and the record. Status: **Milestones 0.5–5
landed** (2026-08-01), Milestone 6 **dropped** (no detached formats in v1 —
`.hdr` is Apple's Radiance image type and `.img` its disk-image type, so
claiming them is not acceptable; `.mhd` was un-claimed as a consequence).
Milestone 8's automated half is done — `./scripts/check-quicklook-routing.sh`
verifies 34 routing fixtures (uppercase, compound, Unicode, spaces, long names,
read-only, and the negative cases) against the appex's own claimed types, and
`README.md` documents formats, fallbacks, limits and troubleshooting. What
remains is Finder-only: per-format spacebar sweep, discovery after reinstall and
reboot, the timing gate, and twenty open/dismiss cycles.
The extension does **not** ship yet — `README.md` describes it, so treat that as
planned, not delivered.

Web-side checks for the preview live in
`NiiVue/React/tests/preview-regression.mjs` (`npm run test:preview`, 78 checks)
with generated NIfTI/GIFTI fixtures in `tests/preview-fixtures.mjs`. They are
separate from `test:bridge` because the two pages share no code. The mesh and
tract checks read real files from the private Git-LFS `dev-images` package by
absolute path and print `SKIP` when it is absent.

**The document route must keep `.` unescaped.** `NVMesh.loadMesh` reads the
reader extension from the URL and ignores the `name` passed with it, and an
unknown extension falls back to the **MZ3 reader** — so a fully-escaped route
makes `.mz3` work by accident while `.gii`/`.tck`/`.trk`/`.trx` all fail.
`registerDocument` escapes everything except alphanumerics and `.`; `/` and `%`
are still escaped, which is what that encoding was actually protecting against.

**Container-based document types must not conform to archive types.**
`org.trx.trx` and `edu.mgh.freesurfer.mgz` conform to `public.data`, not
`public.zip-archive`/`org.gnu.gnu-zip-archive` — otherwise macOS offers to
"Uncompress" them. Same reason `.docx`, `.jar` and `.epub` do not.

**`webView.isOpaque = true` in the extension**, unlike the host app. A Quick
Look panel is movable by its background, and a non-opaque web view lets a drag
read as a window drag.

**The preview page must claim pointer gestures itself.** NiiVue's `pointerdown`
never calls `preventDefault`, and a Quick Look panel is movable by its
background, so an unclaimed drag both moves the window (with jitter, as NiiVue
tracks a pointer whose window is sliding) and starts a text selection. The page
adds a capture-phase `preventDefault` on the canvas *and* sets `user-select:
none` — two different default actions, two fixes. Safe because NiiVue binds only
pointer events there, never mouse events.

**`quicklook.html` sets `user-select: none` on purpose.** Without it, a
rotate-drag becomes a WebKit text selection — NiiVue's `pointerdown` does not
`preventDefault` — and a selection touching the canvas paints the translucent
system selection colour over its whole box, turning the entire panel blue until
the next click. Do not "restore" selectability; the strip's values reach
VoiceOver through `aria-label` instead.

**`attachToCanvas` replaces the canvas element** — NiiVue `cloneNode(false)`s it
and calls `replaceChild`, so a reference taken before attaching is detached from
then on. `quicklook.ts` therefore resolves the canvas by `id` at every use. This
already cost the preview a `ResizeObserver` that never fired and an aria-label
written to nothing; it is the same trap `App.tsx` documents for the React ref.
Do not add a `ResizeObserver` to the preview page — NiiVue installs its own and
owns `devicePixelRatio`.

**The preview turns `is3DCrosshairVisible` and `meshXRay` OFF for geometry**
(`quicklook.ts`, mesh branch only). Both are correct for a volume and wrong for
a mesh: the crosshair marks a slice position that does not exist and shows as
red stubs through the surface, and `meshXRay` redraws the mesh over itself with
depth testing disabled, washing out surfaces and desaturating tract colour. The
crosshair flag is safe to clear there *only* because that branch has no 2D
tiles — see the crosshair trap above.

Facts from the spike that are expensive to rediscover:

- **A Quick Look extension hosting `WKWebView` MUST have
  `com.apple.security.network.client`.** Without it WebKit's content process dies
  instantly — before any navigation — and the preview is a black rectangle. This
  is true even for a purely local bundled page. The product contract was amended
  (owner-approved) to keep the extension offline *by construction* instead:
  bundled assets, self-only CSP, restricted navigation, no remote URLs.
- **WebGL2 works inside the extension on real hardware** (`Apple GPU`), and a
  188×256×190 volume loads and draws in ~294 ms end to end.
- **UTI declarations must live in the CONTAINING APP's `Info.plist`**, not the
  extension's. In the appex alone they are ignored.
- `.nii` already resolves to **`gov.nih.nifti-1`, an Apple system UTI** in
  `CoreTypes.bundle` — reuse it. `.nii.gz` resolves to plain
  `org.gnu.gnu-zip-archive`, so the compound type is ours to export and must never
  claim generic gzip.
- **Ad-hoc signing is enough** for Finder to invoke an extension
  (`lsregister -f -R` + `pluginkit -a`); no development certificate needed.
- A scheme handler must return **`HTTPURLResponse`** — with a plain `URLResponse`,
  `fetch()` reports status 0 and NiiVue fails the load. (`BundleSchemeHandler`
  already does this; do not regress it when factoring the transport out.)
- **Do not gate anything on canvas pixel sampling.** It reported zero lit pixels on
  a preview that rendered correctly; NiiVue's context has no `preserveDrawingBuffer`.
- `qlmanage -p` emits nothing from a non-GUI shell. Log from inside the extension
  to a file under `NSHomeDirectory()/tmp`; `os_log` was not readable either.

## Audit trail

`audit_response.md` holds the reply to the last external review, including the
crosshair regression and the loader bugs it uncovered. Convention in this repo:
an external reviewer leaves `audit_temp.md`, the reply goes in `audit_response.md`,
and `audit_temp.md` is deleted. Both are gitignored via `audit*.md`.
