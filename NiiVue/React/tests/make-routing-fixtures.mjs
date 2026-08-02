/**
 * Write the Quick Look verification fixture set.
 *
 *   node tests/make-routing-fixtures.mjs <dir>
 *
 * Called by scripts/check-quicklook-routing.sh. Every positive fixture holds
 * REAL, loadable content, because the Milestone 8 exit gate is that advertised
 * types "route AND meet their rendered or documented fallback contract" — a
 * directory of zero-byte files proves the routing half and makes the manual
 * spacebar sweep worthless, since everything would show a fallback panel.
 *
 * Prints one `name<TAB>should-route<TAB>should-render` line per fixture on
 * stdout, which is the expectation table the shell script checks against.
 */
import { writeFileSync, copyFileSync, existsSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { gzipSync } from 'node:zlib'
import { nifti1, gifti, octahedron, nrrd, mha, mgh, mz3, tck, arcs } from './preview-fixtures.mjs'

const dir = process.argv[2]
if (!dir) {
  console.error('usage: node tests/make-routing-fixtures.mjs <dir>')
  process.exit(1)
}

// Split into good/ and bad/ so a spacebar sweep needs no lookup table: in good/
// every file draws an image, in bad/ none does. The distinction *within* bad/
// still matters — a foreign archive must keep Finder's own preview, not be
// overpainted by ours — so each folder carries a README stating its rule.
mkdirSync(join(dir, 'good'), { recursive: true })
mkdirSync(join(dir, 'bad'), { recursive: true })

/** Real tract fixtures whose containers are impractical to synthesise. */
const LFS = '/Users/chris/src/mono/packages/dev-images/images/meshes'
const BORROWED = [
  ['tracts.trk', 'tract.IFOF_R.trk'],
  ['tracts.trx', 'colby.trx'],
]

const rows = []
/** @param expect 'yes'|'no' routing · @param render 'yes'|'no'|'skip' */
function put(name, body, expect, render) {
  const folder = render === 'no' ? 'bad' : 'good'
  writeFileSync(join(dir, folder, name), body)
  rows.push([`${folder}/${name}`, expect, render])
}

const volume = nifti1({ dims: [24, 28, 20], pixDims: [2, 2, 2.5] })
const surface = octahedron()

// --- NIfTI, and the filename edge cases the plan calls for ------------------
put('plain.nii', volume, 'yes', 'yes')
put('UPPER.NII', volume, 'yes', 'yes')
put('MiXeD.NiI', volume, 'yes', 'yes')
put('with spaces.nii', volume, 'yes', 'yes')
put('sujet-café-ø-日本.nii', volume, 'yes', 'yes')
put(`${'l'.repeat(180)}.nii`, volume, 'yes', 'yes')
// The shell script chmods this one to 444 after generation.
put('readonly.nii', volume, 'yes', 'yes')
put('compound.nii.gz', gzipSync(volume), 'yes', 'yes')
put('double.NII.GZ', gzipSync(volume), 'yes', 'yes')
// 4D: renders frame zero and must report "1 of 8".
put('series4d.nii', nifti1({ dims: [16, 16, 12, 8] }), 'yes', 'yes')

// --- The other claimed voxel containers ------------------------------------
put('volume.mgh', mgh(), 'yes', 'yes')
put('volume.mgz', gzipSync(mgh()), 'yes', 'yes')
put('volume.nrrd', nrrd(), 'yes', 'yes')
put('volume.mha', mha(), 'yes', 'yes')

// --- Geometry and tracts ----------------------------------------------------
put('surface.gii', gifti(surface), 'yes', 'yes')
put('surface.mz3', mz3(surface), 'yes', 'yes')
put('tracts.tck', tck({ streamlines: arcs() }), 'yes', 'yes')
for (const [name, source] of BORROWED) {
  const from = join(LFS, source)
  if (existsSync(from)) {
    copyFileSync(from, join(dir, 'good', name))
    rows.push([`good/${name}`, 'yes', 'yes'])
  } else {
    rows.push([`good/${name}`, 'yes', 'skip'])
  }
}

// --- Files that must reach us and then be declined or explained ------------
// A real gzipped tarball: the extension claims generic gzip, so this is the
// case that must be handed back rather than overpainted.
const tar = Buffer.alloc(2048)
tar.write('fixture.txt', 0, 'ascii')
tar.write('0000644\0', 100, 'ascii')
tar.write('ustar\0', 257, 'ascii')
put('archive.tar.gz', gzipSync(tar), 'yes', 'no')
put('truncated.nii', nifti1({ dims: [24, 28, 20], truncateTo: 352 + 2000 }), 'yes', 'no')
put('layeronly.gii', gifti({ scalars: [0, 1, 2, 3, 4, 5] }), 'yes', 'no')
put('corrupt.nii', Buffer.from('not a volume in any format niivue reads '.repeat(64)), 'yes', 'no')

// --- Types we must NOT intercept -------------------------------------------
const detached = [
  'detached.hdr', 'detached.img', 'detached.mhd', 'detached.nhdr',
  'afni.HEAD', 'afni.BRIK',
]
const deferred = [
  'surf.white', 'surf.pial', 'surf.inflated', 'surf.sphere',
  'model.obj', 'model.stl', 'model.ply', 'notours.zip', 'notes.txt',
]
for (const name of [...detached, ...deferred]) put(name, Buffer.alloc(0), 'no', 'no')

writeFileSync(
  join(dir, 'good', 'README.txt'),
  `Every file here must DRAW AN IMAGE when you press Space.

  volumes   four tiles: axial, coronal, sagittal, 3D render
  geometry  one fitted 3D view you can drag to rotate

Also check while you are here:
  - series4d.nii reports "frames 1 of 8" in the strip
  - dragging rotates WITHOUT moving the Quick Look window, and without
    the panel turning blue
  - the filename edge cases behave like plain.nii: UPPER.NII, MiXeD.NiI,
    "with spaces.nii", the Unicode name, the 180-character name, and
    readonly.nii (mode 444)

Anything blank, or showing "Preview unavailable", is a bug.
`,
)
writeFileSync(
  join(dir, 'bad', 'README.txt'),
  `NOTHING here may draw an image. There are two kinds, and the difference matters.

1. Ours to explain — these reach the extension, which must show ITS OWN panel
   with a short reason and the file's metadata. Blank is a bug; so is a picture.

     truncated.nii   header promises more voxels than the file holds
     corrupt.nii     not a volume in any format
     layeronly.gii   per-vertex values with no surface to put them on

2. NOT ours — the extension must not preview these at all; whatever macOS would
   normally show is the correct result.

     archive.tar.gz  THE IMPORTANT ONE. We claim generic gzip so that .nii.gz
                     can reach us, so a tarball reaches us too and must be
                     handed straight back. If you see our panel here, the
                     content sniff has regressed.
     detached.*      .hdr/.img/.mhd/.nhdr — deliberately not claimed
     afni.*          .HEAD/.BRIK — deliberately not claimed
     surf.*          FreeSurfer surfaces — deferred
     model.*         .obj/.stl/.ply — better served by existing viewers
     notours.zip, notes.txt
`,
)

for (const row of rows) console.log(row.join('\t'))
