/**
 * Headless regression checks for the `window.niivueBridge` contract.
 *
 *   node tests/bridge-regression.mjs        # after `npm run build`
 *
 * These three checks each caught a real, shipped bug, and CLAUDE.md describes
 * them as the loop to re-run after touching the bridge. They drive the built
 * `dist/` — the same bytes the app bundles — over a throwaway http server, so
 * they exercise the production build rather than a dev-server variant.
 *
 * What they cannot cover: everything native. The document picker, the save
 * panel, the readiness handshake, security-scoped files and content-process
 * recovery all need a simulator, a device, or a Mac.
 *
 * Playwright is deliberately NOT a dependency in package.json — the Xcode build
 * phase runs `npm ci` on a fresh clone and should not be made to pull a browser
 * automation stack to compile the app. Install it either way:
 *
 *   npm i -D playwright && npx playwright install chromium   # local to this dir
 *   npm i -g playwright && npx playwright install chromium   # or globally
 */
import { createServer } from 'node:http'
import { readFile } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import { gunzipSync } from 'node:zlib'
import { join, extname, normalize, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const HERE = dirname(fileURLToPath(import.meta.url))
const DIST = join(HERE, '..', 'dist')
const SAMPLES = join(HERE, '..', '..', 'NiiVue', 'samples')

/** Prefer a local playwright; fall back to a global install. */
async function loadPlaywright() {
  try {
    return await import('playwright')
  } catch {
    const root = execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim()
    return await import(`file://${join(root, 'playwright', 'index.mjs')}`)
  }
}

const MIME = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
}

const server = createServer(async (req, res) => {
  const path = normalize(decodeURIComponent(req.url.split('?')[0]))
  try {
    let body
    if (path.startsWith('/samples/')) {
      body = await readFile(join(SAMPLES, path.slice('/samples/'.length)))
    } else if (path === '/garbage.nii.gz') {
      // Not a volume in any format NiiVue reads.
      body = Buffer.from('this is definitely not a nifti volume'.repeat(64))
    } else {
      body = await readFile(join(DIST, path === '/' ? 'index.html' : path))
    }
    res.writeHead(200, {
      'Content-Type': MIME[extname(path)] ?? 'application/octet-stream',
    })
    res.end(body)
  } catch {
    res.writeHead(404).end('not found')
  }
})
await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve))
const base = `http://127.0.0.1:${server.address().port}`

const results = []
function check(name, ok, detail) {
  results.push(ok)
  console.log(`${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`)
}

const { chromium } = await loadPlaywright()
const browser = await chromium.launch({
  // Headless Chromium has no real GPU; NiiVue needs WebGL2 either way.
  args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'],
})
const page = await browser.newPage({ viewport: { width: 900, height: 700 } })
page.on('pageerror', (e) => console.log('  [page exception]', e.message))

await page.goto(`${base}/index.html`)
await page.waitForFunction(() => !!window.niivueBridge, null, { timeout: 30000 })

// --- 1. Smoke: the bridge surface, a load, a pen stroke, an export -----------
const keys = await page.evaluate(() => Object.keys(window.niivueBridge))
check('bridge exposes 12 functions', keys.length === 12, `${keys.length}`)

const loaded = await page.evaluate(
  (url) => window.niivueBridge.loadImageURL(url, 'T1w_DEMO.nii.gz'),
  `${base}/samples/T1w_DEMO.nii.gz`,
)
check('loadImageURL(sample) resolves true', loaded === true, String(loaded))

await page.evaluate(() => {
  const b = window.niivueBridge
  b.setSliceType(0)
  b.setLayout(2)
  b.setCrosshairVisible(true)
  b.setOrientationText(true)
  b.setOrientationCube(false)
  b.setRadiological(false)
  b.setDragMode(8)
  b.setCrosshairColor()
  b.moveCrosshairInVox(1, 0, 0)
  b.setPenValue(1, true, true)
})
check('the 10 synchronous setters ran without throwing', true)

const box = await page.locator('canvas').boundingBox()
await page.mouse.move(box.x + box.width * 0.45, box.y + box.height * 0.45)
await page.mouse.down()
for (let i = 0; i < 12; i++) {
  await page.mouse.move(
    box.x + box.width * (0.45 + i * 0.004),
    box.y + box.height * (0.45 + i * 0.004),
  )
}
await page.mouse.up()
await page.waitForTimeout(500)

const b64 = await page.evaluate(() => window.niivueBridge.saveDrawing())
check('saveDrawing returned a payload', b64.length > 0, `${b64.length} b64 chars`)

const nii = gunzipSync(Buffer.from(b64, 'base64'))
const dims = [nii.readInt16LE(42), nii.readInt16LE(44), nii.readInt16LE(46)]
check('gunzips to a NIfTI-1 header', nii.readInt32LE(0) === 348, `sizeof_hdr=${nii.readInt32LE(0)}`)
check('drawing dims match the volume', dims.join('x') === '188x256x190', dims.join('x'))
check('drawing datatype is DT_UINT8', nii.readInt16LE(70) === 2, String(nii.readInt16LE(70)))

let painted = 0
for (let i = Math.round(nii.readFloatLE(108)); i < nii.length; i++) {
  if (nii[i] !== 0) painted++
}
check('painted voxel count is non-zero', painted > 0, `${painted} voxels`)

// --- 2. A rejected volume must not cost the user their drawing ---------------
// `bridge.ts` loads BEFORE it closes the drawing precisely so this holds.
const bad = await page.evaluate(
  (url) =>
    window.niivueBridge.loadImageURL(url, 'garbage.nii.gz').then(
      (v) => ({ ok: v }),
      (e) => ({ err: String((e && e.message) || e) }),
    ),
  `${base}/garbage.nii.gz`,
)
check('corrupt file is rejected', bad.ok !== true, JSON.stringify(bad))
const after = await page.evaluate(() => window.niivueBridge.saveDrawing())
check('drawing survives the failed load', after.length === b64.length,
  `${b64.length} → ${after.length} b64 chars`)

// --- 3. Left drag moves the crosshair (NiiVue 1.0's default gesture) ---------
await page.evaluate(() => {
  window.__loc = []
  // Impersonate the native host so postToHost() has somewhere to deliver.
  window.webkit = {
    messageHandlers: { locationChange: { postMessage: (m) => window.__loc.push(m) } },
  }
  window.niivueBridge.setPenValue(1, true, false)
  window.niivueBridge.setDragMode(8)
})
await page.mouse.move(box.x + box.width * 0.25, box.y + box.height * 0.3)
await page.mouse.down()
for (let i = 0; i < 15; i++) {
  await page.mouse.move(box.x + box.width * (0.25 + i * 0.012), box.y + box.height * 0.3)
}
await page.mouse.up()
await page.waitForTimeout(300)

const loc = await page.evaluate(() => window.__loc.map((s) => JSON.parse(s)))
check('left drag emits locationChange', loc.length > 1, `${loc.length} events`)
if (loc.length > 1) {
  const last = loc[loc.length - 1]
  const mm = Math.hypot(...loc[0].slice(0, 3).map((v, i) => v - last[i]))
  check('crosshair moved several mm', mm > 3, `${mm.toFixed(1)} mm`)
}

await browser.close()
server.close()

const failed = results.filter((ok) => !ok).length
console.log(`\n${results.length - failed}/${results.length} checks passed`)
process.exit(failed ? 1 : 0)
