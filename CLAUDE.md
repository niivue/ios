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
| `NiiVue/NiiVue/ContentView.swift` | All native UI + `WebViewManager` — the entire Swift side of the bridge |
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

Raising it above 17 is what would be needed before "modernising" the 14
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
| `updateUI` | `"ready"` → sets `isViewerReady = true` |
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
  same origin. Payloads are delivered in bounded chunks and stopped tasks cancel
  their read state.
- The staged export file is removed in `onFinish` on **both** save and cancel.
  Without it, a full-size volume is left in `tmp/` per save.
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
  the old volume on screen. Covered by regression check #2 below (off-repo).

## Verification

There are **no real tests** — `NiiVueTests.swift` and `NiiVueUITests*.swift` are
untouched Xcode templates with zero assertions. The actual loop is:

```bash
cd NiiVue/React && npm run lint && npm run build
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

## Regression tests (not in the repo — recreate if useful)

There is no test target with real assertions. These scripted checks caught real
bugs and are worth re-running after touching the bridge; they drive the built
`dist/` in headless Chromium/WebKit via Playwright:

1. **Smoke** — load the sample, exercise the 10 bridge setters, paint a pen stroke,
   `saveDrawing`, then gunzip the base64 and assert the NIfTI header
   (188×256×190, `DT_UINT8`) and a non-zero painted-voxel count.
2. **Corrupt file** — paint a stroke, then load garbage. The drawing must survive
   and `loadImageURL` must reject.
3. **Left drag** — with `primaryDragMode = crosshair`, a left drag must emit
   `locationChange` events and move the crosshair several mm.

## Release readiness

**Public deployment is NOT approved.** The owner's triage after audit round 2 was
"developer addresses these, then external auditor re-reviews". Do not treat the
list below as ordinary backlog — the four items marked *blocker* were release
blockers, and the earlier "none is blocking" ranking in this file was wrong.

Status of the four blockers, all addressed and awaiting re-review:

| Blocker | Status |
| --- | --- |
| Import memory amplification | **Addressed at the transport layer** — imports use an opaque same-origin URL and bounded native reads; there is no Swift base64 string, WebKit base64 argument, `atob`, or retained `_sourceFile`. The 256 MB source cap remains an input policy; NiiVue's decompressed voxel allocation still needs representative-device measurement. |
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
3. **Smaller:** `ContentView.swift` is ~1060 lines and splits cleanly into
   three files; dead code confirmed on both sides (`setCrosshairColor`,
   `SharedData`, the `locationChange` round-trip, a stray duplicate `dist` file
   reference in the `NiiVueUITests` group). The picker type filter and
   `Coordinator.isValidFileType` are **done** — no longer open.

## Findings resolved in this round

- **Import transport:** `BundleSchemeHandler` serves the selected security-scoped
  file under an opaque same-origin token. `loadImageURL` passes only that small URL
  and filename to NiiVue. File handles read 1 MiB chunks off the main thread, and
  stopped tasks cancel their read state.
- **Navigation and resource policy:** bundle responses carry a self-only CSP and
  `nosniff`; the navigation delegate allows only the app scheme and host. Bundle
  paths resolve symlinks before containment is checked.
- **Picker lifecycle:** imports use `asCopy: false`; the active security scope is
  held only by `WebViewManager` and is stopped when replaced or deinitialized.
- **Late callbacks:** page-session and request generations prevent old WebKit
  completions from accepting a volume, showing a stale error, or publishing an
  export after a page restart.
- **Second content-process crash:** the manager marks the page not ready even when
  the crash-loop guard declines another reload.
- **`UIFileSharingEnabled` in `Info.plist` is inert** now that nothing writes to
  Documents. Safe to delete.
- **`loadVolumes`-then-`closeDrawing` opens a brief window** where a RAF-driven
  `drawScene` can see the new volume with the old drawing's dims. The reorder is
  still right (it prevents silent drawing loss), but NiiVue offers no atomic
  swap-and-close. Inspection only, not reproduced.

## Audit trail

`audit_response.md` holds the reply to the last external review, including the
crosshair regression and the loader bugs it uncovered. Convention in this repo:
an external reviewer leaves `audit_temp.md`, the reply goes in `audit_response.md`,
and `audit_temp.md` is deleted. Both are gitignored via `audit*.md`.
