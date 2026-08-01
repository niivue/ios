/**
 * Deterministic NIfTI-1 fixture generation for the preview regression checks.
 *
 * Milestone 0 of the Quick Look plan allows "a documented deterministic
 * fixture-generation step" in place of a redistributable file, which is what
 * this is. The cases that matter — 4D, complex, zero-dimension, truncated —
 * have no licensed fixture anywhere in the monorepo, and synthesising them is
 * both smaller and more precise than hunting for real scans that happen to have
 * the property under test.
 *
 * Layout follows the NIfTI-1 spec: a 348-byte header, `magic` "n+1\0" at 344,
 * and voxel data at `vox_offset` 352.
 */

const HEADER_BYTES = 348
const VOX_OFFSET = 352

/** Bytes per voxel for the datatype codes these fixtures use. */
const BYTES_PER_VOXEL = { 2: 1, 4: 2, 16: 4, 32: 8, 64: 8 }

/**
 * @param {object} spec
 * @param {number[]} spec.dims  [x, y, z] or [x, y, z, t]
 * @param {number[]} [spec.pixDims]  voxel size in mm, defaults to 1×1×1
 * @param {number} [spec.datatype]  NIfTI datatype code, defaults to uint8
 * @param {(i: number, voxel: number) => number} [spec.fill]  value per element
 * @param {number} [spec.truncateTo]  total byte length to cut the file down to
 */
export function nifti1(spec) {
  const [nx, ny, nz, nt = 1] = spec.dims
  const pix = spec.pixDims ?? [1, 1, 1]
  const datatype = spec.datatype ?? 2
  const perVoxel = BYTES_PER_VOXEL[datatype]
  if (!perVoxel) throw new Error(`no fixture support for datatype ${datatype}`)

  const voxels = Math.max(0, nx * ny * nz * nt)
  // Complex packs two float32 per voxel; everything else is one element.
  const elements = datatype === 32 ? voxels * 2 : voxels
  const buffer = Buffer.alloc(VOX_OFFSET + voxels * perVoxel)
  const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength)

  view.setInt32(0, HEADER_BYTES, true) // sizeof_hdr
  view.setInt16(40, nt > 1 ? 4 : 3, true) // dim[0]
  view.setInt16(42, nx, true)
  view.setInt16(44, ny, true)
  view.setInt16(46, nz, true)
  view.setInt16(48, nt, true)
  for (let i = 5; i <= 7; i++) view.setInt16(40 + i * 2, 1, true)
  view.setInt16(70, datatype, true)
  view.setInt16(72, perVoxel * 8, true) // bitpix
  view.setFloat32(76, 1, true) // pixdim[0] qfac
  view.setFloat32(80, pix[0], true)
  view.setFloat32(84, pix[1], true)
  view.setFloat32(88, pix[2], true)
  view.setFloat32(92, 1, true) // pixdim[4], TR
  view.setFloat32(108, VOX_OFFSET, true) // vox_offset
  view.setFloat32(112, 1, true) // scl_slope
  view.setUint8(123, 2 | 8) // xyzt_units: mm + sec
  view.setInt16(254, 1, true) // sform_code = scanner anat

  // An axis-aligned RAS affine centred on the volume, so `orient` reads "RAS".
  const srow = [
    [pix[0], 0, 0, (-pix[0] * nx) / 2],
    [0, pix[1], 0, (-pix[1] * ny) / 2],
    [0, 0, pix[2], (-pix[2] * nz) / 2],
  ]
  srow.forEach((row, r) => row.forEach((v, c) => view.setFloat32(280 + r * 16 + c * 4, v, true)))
  buffer.write('n+1\0', 344, 'ascii')

  // A soft-edged blob, so slices have structure rather than a flat field.
  const fill =
    spec.fill ??
    ((i) => {
      const v = i % (nx * ny * nz)
      const x = v % nx
      const y = Math.floor(v / nx) % ny
      const z = Math.floor(v / (nx * ny)) % nz
      const r = Math.hypot(x - nx / 2, y - ny / 2, z - nz / 2) / (Math.min(nx, ny, nz) / 2)
      return r > 1 ? 0 : Math.round(255 * (1 - r * r))
    })

  for (let i = 0; i < elements; i++) {
    const at = VOX_OFFSET + i * (datatype === 32 ? 4 : perVoxel)
    const value = fill(i)
    if (datatype === 2) view.setUint8(at, value & 0xff)
    else if (datatype === 4) view.setInt16(at, value, true)
    else if (datatype === 16 || datatype === 32) view.setFloat32(at, value, true)
    else if (datatype === 64) view.setFloat64(at, value, true)
  }

  return spec.truncateTo === undefined ? buffer : buffer.subarray(0, spec.truncateTo)
}

