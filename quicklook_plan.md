# Quick Look Preview Extension Plan

Status: product decisions approved. This plan adds a Finder Quick Look preview
to the existing Mac Catalyst app without changing the app into a general file
handler.

## Product contract

- Target Finder Quick Look on macOS through the Catalyst app. Keep iOS/iPadOS
  Files integration out of v1.
- Add a view-controller-based Quick Look Preview Extension using
  `UIViewController` and `QLPreviewingController`.
- Host a minimal offline NiiVue page in `WKWebView`. Reuse the host app's scoped
  scheme transport; do not revive a base64 file bridge.
- Permit viewing interactions only: resize, orbit, zoom, slice scrolling, and
  crosshair movement. Exclude drawing, saving, settings, menus, and links.
- Show voxel data as equal-size Axial, Coronal, Sagittal, and Render quadrants.
  Use neurological orientation and an initially centered crosshair.
- Overlay compact technical metadata: format, dimensions, voxel spacing and
  units, datatype, frame count, file size, orientation, and physical field of
  view. Do not expose free-text description or patient-adjacent fields.
- For 4D data, load frame zero only and report the total frame count. Do not
  animate or provide a time control in v1.
- Show meshes and streamlines in a fitted 3D render view.
- Use concise in-preview fallbacks for malformed, inaccessible, unsupported,
  oversized, or graphics-incompatible files. Never leave a blank canvas.
- Remain fully offline — **by construction, not by entitlement**. The extension
  *must* carry `com.apple.security.network.client`: without it WebKit refuses to
  start its auxiliary processes and the preview is a black rectangle (proved in
  Milestone 0.5, owner-approved 2026-08-01). Offline is then enforced by bundled
  assets only, a self-only CSP, a navigation delegate restricted to the app
  scheme and host, and no remote URLs in any runtime bundle. The entitlement
  grants a capability the extension never exercises; Milestone 8 must verify no
  network access actually occurs.
- Register only the file types required by the extension. Do not add the main
  app to Finder's **Open With** list.
- Preserve the existing iOS/Catalyst 16.4 deployment floor and build for both
  Apple Silicon and Intel Macs.
- Defer a Finder Thumbnail Extension until after the preview extension ships.

## Transport decision

Build the scoped file transport in the host app before the Quick Look extension.
The app's original base64 import path was a memory and latency problem; commit
`32569d3` replaced it with `BundleSchemeHandler`. Making Quick
Look the first consumer would leave that blocker in the shipped app while a new
feature is being developed. The host now owns the first implementation: an opaque
same-origin route, security-scoped access, bounded native reads, cancellation, and
request/session generations.

Quick Look should reuse and factor that transport when its extension target is
added. The extension still needs its own lifecycle and sandbox policy, but it
should not introduce a second file-delivery design or revive a base64 bridge.

Apple references:

