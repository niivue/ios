import { logToIOS } from './iosMessaging'

type DicomInputItem = { name: string; data: ArrayBuffer | Uint8Array }
type DicomInput = DicomInputItem[]

type Dcm2niixModule = {
  FS: {
    mkdir: (path: string) => void
    rmdir: (path: string) => void
    readdir: (path: string) => string[]
    unlink: (path: string) => void
    createDataFile: (parent: string, name: string, data: Uint8Array, canRead: boolean, canWrite: boolean) => void
    readFile: (path: string) => Uint8Array
  }
  callMain: (args: string[]) => number
}

let cachedModulePromise: Promise<Dcm2niixModule> | null = null

async function fetchWithOk(url: string | URL): Promise<Response> {
  const response = await fetch(url)
  if (!response.ok) {
    throw new Error(`Fetch failed (${response.status}): ${response.statusText}`)
  }
  return response
}

async function loadDcm2niixModule(): Promise<Dcm2niixModule> {
  if (!cachedModulePromise) {
    cachedModulePromise = (async () => {
      const { default: Module } = (await import('@niivue/dcm2niix-module')) as { default: () => Promise<Dcm2niixModule> }
      return await Module()
    })()
  }
  return await cachedModulePromise
}

function safeUnlink(mod: Dcm2niixModule, path: string): void {
  try {
    mod.FS.unlink(path)
  } catch {
    // Ignore.
  }
}

function safeRmdir(mod: Dcm2niixModule, path: string): void {
  try {
    mod.FS.rmdir(path)
  } catch {
    // Ignore.
  }
}

export async function dicomLoader(data: DicomInput): Promise<Array<{ name: string; data: ArrayBuffer }>> {
  const start = Date.now()
  const fileCount = Array.isArray(data) ? data.length : 0
  logToIOS('info', `[DICOM] dcm2niix(main-thread) start: ${fileCount} file(s)`)

  const mod = await loadDcm2niixModule()
  const runId = `${Date.now()}_${Math.floor(Math.random() * 1e9)}`
  const inDir = `/input_${runId}`
  const outDir = `/output_${runId}`

  // dcm2niix expects at least one CLI flag.
  //
  // IMPORTANT (iOS memory): large series can exceed WebKit/WASM memory limits if we emit a huge uncompressed `.nii`.
  // Prefer gzipped output for large series to reduce peak memory usage and avoid conversion stalls.
  const gzipOutput = fileCount >= 350 ? 'y' : 'n'
  const args: string[] = ['-z', gzipOutput]

  const inputFileNames: string[] = []
  try {
    mod.FS.mkdir(inDir)
    mod.FS.mkdir(outDir)

    for (const entry of data) {
      const fileName = `${entry.name}`.split('/').join('_')
      inputFileNames.push(fileName)
      const bytes = entry.data instanceof ArrayBuffer ? new Uint8Array(entry.data) : entry.data
      mod.FS.createDataFile(inDir, fileName, bytes, true, true)
      // Help GC by dropping references to large input buffers as soon as they are copied into MEMFS.
      entry.data = new Uint8Array(0)
    }

    const fullArgs = ['-o', outDir, ...args, inDir]
    logToIOS('info', `[DICOM] dcm2niix(main-thread) callMain args=${JSON.stringify(fullArgs)}`)

    const exitCode = mod.callMain(fullArgs)
    if (exitCode !== 0 && exitCode !== 3) {
      throw new Error(`dcm2niix processing failed with exit code ${exitCode}`)
    }

    const outFiles = mod.FS.readdir(outDir).filter((name) => name !== '.' && name !== '..' && !name.startsWith('.'))
    const niiFiles = outFiles.filter((name) => name.endsWith('.nii') || name.endsWith('.nii.gz'))
    if (niiFiles.length < 1) {
      throw new Error(`dcm2niix succeeded but produced no .nii/.nii.gz files (outFiles=${outFiles.join(', ')})`)
    }

    const arrayBuffers: Array<{ name: string; data: ArrayBuffer }> = []
    for (const fileName of niiFiles) {
      const filePath = `${outDir}/${fileName}`
      const fileData = mod.FS.readFile(filePath)
      const buffer =
        fileData.byteOffset === 0 && fileData.byteLength === fileData.buffer.byteLength
          ? fileData.buffer
          : fileData.buffer.slice(fileData.byteOffset, fileData.byteOffset + fileData.byteLength)
      arrayBuffers.push({ name: fileName, data: buffer })
    }

    const elapsedMs = Date.now() - start
    logToIOS('info', `[DICOM] dcm2niix(main-thread) produced ${arrayBuffers.length} NIfTI file(s) in ${elapsedMs}ms`)
    return arrayBuffers
  } finally {
    // Best-effort cleanup to keep the Emscripten MEMFS from growing unbounded across runs.
    for (const fileName of inputFileNames) {
      safeUnlink(mod, `${inDir}/${fileName}`)
    }
    safeRmdir(mod, inDir)

    try {
      const remaining = mod.FS.readdir(outDir).filter((name) => name !== '.' && name !== '..')
      for (const fileName of remaining) {
        safeUnlink(mod, `${outDir}/${fileName}`)
      }
    } catch {
      // Ignore.
    }
    safeRmdir(mod, outDir)
  }
}