/**
 * A GIFTI surface, or — with no geometry — the layer-only file the product
 * contract singles out: one that supplies scalars and expects a viewer to go
 * looking for a companion surface, which this preview must refuse to do.
 *
 * ASCII encoding keeps the fixture readable and sidesteps base64 endianness.
 * NiiVue's reader defaults an absent `Dim2` to 1, so the conventional
 * `Dimensionality="2"` form is what it expects.
 */
function dataArray(intent, dataType, dims, values) {
  const dimAttrs = dims.map((d, i) => `Dim${i}="${d}"`).join(' ')
  return `  <DataArray Intent="${intent}" DataType="${dataType}"
    ArrayIndexingOrder="RowMajorOrder" Dimensionality="${dims.length}" ${dimAttrs}
    Encoding="ASCII" Endian="LittleEndian" ExternalFileName="" ExternalFileOffset="">
    <Data>${values.join(' ')}</Data>
  </DataArray>`
}

export function gifti(spec) {
  const arrays = []
  if (spec.vertices) {
    arrays.push(
      dataArray('NIFTI_INTENT_POINTSET', 'NIFTI_TYPE_FLOAT32', [spec.vertices.length / 3, 3], spec.vertices),
    )
  }
  if (spec.triangles) {
    arrays.push(
      dataArray('NIFTI_INTENT_TRIANGLE', 'NIFTI_TYPE_INT32', [spec.triangles.length / 3, 3], spec.triangles),
    )
  }
  if (spec.scalars) {
    arrays.push(dataArray('NIFTI_INTENT_SHAPE', 'NIFTI_TYPE_FLOAT32', [spec.scalars.length], spec.scalars))
  }
  return Buffer.from(
    `<?xml version="1.0" encoding="UTF-8"?>
<GIFTI Version="1.0" NumberOfDataArrays="${arrays.length}">
${arrays.join('\n')}
</GIFTI>
`,
    'utf8',
  )
}

/** A soft ellipsoid blob, so slices have structure rather than a flat field. */
function blob(nx, ny, nz) {
  const voxels = new Uint8Array(nx * ny * nz)
  let i = 0
  for (let z = 0; z < nz; z++) {
    for (let y = 0; y < ny; y++) {
      for (let x = 0; x < nx; x++) {
        const r = Math.hypot((x - nx / 2) / nx, (y - ny / 2) / ny, (z - nz / 2) / nz) * 2
        voxels[i++] = r > 1 ? 0 : Math.round(255 * (1 - r * r))
      }
    }
  }
  return voxels
}

/**
 * Self-contained NRRD. `encoding: raw` with the data attached after the blank
 * line that terminates the header — the detached `.nhdr` form is out of scope.
 */
export function nrrd({ dims = [24, 28, 20], spacing = [2, 2, 2.5] } = {}) {
  const [nx, ny, nz] = dims
  const header = [
    'NRRD0004',
    '# Synthetic fixture for Quick Look verification.',
    'type: uint8',
    'dimension: 3',
    `sizes: ${nx} ${ny} ${nz}`,
    'space: right-anterior-superior',
    `space directions: (${spacing[0]},0,0) (0,${spacing[1]},0) (0,0,${spacing[2]})`,
    `space origin: (${(-spacing[0] * nx) / 2},${(-spacing[1] * ny) / 2},${(-spacing[2] * nz) / 2})`,
    'encoding: raw',
    'endian: little',
    '',
    '',
  ].join('\n')
  return Buffer.concat([Buffer.from(header, 'ascii'), Buffer.from(blob(nx, ny, nz))])
}

/**
 * Self-contained MetaImage. `ElementDataFile = LOCAL` is what makes it `.mha`
 * rather than the detached `.mhd` this extension deliberately does not claim.
 */
export function mha({ dims = [24, 28, 20], spacing = [2, 2, 2.5] } = {}) {
  const [nx, ny, nz] = dims
  const header = [
    'ObjectType = Image',
    'NDims = 3',
    'BinaryData = True',
    'BinaryDataByteOrderMSB = False',
    'CompressedData = False',
    'TransformMatrix = 1 0 0 0 1 0 0 0 1',
    `Offset = ${(-spacing[0] * nx) / 2} ${(-spacing[1] * ny) / 2} ${(-spacing[2] * nz) / 2}`,
    `ElementSpacing = ${spacing.join(' ')}`,
    `DimSize = ${dims.join(' ')}`,
    'ElementType = MET_UCHAR',
    'ElementDataFile = LOCAL',
    '',
  ].join('\n')
  return Buffer.concat([Buffer.from(header, 'ascii'), Buffer.from(blob(nx, ny, nz))])
}