- [Quick Look overview](https://developer.apple.com/documentation/quicklook/)
- [QLPreviewingController](https://developer.apple.com/documentation/quicklook/qlpreviewingcontroller)
- [Preparing a file preview](https://developer.apple.com/documentation/quicklookui/qlpreviewingcontroller/preparepreviewoffile%28at%3Acompletionhandler%3A%29)
- [Data-based previews](https://developer.apple.com/documentation/quicklookui/qlpreviewprovider)

## Milestone 0.5 results — RUN, and the gate is PASSED (2026-08-01)

The spike was built in a throwaway git worktree so it never touched the repo, and
was driven by Finder/`qlmanage` against an ad-hoc-signed Catalyst build. Its code
is gone; these findings are the deliverable.

**Decision: proceed to Milestone 1** — with one product-contract conflict that
needs an owner ruling first (see N1).

### R1 — Can NiiVue render inside the extension? **YES.**

Measured from inside the extension process, previewing a 9.1 MB uncompressed
NIfTI (188×256×190):

| Probe | Result |
| --- | --- |
| WebGL2 context | **available** |
| Renderer / vendor | **`Apple GPU` / `Apple Inc.`** — real hardware, not software |
| `MAX_TEXTURE_SIZE` / `MAX_3D_TEXTURE_SIZE` | 16384 / **2048** |
| `navigator.gpu` (WebGPU) | absent — same as the host app, so `backend: 'webgpu'` downgrades up front |
| `attachToCanvas` | **37 ms** |
| `loadVolumes` → drawn | **257 ms** |
| Total, `preparePreviewOfFile` → `loaded` | **294 ms** (target is ≤2 s) |
| Rendered output | **visually confirmed by the owner** in the Finder preview panel |

Both DOM *and* the WebGL canvas composite into the Quick Look preview.

### N1 — NEW BLOCKER: WKWebView requires the network entitlement (contract conflict)

Without `com.apple.security.network.client` the **WebKit content process dies
instantly** — twice, before any navigation commits — and the preview is a black
rectangle. Adding it makes everything above work. Nothing else changed.

This directly contradicts the product contract line *"Remain fully offline. Do not
add a network entitlement to the extension."* It is not optional: WebKit will not
start its auxiliary processes in a sandboxed host without it, even for a purely
local bundled page.

**Owner decision required.** The recommendation is to take the entitlement and
keep the extension offline *by construction* instead of by entitlement — bundled
assets only, a self-only CSP, a navigation delegate that allows only the app
scheme/host, and no remote URLs in any runtime bundle. The entitlement grants a
capability the extension then never exercises. If that is unacceptable, the
feature needs a non-WebKit rendering path and the plan changes fundamentally.

### R2 — Memory: proceed, but Milestone 7 budgets become entry criteria

| Process | Resident, volume loaded |
| --- | --- |
| Extension process itself | **~16 MB** |
| WebKit `WebContent` | ~123–149 MB |
| WebKit `GPU` | ~169–226 MB |

The extension process is almost free; essentially all of the cost is in the shared
WebKit processes, and those are shared with the Catalyst app rather than charged
to the extension's own jetsam limit. Nothing was killed at these sizes and the
preview completed comfortably. R2's worry — that NiiVue's *baseline* footprint
alone would exceed the extension budget — did not materialise on macOS. Treat the
Milestone 7 budgets as entry criteria anyway; this was one small file.

### R3 — Signing and discovery: **ad-hoc is sufficient. No dev certificate needed.**

`CODE_SIGN_IDENTITY="-"` + `lsregister -f -R` + `pluginkit -a` was enough for
Quick Look to invoke the extension. `preparePreviewOfFile` fired, and the
previewed file arrived **readable with the correct byte count** — so the sandbox
grants document read access without any broad entitlement. Every Finder-facing
exit gate in this plan is runnable on this machine. R3 is closed.

### Other findings that change later milestones

- **UTI declarations must live in the CONTAINING APP's `Info.plist`, not the
  extension's.** Verified both ways: declared only in the appex, the test file
  resolved to a `dyn.*` type and never matched; moved into the app's `Info.plist`,
  it resolved immediately. This affects every UTI in Milestone 1.
- **UTI landscape, measured (this supersedes an earlier wrong note in this file
  that said `gov.nih.nifti-1` was not an Apple type — that check grepped a binary
  plist and missed it).** Apple's `/System/Library/CoreServices/CoreTypes.bundle`
  **does** declare `gov.nih.nifti-1` (description "NIfTI-1", reference URL
  `nifti.nimh.nih.gov`, OSType `NII1`, extension `nii`). Verified resolution on
  this machine with the competing NIfTIViewQL registration removed:

  | File | Resolves to | Consequence for Milestone 1 |
  | --- | --- | --- |
  | `.nii` | `gov.nih.nifti-1` (**Apple system UTI**) | **Reuse it.** Do not namespace our own — decided by the owner. |
  | `.nii.gz` | `org.gnu.gnu-zip-archive` (**generic gzip**) | We must export our own compound type. This is the release gate the plan already flags. |

  Apple's only other relevant declarations are `ca.mcgill.mni.bic.mnc` (minc) and
  `org.nema.dicom`. There is **no** system type for mgh/mgz, nrrd, mha/mhd, gii,
  mz3, tck/trk/trx — all of those need exported declarations.

  `gov.nih.nifti-1-gzip` existed on this machine only because NIfTIViewQL declared
  it; it disappeared when that registration was removed. That name is therefore
  free to re-declare, and matching it keeps us consistent with the de-facto
  convention rather than inventing a third identity for `.nii.gz`. It must conform
  to `org.gnu.gnu-zip-archive`, and the extension must **never** register for
  `org.gnu.gnu-zip-archive`/`public.gzip` itself.

  Competitor status on this machine: NIfTIViewQL is **removed** — it was never
  installed to `/Applications` or `~/Library/QuickLook`; its only registration came
  from a build product inside its own source checkout, which has been deleted.
  The source checkout at `/Users/chris/src/NIfTIViewQL` remains and would
  re-register if rebuilt.
- **The scheme handler must return `HTTPURLResponse`, not `URLResponse`.** With a
  plain `URLResponse`, `fetch()` reports status 0 / `ok: false` and NiiVue fails
  the load with "fetchVolume failed". The host app already does this correctly;
  Milestone 3 must not regress it when the transport is factored out.
- **The Vite multi-page build works.** Two entries produced a shared
  `niivue-*.js` chunk (1.32 MB) plus a 1.7 kB Quick Look entry — confirming the
  "Build organization" assumption that NiiVue can be shared between the app and
  the preview rather than duplicated.
- **Do not gate anything on canvas pixel sampling.** `drawImage`-based non-black
  pixel counting reported **0 lit pixels on a preview that renders correctly**;
  NiiVue's context has no `preserveDrawingBuffer`, so the buffer is unreadable in
  the same frame or a later one. Milestone 2's "deterministic synthetic success
  state" needs a different liveness signal. Visual confirmation is ground truth.
- **`qlmanage -p` emits nothing from a non-GUI shell session** and cannot be used
  as the automated driver. Finder spacebar worked. Extension-side logging must go
  to a file inside the extension's sandbox container (`NSHomeDirectory()/tmp`);
  `os_log` was not readable from the same shell.

## Milestone 1 results — target landed, routing 11/12, `.nii.gz` gate FAILED (2026-08-01)

Delivered: the `QuickLookPreview` target (`com.niivue.mobile.QuickLookPreview`),
embedded in the Catalyst app, sandboxed, with the network entitlement documented
as a WebKit requirement rather than a networking one. The preview controller is
deliberately a stub that reports the routed type and file size — the rendering
shell is Milestone 2, and keeping them apart means a routing failure here cannot
be mistaken for a rendering one.

**Builds green on all three destinations** (R5 satisfied): Mac Catalyst, iOS
Simulator, and generic iOS device. The extension target does not break the iOS
builds.

### Routing: 11/12 advertised types, 9/9 negative tests

| Fixture | Resolves to | |
| --- | --- | --- |
| `.nii` | `gov.nih.nifti-1` (Apple's) | routed |
| **`.nii.gz`** | **`org.gnu.gnu-zip-archive`** | **no dedicated type — see resolution** |
| `.mgh` / `.mgz` | `edu.mgh.freesurfer.mgh` / `.mgz` | routed |
| `.nrrd` | `org.nrrd.nrrd` | routed |
| `.mha` / `.mhd` | `org.itk.metaimage` / `-header` | routed |
| `.gii` | `org.nitrc.gifti` | routed |
| `.mz3` | `com.niivue.mz3` | routed |
| `.tck` / `.trk` / `.trx` | `org.mrtrix.tck` / `org.trackvis.trk` / `org.trx.trx` | routed |

Negative tests all pass — plain `.gz`, `.zip`, FreeSurfer `.white/.pial/.inflated/.sphere`,
and `.obj/.stl/.ply` are **not** intercepted.

### `.nii.gz` gets no dedicated type — a platform limit, not a bad declaration

**Wording note:** "`.nii.gz` does not route" would be too strong, and an earlier
revision of this file said it. It routes fine *via the generic gzip type*. What
is impossible is a **dedicated compound UTI**. Keep the distinction — the two
readings imply completely different release gates.

`gov.nih.nifti-1-gzip` **is** registered and **does** carry the
`public.filename-extension` tag `nii.gz` — confirmed via `UTType`. It still never
matches, because **macOS resolves a file's type from the LAST extension component
only.** Proof: Apple's own `org.gnu.gnu-zip-tar-archive` declares only `tgz`, and
a real `.tar.gz` file on this machine resolves to `org.gnu.gnu-zip-archive` too.
Compound extensions are not a supported concept in the UTI system.

This trips the exit gate the plan already wrote: *"`.nii.gz` compound-extension
routing works… Failure blocks the release and triggers a narrowly scoped UTI
redesign."* It has failed, and it cannot be fixed by redesigning our declaration.

**Owner decision required. The options are all imperfect:**

1. **Ship `.nii` only in v1; `.nii.gz` gets no preview.** Honest and safe, but
   `.nii.gz` is the single most common format in practice, so this guts the
   feature's value.
2. **Register for `org.gnu.gnu-zip-archive` and content-sniff.** The extension
   would become the previewer for *every* `.gz` on the machine, reading the gzip
   header to decide whether it holds a NIfTI and showing a neutral "Gzip archive,
   N bytes" fallback otherwise. This is explicitly forbidden by the current
   product contract. Mitigating context: macOS ships no rich `.gz` preview today,
   so the practical loss to the user is small — but it does claim another
   ecosystem's file type, and tarballs would route through us.
3. **Ask users to decompress.** Not credible.

Recommendation: **option 2, narrowly**, with a hard rule that any gzip whose
payload is not a NIfTI falls back to plain archive metadata and never renders —
plus an explicit contract amendment, since it reverses a stated prohibition.
If that is unacceptable, option 1 and re-scope v1.

### Resolution — option 2, owner-approved 2026-08-01. Gate now PASSES 12/12.

The extension claims `org.gnu.gnu-zip-archive` and decides by content.
`gov.nih.nifti-1-gzip` was **removed** from the app's exported declarations
rather than left in place: it registers and never matches, so keeping it would
be dead config that reads as though `.nii.gz` were handled.

`QuickLookPreview/GzipPeek.swift` inflates a bounded prefix — at most 64 KB read,
at most 1 KB inflated — and `VolumeSniff.isNIfTI` checks `sizeof_hdr` (348/540)
**and** the magic string (`n+1`/`ni1` at 344, `n+2`/`ni2` at 4), in both byte
orders. The size field alone is not sufficient; 348 is a plausible leading int32
in arbitrary data.

Verified by compiling the real Swift implementation against real files:

| Fixture | Inflated | NIfTI? | |
| --- | --- | --- | --- |
| `vol.nii.gz` | 1024 B | yes | renders |
| `archive.tar.gz` | 1024 B | no | archive metadata only |
| `plain.gz` | 6 B | no | archive metadata only |
| `vol.mgz` (gzipped non-NIfTI) | 1024 B | no | archive metadata only |
| `vol.nii` (not gzip) | n/a | no | routed by its own type |

**Standing obligation:** because this extension now previews every `.gz` on the
machine, `shouldRender` must stay strict. Do not loosen the sniff, and do not let
a future milestone render on the strength of the filename alone.

#### Prior art — both comparable tools do exactly this

Checked directly, and it independently validates the approach:

- **NIfTIViewQL** (`/Users/chris/src/NIfTIViewQL`) declares
  `gov.nih.nifti-1-gzip` tagged with **both `nii.gz` and bare `gz`**, and also
  lists `org.gnu.gnu-zip-archive` in `QLSupportedContentTypes`. Its controller
  then strips `.gz` and checks for an inner `.nii` — a **filename** test. For
  anything else it **returns an `NSError`** so another extension can handle the
  file.
- **MIQ** (`/Users/chris/src/MIQ`) lists its narrow `org.nifti.nii-gz` *plus*
  `public.gzip` and `org.gnu.gnu-zip-archive`, matches on full path suffix
  (`.nii.gz`, `.mgh.gz`, `.mif.gz`) in `MIQFileKind.swift`, and documents the
  broad `.gz` claim and its conflicts in its README.

Two things follow. First, broad-gzip-plus-validation is the established solution,
not a hack peculiar to this project. Second, **our discrimination is stronger
than either**: both decide by filename, which mis-accepts a renamed file and
mis-rejects a correctly-formed one, whereas `GzipPeek` reads the actual header.
Keep it that way.

NIfTIViewQL's decline-by-`NSError` is worth adopting for foreign archives: it
hands a `.tar.gz` back to whatever would otherwise preview it, instead of
replacing that with our own panel. Its being in shipping use is evidence Quick
Look falls back cleanly.

## Milestone 2 results — shell and shared web build landed (2026-08-01)

Delivered:

- **`NiiVueWeb` aggregate target** owns the single web build. The app's own
  script phase was removed and both the app and the extension now depend on the
  aggregate, so two targets can no longer race to rewrite the same gitignored
  `dist/`. Verified by deleting `React/dist` entirely and doing a clean build:
  it regenerates once and lands in both the app and the `.appex`.
- **Vite multi-page build.** `index` + `quicklook` entries emit NiiVue as one
  shared chunk (1.32 MB) with a 2 kB preview entry, instead of duplicating the
  library into two bundles.
- **`quicklook.html` + `src/quicklook.ts`** — loading shell with spinner,
  adaptive metadata strip that wraps rather than clips, fallback panel, a
  `ResizeObserver` that keeps the drawing buffer matched to the panel, and
  `prefers-reduced-motion` handling.
- **`PreviewSchemeHandler`** — bundle assets only, path-component containment,
  `HTTPURLResponse` with a self-only CSP and `nosniff`, main-queue-confined task
  callbacks. No document route exists in this milestone *by construction*.
- **`PreviewViewController`** — typed `ready`/`loaded`/`failed` contract, a
  single completion gate that cannot fire twice, a 10 s readiness timeout, and a
  navigation delegate that allows only the bundled page.

Kept separate from `bridge.ts` on purpose: the app's bridge is a two-way control
surface with drawing and export paths, and a preview is read-only and
single-shot. Sharing it would ship those paths into an extension that must not
have them.

### Exit gate

| Criterion | Status |
| --- | --- |
| Clean build embeds the extension and both web entries | **pass** (verified from a deleted `dist/`) |
| iOS Simulator / generic iOS device / Mac Catalyst all build | **pass** |
| No network access in the runtime bundle | **pass** — the preview's own chunks (`quicklook-*.js`, `niivue-*.js`) contain **zero** remote URLs; the only hit anywhere is `https://react.dev` in the *app* entry, an unfetched React error link that the preview page never loads |
| Spacebar shows the loading shell then a deterministic synthetic state | **awaiting visual confirmation** — `qlmanage -p` cannot drive this from a non-GUI shell |

### Foreign archives are now declined, not overpainted

Following NIfTIViewQL's shipping behaviour, a `.gz` that is not a NIfTI gets an
`NSError` back from `preparePreviewOfFile` rather than our own panel, so a
`.tar.gz` keeps whatever preview it would otherwise have had. The filename is
consulted only when the *bytes* are inconclusive — a gzip variant `GzipPeek`
cannot inflate — where a user who named a file `.nii.gz` is better served by a
visible failure than by being told it is a foreign archive.

## Milestone 3 results — scoped transport and lifecycle landed (2026-08-01)

Delivered:

- **`PreviewSchemeHandler` gained the document route**, factored from the host
  app's `BundleSchemeHandler`: a UUID token plus the original filename, both
  matched exactly; the filename percent-encoded with `.alphanumerics` (the
  `URLComponents.path` `%` trap); path-component containment; 1 MiB chunked
  `FileHandle` reads; and the main-queue-confined `deliver(_:_:)` in its `sync`
  form, so a large file cannot pile up as pending main-queue blocks. The
  descriptor closes on every exit including cancellation.
  `invalidateDocument()` drops the route on teardown.
- **Deliberately copied, not linked.** The app's handler lives inside
  `ContentView.swift`; sharing the file would drag the whole app UI into the
  extension. The invariants are the shared asset, and both copies carry the
  same comments explaining why.
- **Generation-scoped lifecycle.** One counter, bumped on every request *and*
  every teardown; timers and `callAsyncJavaScript` completions carry the
  generation they were issued under. Teardown runs from `viewDidDisappear`,
  from a replacement request, and from `deinit`.
- **Two timeouts, not one.** Readiness (10 s, page never came up) completes
  with an error so Quick Look shows its own panel rather than an indefinite
  spinner; load (20 s, page is up) asks the page to draw its own `timeout`
  fallback. A single timeout could only do one of those correctly.
- **Structured failure codes** — `PreviewFailure` in Swift mirrored by
  `FailureCode` in `quicklook.ts`, crossing as bare strings.
- The size cap fails closed on an unreadable size, matching the app's import
  check. Its number is provisional; Milestone 7 owns the real one.

### Two lifecycle defects found in the Milestone 2 code

- **`config.userContentController.add(self, …)` was a retain cycle.** The
  controller, and through it the web view, scheme handler and security scope,
  would have outlived every preview — which is precisely what the "twenty
  open/dismiss cycles" gate exists to catch. Now goes through a
  `WeakScriptMessageHandler`, as the host app does.
- **The navigation delegate did not exclude the document route.** It had no
  document route to exclude in Milestone 2; it does now, and the picked-file
  route must never become the top-level document.

### Exit gate

| Criterion | Status |
| --- | --- |
| A selected fixture reaches JavaScript with byte count and filename intact | **pass** — automated, see below |
| Cancelling during asset and document load closes resources, no late mutation | **pass** by construction (main-queue confinement + generation scoping); exercised by hand in Finder |
| Repeat open/dismiss cycles retain nothing | **pass** — the retain cycle above was the one real obstacle |
| All three destinations still build | **pass** |

## Milestone 4 results — voxel previews and metadata landed (2026-08-01)

Delivered:

- **One load path for every voxel format.** Every NiiVue volume reader
  normalizes into a NIfTI header, so NIfTI, MGH/MGZ, NRRD and MetaImage need no
  per-format branching — `loadVolumes` plus one header extractor covers them.
- **`customLayout`, not `multiplanarType`.** Four fixed equal quadrants in
  reading order (Axial, Coronal, Sagittal, Render). `customLayout` overrides
  every built-in layout mode, so the preview cannot drift with NiiVue's
  multiplanar heuristics. `isEqualSize = true` additionally draws all three
  orientations at one physical scale, so the panels are comparable.
- **`limitFrames4D: 1`** — verified to work: a 7-frame fixture loads
  `nFrame4D = 1`, `nTotalFrame4D = 7`, and `img.length` is exactly one frame.
  The strip reads **`frames 1 of 7`**, which states the whole contract in one
  field.
- **`src/preview-metadata.ts`** — format, dims, voxel size with units, physical
  FOV, datatype, orientation code, frame count, file size. Closed by
  construction: every field is a number, a code, or the filename, so
  `descrip`, `aux_file`, `intent_name` and `db_name` are never read.
- Dims and spacing are the **file's own** `hdr` values, not NiiVue's
  RAS-reordered view, so a preview matches `fslhd`; the reorientation is
  reported separately as the orientation code, derived by inverting `permRAS`.
- **Three outcomes, not two.** `loaded` + render; `loaded` + *metadata-only*
  (the file parses but has no ordinary voxel view); and `failed`. Metadata-only
  posts `loaded` on purpose — a `failed` would make the native side hand Quick
  Look its generic panel and throw away the header we just extracted.

### What NiiVue actually does with malformed input, measured

Three assumptions were wrong and were corrected against the library rather than
around it:

| Fixture | NiiVue's behaviour | Preview outcome |
| --- | --- | --- |
| 4D, 7 frames | `limitFrames4D` honoured exactly | renders frame 0, reports `1 of 7` |
| complex64 | **throws** `Unsupported datatype: 32` — never becomes a volume | `unsupported`, not `unreadable`; the message is matched narrowly and degrades to `unreadable` |
| truncated (⅓ of voxels) | **loads happily**, `img.length` 4480 vs `nVox3D` 13440 | detected by comparing the two → metadata-only |
| zero-dimension | throws | fallback panel |
| garbage | throws | fallback panel |

The truncated case is the one that mattered: it would otherwise have drawn a
head with the bottom third missing and no indication why.

Because complex NIfTI never loads, the metadata-fallback branch for it is
reachable only via the spectroscopy path (`isImaginary`), which is where NiiVue
does produce a complex-typed volume. That branch is kept for that reason, not
speculatively.

### Exit gate

| Criterion | Status |
| --- | --- |
| Each core voxel fixture produces four nonblank tiles and correct metadata | **pass** — automated, per-quadrant lit-pixel counts |
| A 4D fixture reports its frame count while retaining only frame zero | **pass** |
| Corrupt, truncated, zero-dimension, unsupported-datatype → fallback, not blank or crash | **pass** |

Still open for Milestone 5: mesh and tract requests are **declined**
(`unsupported`) rather than mis-drawn as an empty render tile.

## Regression coverage added for Milestones 3–4

`NiiVue/React/tests/preview-regression.mjs`, run with `npm run test:preview`.
**48 checks, all passing.** Same shape as `bridge-regression.mjs`: it drives the
built `dist/` in headless Chromium over a throwaway http server, so it exercises
the bytes the extension bundles.

Two things in it are worth not rediscovering:

- **Canvas pixel sampling *is* possible after all — from outside the page.**
  Milestone 0.5 concluded "do not gate anything on canvas pixel sampling"
  because in-page `drawImage` reported zero lit pixels (no
  `preserveDrawingBuffer`). The compositor does have the frame, so Playwright's
  screenshot captures it correctly; handing that PNG *back* to the page to
  decode gives per-quadrant lit-pixel counts. The four-tile exit gate is
  therefore automated rather than eyeballed. The original finding still holds
  for anything sampling from inside the page, which is what the extension would
  have to do.
- **Fixtures are generated, not collected** — `tests/preview-fixtures.mjs`
  writes NIfTI-1 files with exact dims, spacing, affine, datatype and
  truncation. R4 in this plan notes that five of the eight v1 families have no
  fixture anywhere in the monorepo; for the *properties* under test (4D,
  complex, zero-dimension, truncated) no real scan is more precise than a
  synthesised one, and Milestone 0 already allows a deterministic generation
  step in place of a redistributable file.

What it still does not cover is everything native: the chunked reads, the
document token, security scope, the Quick Look completion gate and the timeouts
all need Finder on a Mac.

## Risks and open questions

Added after a feasibility review of the plan against the codebase. Everything the
plan assumes about APIs checked out (see *Verified assumptions* below); these are
the things that did not, or that the plan sequences in a way I would change.

### R1 — The largest technical unknown is proved far too late (blocking) — **RESOLVED, see Milestone 0.5 results**

Nothing in Milestones 0–3 proves that **NiiVue can render at all inside a Quick Look
extension process**. A preview extension is a separate, heavily sandboxed,
memory-capped process; WebGL/WebGPU availability and GPU-process access inside it
are not guaranteed and are not documented either way. Milestone 2's exit gate — "a
deterministic synthetic success state" — can be satisfied by DOM-only content and
would not catch this.

If WebGL does not work there, Milestones 2–7 are wasted work and the product
contract itself has to change (e.g. render server-side to a static image, or drop
the feature). This must be settled first. See the new **Milestone 0.5**.

### R2 — Memory headroom may be the real constraint (blocking, coupled to R1) — **MEASURED, proceed**

Measured on the existing app with the 4 MB demo volume: **~247 MB resident in the
WebKit content process** and ~234 MB in the app process. Most of that is baseline —
the JS bundle, NiiVue's WebGL textures and gradient volumes — not image data.

Quick Look extensions run under materially tighter jetsam limits than an app. If
NiiVue's *baseline* WebKit footprint approaches the extension's budget before any
file is loaded, the resource policy in Milestone 7 is not tuning, it is a
feasibility question. Measure it in Milestone 0.5, not Milestone 7.

### R3 — Extension discovery may be untestable on this machine (blocking for local QA) — **RESOLVED: ad-hoc works**

Finder discovers Quick Look extensions through Launch Services and runs them via
`pluginkit`. This machine has **no Apple Development certificate** — only a
`Developer ID Application` cert, which does not sign development builds — so the
Catalyst app is currently built ad-hoc (`CODE_SIGN_IDENTITY="-"`) from a
`DerivedData` path. Whether Finder will register and invoke an extension embedded
in such a bundle is unverified, and the plan does not mention signing at all.

Resolve before Milestone 1: either confirm ad-hoc + `lsregister` is sufficient, or
obtain a development certificate (Xcode → Settings → Accounts). If neither works,
every Finder-facing exit gate in this plan is unrunnable.

### R4 — Fixture coverage is thinner than Milestone 0 implies

The nearest fixture source is `/Users/chris/src/mono/packages/dev-images`, which is
a **private, Git-LFS** package explicitly "not published to npm" — so
redistribution needs a decision, not just selection. Actual coverage against the v1
matrix:

| Format | Fixtures available | Note |
| --- | --- | --- |
| `.nii` / `.nii.gz` | 30 | ample |
| `.mgz` | 3 | ample |
| `.mz3` | 8 | ample |
| `.tck` / `.trk` / `.trx` | 1 / 1 / 3 | sufficient |
| `.mgh` | **0** | derive from `.mgz` (plan already anticipates this) |
| `.nrrd` | **0** | none anywhere in the monorepo |
| `.mha` | **0** | none |
| `.mhd` | **0** | none — and this is the Milestone 6 gate |
| `.gii` | **0** | none |

Five of the eight v1 families have no fixture, and four of those have no obvious
source. That is a real Milestone 0 lift on the critical path for Milestones 4–6.
Either budget for authoring/converting them, or narrow the v1 matrix to the
formats we can actually test.

### R5 — The extension must not break the iOS targets

The project builds for iOS device, iOS Simulator, and Mac Catalyst. A Quick Look
preview extension is Catalyst/macOS-only. Adding the target must not appear in the
iOS destinations or break `xcodebuild -destination 'generic/platform=iOS'`. Set
`SUPPORTED_PLATFORMS` on the extension target explicitly and keep the existing iOS
builds in the Milestone 1 exit gate, not only in Milestone 8.

### R6 — "Both Apple Silicon and Intel" is stated but not testable here

The project sets no explicit `ARCHS` (so Release uses `ARCHS_STANDARD`) and
`ONLY_ACTIVE_ARCH = YES` for Debug. Building universal is achievable; **verifying**
Intel is not — this is an Apple Silicon machine, and Intel Mac support is being
wound down across recent macOS releases. Either drop the Intel claim to
"builds universal, verified on Apple Silicon only", or identify a test machine.

### Ambiguities to settle before starting

1. **"Meaningful content within two seconds" — measured from when?** Finder
   invocation, `preparePreviewOfFile` entry, or first byte delivered? These differ
   by the extension launch cost, which we do not control. Propose: from
   `preparePreviewOfFile` entry to the `loaded` message, reported separately from
   cold-start extension launch.
2. **"Neurological orientation"** maps to `isRadiological = false` in NiiVue. Say so
   explicitly — the host app exposes this as a user toggle and the mapping is not
   self-evident.
3. **The shared web-build target does change the existing app.** Milestone 0 says
   not to mix this work with unrelated fixes, but the `NiiVueWeb` aggregate target
   in "Build organization" necessarily rewrites the app's existing script phase.
   That is fine — but call it out as deliberate shared-infrastructure work rather
   than letting it look like scope leakage.
4. **The working tree must be landed first.** There are currently ~15 uncommitted
   files from the audit rounds. Milestone 0's "distinct reviewable changeset"
   requires committing or shelving those before the first Quick Look commit.
5. **`.trx` is a zip container.** Confirm the reader's I/O shape is compatible with
   the bounded-chunk scheme transport before Milestone 5, rather than discovering a
   whole-file requirement late.

### Verified assumptions (checked, no action needed)

- `QLPreviewingController` **is** available to Mac Catalyst —
  `MacOSX.sdk/System/iOSSupport/.../QuickLook.framework/Headers/QLPreviewingController.h`.
- NiiVue `1.0.0-rc.11` has readers for every v1 format: `nii`, `mgh`/`mgz`,
  `nrrd`/`nhdr`, `mha`/`mhd`, `mif`/`mih`, AFNI `head`, `gii`, `mz3`, and tract
  readers `tck`, `trk`, `trx`, `tt`.
- The APIs the plan depends on exist: `limitFrames4D` and `urlImageData` on
  `ImageFromUrlOptions`, and `customLayout` for the fixed 2×2 grid.
- The extension bundle identifier convention (`com.niivue.mobile.QuickLookPreview`
  under host `com.niivue.mobile`) is correct.

## v1 format boundary

| Family | Extensions | v1 behavior | Notes |
| --- | --- | --- | --- |
| NIfTI | `.nii`, `.nii.gz` | MPR + Render | Frame zero only for 4D; compound-extension UTI routing is a release gate. |
| MGH | `.mgh`, `.mgz` | MPR + Render | Generate a small `.mgh` fixture from a licensed `.mgz` fixture if needed. |
| NRRD | `.nrrd` | MPR + Render | Self-contained NRRD only; detached `.nhdr` is out of scope. |
| MetaImage | `.mha` | MPR + Render | Self-contained files are required. |
| MetaImage detached | `.mhd` | MPR + Render if its single sibling payload is accessible; otherwise metadata fallback | Full support is controlled by the Milestone 6 feasibility gate. |
| GIFTI | `.gii` | 3D render for geometry; metadata fallback for layer-only files | Do not search the filesystem for a companion surface. |
| MZ3 | `.mz3` | 3D render | Use NiiVue's native mesh reader. |
| Streamlines | `.tck`, `.trk`, `.trx` | 3D render | Use NiiVue's mesh/tract loader and default directional coloring. |

Deferred formats:

- FreeSurfer meshes (`.white`, `.pial`, `.inflated`, `.sphere`, `.orig`,
  `.smoothwm`, `.qsphere`): reader support exists, but the generic extensions
  and file-association risk need a separate release decision.
- AFNI `.niml.tract`: no reader or fixture exists in the current NiiVue source;
  implement this upstream before adding it to Quick Look.
- OBJ, STL, and PLY: NiiVue can read them, but Finder and specialist mesh apps
  are better owners of these common types.
- CIFTI, spectroscopy NIfTI, complex data, and vector NIfTI: allow NiiVue's
  best-effort load, then show technical metadata fallback if the result is not
  an ordinary displayable voxel volume.

## Architecture

```text
Finder
  -> Quick Look Preview Extension
      -> PreviewViewController
          -> scoped custom-scheme file server
          -> bundled quicklook.html in WKWebView
              -> NiiVue volume or mesh loader
              -> ready / metadata / error message
          -> complete the Quick Look request exactly once
```

### Native extension

- `PreviewViewController` owns one `WKWebView`, conforms to
  `QLPreviewingController`, and coordinates one generation token per requested
  file.
- A preview-specific `WKURLSchemeHandler` serves only:
  - bundled web assets below the extension's known resource root;
  - the exact requested document URL;
  - one explicitly approved same-directory `.mhd` sidecar.
- Validate scheme, host, token, and path components. Do not use string-prefix
  containment checks, private WebKit preferences, broad directory access, or
  interpolated JavaScript.
- Read file payloads asynchronously in bounded chunks. Close the file as soon
  as delivery finishes; Apple advises against holding descriptors open for the
  lifetime of a preview.
- `preparePreviewOfFile` starts work without blocking the main thread. Its
  completion handler fires once after either useful content or the fallback
  view is ready.
- Teardown invalidates the generation token, stops scheme tasks, closes file
  handles, stops WebKit loading, and destroys the NiiVue instance.

### Web preview

- Add a dedicated `quicklook.html` and TypeScript entry point. It should use
  NiiVue directly rather than adding another React tree.
- Extract only the NiiVue construction options that genuinely need to be
  shared with the app. Avoid a broad app refactor.
- The native side passes a small structured request containing the scoped URL,
  display name, format family, file size, and optional sidecar URL.
- Volume requests call `loadVolumes` with `limitFrames4D: 1` and apply the fixed
  four-quadrant custom layout.
- Mesh and tract requests call `loadMeshes`, switch to render mode, and fit the
  camera after loading.
- The page posts typed `ready`, `loaded`, and `failed` messages. `loaded`
  includes sanitized header metadata needed by the overlay.
- A `ResizeObserver` keeps the canvas sharp as Finder resizes the preview.
- Use a near-black canvas and an adaptive, high-contrast metadata strip. The
  narrow layout may abbreviate labels but must not hide values.

### Build organization

- Add one deterministic web-build script used by both the app and extension.
- Prefer a small aggregate `NiiVueWeb` target with an explicit output stamp;
  make the app and preview extension depend on it. This avoids two targets
  racing to rebuild the same ignored `dist/` directory.
- Build the existing app entry and the new Quick Look entry from one Vite
  multi-page build so NiiVue code can be shared between chunks.
- Use the lockfile on clean installs, validate the supported Node version, and
  keep runtime bundles free of remote URLs.
- Test the pinned NiiVue `1.0.0-rc.11` first. Upgrade only if a v1 format or
  lifecycle requirement fails; pin the replacement exactly and record why.

## Milestones

### Milestone 0 — baseline and fixtures

Deliverables:

- Land or shelve the ~15 uncommitted files from the audit rounds first, so Quick
  Look work starts from a clean tree and is reviewable on its own.
- Start Quick Look work as a distinct reviewable changeset; do not mix it with
  unrelated audit fixes. (The shared web-build target in "Build organization" is
  the one deliberate exception — it necessarily touches the app.)
- Record passing baseline checks for the React build and existing iOS/Catalyst
  app.
- Create a fixture manifest with source path, format, size, license, and hash.
- Select the smallest useful licensed examples for each v1 format. Derive
  compact uncompressed `.nii`/`.mgh` and detached `.mhd` fixtures from licensed
  compressed/self-contained samples where practical.
- Include malformed and truncated fixtures without clinical or identifying
  metadata.

Exit gate:

- Every v1 extension has a redistributable fixture or a documented deterministic
  fixture-generation step.
- Existing app behavior and build results are captured before target changes.

### Milestone 0.5 — feasibility spike (kill gate)

Throwaway code. The point is to answer three questions before any real
implementation exists, because a "no" on any of them changes the product.

Deliverables:

- A minimal Quick Look preview extension embedded in the Catalyst app that loads a
  bundled HTML page in a `WKWebView` and is invoked by Finder for one hardcoded
  test extension. No scheme handler, no transport, no metadata, no fallbacks.
- The page reports, via a message handler: whether a WebGL2 context was obtained,
  the renderer string, and whether a bundled NiiVue instance rendered one bundled
  volume to a non-blank canvas.
- Resident memory of the extension and its WebKit content process, at rest and with
  that volume loaded.
- A note on how the extension was signed and registered, and whether Finder found
  it without manual `lsregister` intervention.

Exit gate and decision rule:

- **WebGL2 available and NiiVue renders inside the extension** → proceed to
  Milestone 1 as written.
- **Renders, but memory is near the extension's limit with a small volume** →
  proceed, but re-open the product contract first: the resource budgets in
  Milestone 7 become entry criteria, and the v1 format matrix may need to shrink.
- **No WebGL, or Finder will not invoke the extension on this machine** → stop.
  Do not build Milestones 2+. Escalate with the measurements; the options are a
  non-WebGL rendering path, a static-image preview, or dropping the feature.

Nothing from this milestone is intended to survive into the shipped extension.

### Milestone 1 — extension target and UTI routing spike

Deliverables:

- Add the embedded Quick Look Preview Extension target and shared scheme.
- Use a distinct bundle identifier such as
  `com.niivue.mobile.QuickLookPreview`.
- Set extension-safe APIs only, Catalyst support, the existing deployment floor,
  and universal Mac architectures.
- Give the extension the app sandbox and only file-read access demonstrated as
  necessary. Do not copy the host app's network entitlement.
- Define exact UTTypes and `QLSupportedContentTypes` entries for the v1 matrix.
  Do not add host-app document roles.
- Probe each fixture with Launch Services/Finder on a clean install. Reuse a
  stable system UTI where one exists; otherwise define a namespaced type with
  the exact filename-extension tag.
- Route `.nii.gz` by claiming `org.gnu.gnu-zip-archive` and discriminating on
  **content**. (This supersedes an earlier "never register for `public.gzip`"
  rule. That rule assumed a compound `nii.gz` UTI could work; it cannot — macOS
  resolves a type from the last extension component only, so the choice is
  broad-claim-plus-sniff or no `.nii.gz` preview at all. Owner-approved
  2026-08-01. `public.gzip` itself is still not claimed; only
  `org.gnu.gnu-zip-archive`, the type real files actually resolve to.)

Exit gate:

- Finder discovers and invokes the extension for every advertised v1 type.
- Deferred FreeSurfer extensions and common mesh files are not intercepted, and
  no type is claimed beyond the v1 matrix plus `org.gnu.gnu-zip-archive`.
- The existing iOS device, iOS Simulator, and Mac Catalyst builds all still
  succeed. The extension target must not join the iOS destinations.
- **`.nii.gz` previews, and non-NIfTI gzip does not.** The gate is
  content-sniffed routing, not resolution to a dedicated compound UTI — the
  latter is impossible on macOS. Verify with a gzipped NIfTI, a `.tar.gz`, and a
  plain `.gz`, after clearing the Quick Look cache and reinstalling the app.

### Milestone 2 — minimal preview shell and shared web build

Deliverables:

- Add the deterministic shared web-build target/script.
- Add `quicklook.html`, its TypeScript entry, canvas styling, loading state,
  metadata strip, and fallback panel.
- Add `PreviewViewController` with a bundled-page load and typed message
  handlers.
- Complete a synthetic preview request without touching document bytes.
- Make the page responsive from Finder's minimum practical preview size through
  a large resizable window.

Exit gate:

- A clean app build embeds the extension and both web entries.
- Spacebar Quick Look shows the branded loading shell and then a deterministic
  synthetic success state without launching the containing app.
- The build and runtime perform no network access.

### Milestone 3 — scoped file transport and lifecycle

Deliverables:

- Factor the host app's bounded-chunk scheme transport into the preview target and
  retain an opaque per-request document token per extension instance.
- Stream the selected file without base64, JavaScript source interpolation, or
  a second full native copy.
- Honor `WKURLSchemeTask.stop`, request replacement, view disappearance, and
  controller deinitialization.
- Add a single completion gate and readiness timeout so stale JavaScript or file
  callbacks cannot complete a newer preview.
- Add structured error codes for unreadable file, unsupported type, timeout,
  graphics failure, cancellation, and resource limit.

Exit gate:

- A selected fixture reaches JavaScript with byte count and filename intact.
- Cancelling during asset load and during document load closes resources and
  produces no late state mutation.
- Repeating open/dismiss cycles does not retain old controllers, scheme tasks,
  files, or WebViews.

### Milestone 4 — voxel previews and metadata

Deliverables:

- Implement NIfTI, MGH/MGZ, NRRD, and MHA classification and loading.
- Load only frame zero for 4D data while retaining the total frame count in
  metadata.
- Apply the fixed equal-size 2×2 layout:
  Axial, Coronal, Sagittal, Render.
- Center the crosshair, use neurological orientation (`isRadiological = false`),
  and keep orientation labels visible.
- Format dimensions, spacing/units, datatype, frame count, file size,
  orientation, and physical field of view without free-text header fields.
- Route nonstandard NIfTI that cannot produce the ordinary voxel view to the
  metadata fallback.

Exit gate:

- Each core voxel fixture produces four nonblank tiles and correct sanitized
  metadata.
- A 4D fixture reports its frame count while retaining only frame zero.
- Corrupt, truncated, zero-dimension, and unsupported-datatype fixtures produce
  the fallback panel rather than a blank view or extension crash.

### Milestone 5 — mesh and streamline previews

Deliverables:

- Load geometry GIFTI and MZ3 with `loadMeshes`.
- Load TCK, TRK, and TRX through NiiVue's tract readers.
- Select render-only mode, fit the camera, and enable orbit/zoom interaction.
- Preserve NiiVue's default directional tract coloring and useful embedded mesh
  colors.
- Detect a GIFTI file that supplies only labels/scalars and show metadata rather
  than searching for a companion surface.

Exit gate:

- Every mesh/tract fixture is visible, centered, and interactively rotatable.
- Resizing does not crop or blur the render.
- Layer-only and malformed GIFTI files produce an accurate fallback.

### Milestone 6 — detached MHD feasibility gate

Deliverables:

- Parse only a bounded header prefix to resolve one `ElementDataFile` sibling.
- Accept a plain same-directory filename only. Reject URLs, absolute paths,
  traversal, wildcard/list forms, and nested paths.
- Attempt security-scoped access to that exact sibling, expose it through a
  second opaque scheme URL, and pass it as NiiVue's `urlImageData`.
- Test local, iCloud-downloaded, and external-volume files.

Exit gate and decision rule:

- If Finder grants reliable sibling access without broad entitlements, ship a
  rendered `.mhd` preview.
- Otherwise keep `.mhd` as an explicit metadata preview that names the required
  sidecar and access limitation. Do not broaden sandbox access or copy an
  arbitrary directory to force full rendering.

### Milestone 7 — resource policy and failure UX

Deliverables:

- Profile representative small and moderate files before selecting limits.
- Establish conservative file, decoded-voxel, mesh-vertex/index, tract-point,
  and timeout budgets from measured headroom. Unknown metadata fails to the
  fallback rather than bypassing a limit.
- Ensure all heavy parsing/loading is asynchronous from the preview-controller
  callback.
- Surface initialization failures from NiiVue/WebGL to the native fallback.
- Keep technical errors concise; do not show full filesystem paths.
- Add accessibility labels for filename, format, metadata, loading, and errors.

Exit gate:

- A representative small preview becomes meaningful within two seconds on
  Apple Silicon, measured from `preparePreviewOfFile` entry to the `loaded`
  message. Report cold extension-launch cost separately — it is not ours to fix.
- Dismissal during a large load returns promptly and releases resources.
- Twenty sequential previews return near baseline memory after dismissal;
  investigate any monotonic growth.
- Oversized and deliberately hostile headers are rejected before large
  allocations.

### Milestone 8 — system verification and release

Deliverables:

- Run format-by-format Finder tests on Apple Silicon and Intel macOS where
  available.
- Cover uppercase extensions, compound extensions, Unicode filenames, spaces,
  long names, read-only files, iCloud-downloaded files, and malformed inputs.
- Verify standard Finder behavior: Space opens/closes, Escape dismisses, window
  resizing works, and extension gestures do not interfere with Quick Look.
- Verify extension discovery after clean install, app replacement, cache reset,
  and reboot/login where practical.
- Re-run the existing app's React checks and iOS/Catalyst builds. A NiiVue
  dependency update also requires the app's volume, drawing, and corrupt-file
  regression checks.
- Document supported formats, frame-zero behavior, metadata-only fallbacks,
  resource limits, extension troubleshooting, and the deferred list.

Exit gate:

- All advertised types route to the extension and meet their rendered or
  documented fallback contract.
- The host app does not launch, gain new document roles, or regress.
- No private API, network dependency, broad file entitlement, base64 document
  transport, blank failure state, stale completion, or retained file descriptor
  remains.

## Verification matrix

| Area | Required evidence |
| --- | --- |
| Build | Clean React build; clean app, extension, iOS, and Catalyst builds; universal Mac architectures. |
| Routing | Finder invocation for every advertised UTI; explicit negative tests for generic gzip and deferred formats. |
| Voxels | Nonblank four-tile output and exact sanitized header metadata for each core format. |
| Geometry | Visible, fitted, resizable, interactive mesh/tract render for each core format. |
| Failures | Malformed, inaccessible, unsupported, oversized, missing-sidecar, timeout, and graphics-failure fallbacks. |
| Lifecycle | Rapid file changes, cancellation during load, twenty open/dismiss cycles, and no stale callbacks. |
| Security | Offline runtime, exact-file scheme routes, traversal rejection, no private WebKit keys, no leaked paths or PHI. |
| Performance | ≤2 seconds from `preparePreviewOfFile` to `loaded` for the representative small fixture; extension launch cost reported separately; measured limits for larger content. |

## Explicitly deferred follow-up

After v1 ships, evaluate these as separate changesets:

1. Finder Thumbnail Extension using static, resource-bounded snapshots.
2. FreeSurfer mesh UTIs and collision testing.
3. An upstream NiiVue reader plus licensed fixture for AFNI `.niml.tract`.
4. OBJ/STL/PLY registration only if NiiVue adds value beyond existing viewers.
5. iOS/iPadOS Files previews.
6. Host-app **Open With** document roles.