export async function dicomLoaderFromBundleUrl(bundleUrl: string): Promise<Array<{ name: string; data: ArrayBuffer }>> {
  const start = Date.now()
  logToIOS('info', `[DICOM] dcm2niix(bundle) start: ${bundleUrl}`)

  const mod = await loadDcm2niixModule()
  const runId = `${Date.now()}_${Math.floor(Math.random() * 1e9)}`
  const inDir = `/input_${runId}`
  const outDir = `/output_${runId}`

  const inputFileNames: string[] = []
  let parsedFileCount = 0

  function safeReadU32LE(bytes: Uint8Array): number {
    if (bytes.byteLength !== 4) {
      throw new Error(`Invalid DICOM bundle: expected 4 bytes, got ${bytes.byteLength}`)
    }
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)
  }

  // Stream parser: minimal-copy queue reader for `bundle.bin`.
  const response = await fetchWithOk(bundleUrl)
  const reader = response.body?.getReader()
  if (!reader) {
    throw new Error('DICOM bundle response is not stream-readable (response.body missing).')
  }

  const chunks: Uint8Array[] = []
  let headOffset = 0
  let available = 0

  async function ensureAvailable(bytesNeeded: number): Promise<void> {
    while (available < bytesNeeded) {
      const { value, done } = await reader.read()
      if (done) {
        throw new Error(`Invalid DICOM bundle: truncated stream (needed ${bytesNeeded}, available ${available}).`)
      }
      if (value && value.byteLength > 0) {
        chunks.push(value)
        available += value.byteLength
      }
    }
  }

  async function readInto(target: Uint8Array, targetOffset: number, length: number): Promise<void> {
    await ensureAvailable(length)
    let remaining = length
    let offset = targetOffset
    while (remaining > 0) {
      const head = chunks[0]
      const headRemaining = head.byteLength - headOffset
      const take = Math.min(headRemaining, remaining)
      target.set(head.subarray(headOffset, headOffset + take), offset)
      headOffset += take
      offset += take
      remaining -= take
      available -= take
      if (headOffset >= head.byteLength) {
        chunks.shift()
        headOffset = 0
      }
    }
  }

  async function readExactly(length: number): Promise<Uint8Array> {
    const out = new Uint8Array(length)
    await readInto(out, 0, length)
    return out
  }

  const decoder = new TextDecoder('utf-8')

  try {
    mod.FS.mkdir(inDir)
    mod.FS.mkdir(outDir)

    const countBytes = await readExactly(4)
    const count = safeReadU32LE(countBytes) >>> 0
    parsedFileCount = count
    logToIOS('info', `[DICOM] Bundle stream header: ${count} file(s)`)

    for (let i = 0; i < count; i += 1) {
      const nameLen = safeReadU32LE(await readExactly(4)) >>> 0
      if (nameLen < 1 || nameLen > 1024 * 8) {
        throw new Error(`Invalid DICOM bundle: suspicious filename length ${nameLen}`)
      }
      const nameBytes = await readExactly(nameLen)
      const name = decoder.decode(nameBytes)

      const dataLen = safeReadU32LE(await readExactly(4)) >>> 0
      if (dataLen < 1) {
        throw new Error(`Invalid DICOM bundle: invalid data length ${dataLen} for ${name}`)
      }

      const fileName = `${name}`.split('/').join('_')
      inputFileNames.push(fileName)

      const fileData = new Uint8Array(dataLen)
      await readInto(fileData, 0, dataLen)
      mod.FS.createDataFile(inDir, fileName, fileData, true, true)

      if (i > 0 && (i % 50 === 0 || i === count - 1)) {
        logToIOS('info', `[DICOM] Bundle stream progress: ${i + 1}/${count}`)
      }
    }

    // Prefer gzipped output for large series to reduce peak memory usage.
    const gzipOutput = parsedFileCount >= 350 ? 'y' : 'n'
    const args: string[] = ['-z', gzipOutput]
    const fullArgs = ['-o', outDir, ...args, inDir]
    logToIOS('info', `[DICOM] dcm2niix(bundle) callMain args=${JSON.stringify(fullArgs)}`)

    const exitCode = mod.callMain(fullArgs)
    if (exitCode !== 0 && exitCode !== 3) {
      throw new Error(`dcm2niix processing failed with exit code ${exitCode}`)
    }

    const outFiles = mod.FS.readdir(outDir).filter((name) => name !== '.' && name !== '..' && !name.startsWith('.'))
    const niiFiles = outFiles.filter((name) => name.endsWith('.nii') || name.endsWith('.nii.gz'))
    if (niiFiles.length < 1) {
      throw new Error(`dcm2niix succeeded but produced no .nii/.nii.gz files (outFiles=${outFiles.join(', ')})`)
    }

    const arrayBuffers: Array<{ name: string; data: ArrayBuffer }> = []
    for (const fileName of niiFiles) {
      const filePath = `${outDir}/${fileName}`
      const fileData = mod.FS.readFile(filePath)
      const buffer =
        fileData.byteOffset === 0 && fileData.byteLength === fileData.buffer.byteLength
          ? fileData.buffer
          : fileData.buffer.slice(fileData.byteOffset, fileData.byteOffset + fileData.byteLength)
      arrayBuffers.push({ name: fileName, data: buffer })
    }

    const elapsedMs = Date.now() - start
    logToIOS('info', `[DICOM] dcm2niix(bundle) produced ${arrayBuffers.length} NIfTI file(s) in ${elapsedMs}ms`)
    return arrayBuffers
  } finally {
    try {
      // If the stream is still open, cancel to free networking resources.
      await reader.cancel()
    } catch {
      // Ignore.
    }

    for (const fileName of inputFileNames) {
      safeUnlink(mod, `${inDir}/${fileName}`)
    }
    safeRmdir(mod, inDir)

    try {
      const remaining = mod.FS.readdir(outDir).filter((name) => name !== '.' && name !== '..')
      for (const fileName of remaining) {
        safeUnlink(mod, `${outDir}/${fileName}`)
      }
    } catch {
      // Ignore.
    }
    safeRmdir(mod, outDir)
  }
}