/**
 * FreeSurfer MGH. Big-endian throughout, a fixed 284-byte header, and voxel
 * data straight after it. Field offsets follow NiiVue's reader
 * (`volume/readers/mgh.ts`): dims at 4/8/12/16, type at 20, the RAS-good flag
 * at 28, spacing at 30, direction cosines at 42, and the centre at 78.
 * Gzipping the result is exactly what makes it an `.mgz`.
 */
export function mgh({ dims = [24, 28, 20], spacing = [2, 2, 2.5] } = {}) {
  const [nx, ny, nz] = dims
  const header = Buffer.alloc(284)
  const view = new DataView(header.buffer, header.byteOffset, header.byteLength)
  view.setInt32(0, 1) // version
  view.setInt32(4, nx)
  view.setInt32(8, ny)
  view.setInt32(12, nz)
  view.setInt32(16, 1) // nframes
  view.setInt32(20, 0) // MRI_UCHAR
  view.setInt32(24, 0) // dof
  view.setInt16(28, 1) // ras_good_flag
  spacing.forEach((s, i) => view.setFloat32(30 + i * 4, s))
  // Direction cosines: an identity RAS basis.
  ;[1, 0, 0, 0, 1, 0, 0, 0, 1].forEach((v, i) => view.setFloat32(42 + i * 4, v))
  ;[0, 0, 0].forEach((v, i) => view.setFloat32(78 + i * 4, v)) // c_ras
  return Buffer.concat([header, Buffer.from(blob(nx, ny, nz))])
}

/**
 * MZ3 surface. Little-endian: magic 23117, then an attribute word whose low two
 * bits say "this file has faces and vertices", then the two counts, a skip
 * field, and the arrays. See `mesh/readers/mz3.ts`.
 */
export function mz3({ vertices, triangles }) {
  const header = Buffer.alloc(16)
  const view = new DataView(header.buffer)
  view.setUint16(0, 23117, true) // magic
  view.setUint16(2, 1 | 2, true) // isFACE | isVERT
  view.setUint32(4, triangles.length / 3, true)
  view.setUint32(8, vertices.length / 3, true)
  view.setUint32(12, 0, true) // nskip
  const faces = Buffer.alloc(triangles.length * 4)
  triangles.forEach((v, i) => faces.writeInt32LE(v, i * 4))
  const verts = Buffer.alloc(vertices.length * 4)
  vertices.forEach((v, i) => verts.writeFloatLE(v, i * 4))
  return Buffer.concat([header, faces, verts])
}

/**
 * MRtrix TCK. An ASCII header whose `file:` field carries the byte offset of
 * the data, then float triplets: NaN ends a streamline, Infinity ends the file.
 */
export function tck({ streamlines }) {
  // The offset has to appear inside the very header whose length it describes,
  // so pad it to a fixed width rather than chasing a fixed point.
  const body = (offset) =>
    `mrtrix tracks\ndatatype: Float32LE\nfile: . ${String(offset).padStart(6, ' ')}\nEND\n`
  const offset = Buffer.byteLength(body(0), 'ascii')
  const header = Buffer.from(body(offset), 'ascii')

  const floats = []
  for (const line of streamlines) {
    floats.push(...line)
    floats.push(NaN, NaN, NaN)
  }
  floats.push(Infinity, Infinity, Infinity)
  const data = Buffer.alloc(floats.length * 4)
  floats.forEach((v, i) => data.writeFloatLE(v, i * 4))
  return Buffer.concat([header, data])
}

/** A few arcs, so a tract fixture has direction to colour by. */
export function arcs(count = 12, points = 24, radius = 40) {
  return Array.from({ length: count }, (_, s) => {
    const line = []
    const tilt = (s / count) * Math.PI
    for (let p = 0; p < points; p++) {
      const t = (p / (points - 1)) * Math.PI
      line.push(
        radius * Math.cos(t) * Math.cos(tilt),
        radius * Math.cos(t) * Math.sin(tilt),
        radius * Math.sin(t) - radius / 2,
      )
    }
    return line
  })
}

/** A closed octahedron, big enough in mm to look like something on screen. */
export function octahedron(radius = 40) {
  const r = radius
  const vertices = [r, 0, 0, -r, 0, 0, 0, r, 0, 0, -r, 0, 0, 0, r, 0, 0, -r]
  const triangles = [
    0, 2, 4, 2, 1, 4, 1, 3, 4, 3, 0, 4,
    2, 0, 5, 1, 2, 5, 3, 1, 5, 0, 3, 5,
  ]
  return { vertices, triangles }
}
