//
//  GzipPeek.swift
//  Bounded gzip inspection for Quick Look routing.
//
//  Why this exists: macOS resolves a file's type from the LAST extension
//  component only, so `.nii.gz` can never have its own UTI — it is simply
//  `org.gnu.gnu-zip-archive`, exactly like `.tar.gz`. Declaring a compound
//  `nii.gz` tag registers fine and never matches; Apple's own tar-gzip type
//  declares only `tgz` for the same reason.
//
//  The extension therefore claims gzip and decides by CONTENT. That obliges it
//  to be a good citizen for every other `.gz` on the machine, so this reader is
//  deliberately hostile-input shaped: it inflates a fixed, tiny prefix and never
//  allocates on the strength of anything the file claims about itself.
//

import Foundation
import Compression

enum GzipPeek {

    /// Enough for a NIfTI-1 header (348 bytes) or a NIfTI-2 header (540).
    private static let peekBytes = 1024
    /// Compressed bytes read from disk. A gzip header plus the first block of a
    /// real volume is far smaller than this; anything needing more is not
    /// something we want to identify anyway.
    private static let compressedBudget = 64 * 1024

    /// Offset of the raw DEFLATE payload within a gzip member, or nil if this
    /// is not gzip. Shared so the prefix reader and the streaming size bound
    /// agree on exactly what a gzip header is.
    static func deflateOffset(in data: Data) -> Int? {
        var index = data.startIndex
        func take(_ n: Int) -> Data? {
            guard data.distance(from: index, to: data.endIndex) >= n else { return nil }
            let end = data.index(index, offsetBy: n)
            defer { index = end }
            return data[index..<end]
        }
        // Fixed 10-byte gzip header.
        guard let header = take(10), header.count == 10 else { return nil }
        let bytes = [UInt8](header)
        guard bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else { return nil }
        let flags = bytes[3]

        if flags & 0x04 != 0 { // FEXTRA
            guard let xlen = take(2) else { return nil }
            let n = Int([UInt8](xlen)[0]) | Int([UInt8](xlen)[1]) << 8
            guard take(n) != nil else { return nil }
        }
        for flag in [UInt8(0x08), UInt8(0x10)] where flags & flag != 0 { // FNAME, FCOMMENT
            while true {
                guard let byte = take(1) else { return nil }
                if byte.first == 0 { break }
            }
        }
        if flags & 0x02 != 0, take(2) == nil { return nil } // FHCRC
        return data.distance(from: data.startIndex, to: index)
    }

    /// Inflate at most `peekBytes` from the start of a gzip member.
    /// Returns nil if `data` is not gzip, or is truncated/corrupt.
    static func inflatePrefix(of data: Data) -> Data? {
        guard let offset = deflateOffset(in: data) else { return nil }
        let deflate = data[data.index(data.startIndex, offsetBy: offset)...]
        guard !deflate.isEmpty else { return nil }

        // COMPRESSION_ZLIB is raw DEFLATE in Apple's framework, which is what a
        // gzip member holds once its header is consumed.
        var out = Data(count: peekBytes)
        let produced: Int = out.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return deflate.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                // A truncated prefix legitimately ends mid-stream, so a short
                // result is success, not failure.
                return compression_decode_buffer(dstBase, peekBytes,
                                                 srcBase, deflate.count,
                                                 nil, COMPRESSION_ZLIB)
            }
        }
        guard produced > 0 else { return nil }
        return out.prefix(produced)
    }

    /// Read a bounded prefix of `url` and inflate it if it is gzip.
    static func inflatePrefix(ofFileAt url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let compressed = try? handle.read(upToCount: compressedBudget) else { return nil }
        return inflatePrefix(of: compressed)
    }

    /// True when the gzip member at `url` inflates to more than `limit` bytes.
    ///
    /// The format-agnostic half of the memory policy, and the only part that
    /// covers `.mgz`, `.nrrd.gz` and `.gii.gz` — a header budget needs a parser
    /// per format, but every one of these is a gzip member, and a bomb is a
    /// bomb whatever is inside it. Output is inflated into one reused buffer
    /// and discarded; only the running total is kept, so the peak cost here is
    /// `chunkBytes`, not the payload.
    ///
    /// Stops the moment the limit is passed, so a 1000:1 bomb costs `limit`
    /// bytes of work rather than the whole expansion. Compare the gzip ISIZE
    /// trailer, which is tempting and wrong: it is modulo 2³² and describes
    /// only the last member.
    ///
    /// Returns false for anything that is not gzip — uncompressed files are
    /// already bounded by the source-size cap, since decoded ≈ bytes on disk.
    static func inflatedSize(ofFileAt url: URL, exceeds limit: Int) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        // The header can carry an arbitrarily long FNAME/FCOMMENT, so find the
        // payload within the same bounded window the prefix reader uses.
        guard let head = try? handle.read(upToCount: compressedBudget),
              let offset = deflateOffset(in: head), offset < head.count else { return false }

        var stream = compression_stream(dst_ptr: UnsafeMutablePointer<UInt8>(bitPattern: 1)!,
                                        dst_size: 0,
                                        src_ptr: UnsafePointer<UInt8>(bitPattern: 1)!,
                                        src_size: 0, state: nil)
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE,
                                      COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else { return false }
        defer { compression_stream_destroy(&stream) }

        var produced = 0
        var output = [UInt8](repeating: 0, count: chunkBytes)
        var input = head.subdata(in: (head.startIndex + offset)..<head.endIndex)

        while true {
            var status = COMPRESSION_STATUS_OK
            var stalled = false
            let overflowed: Bool = input.withUnsafeBytes { src -> Bool in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return false }
                stream.src_ptr = srcBase
                stream.src_size = input.count
                repeat {
                    let wrote: Int = output.withUnsafeMutableBufferPointer { dst -> Int in
                        stream.dst_ptr = dst.baseAddress!
                        stream.dst_size = dst.count
                        status = compression_stream_process(&stream, 0)
                        return dst.count - stream.dst_size
                    }
                    produced += wrote
                    if produced > limit { return true }
                    if status != COMPRESSION_STATUS_OK { return false }
                    if wrote == 0 { stalled = true; return false }
                } while stream.src_size > 0
                return false
            }
            if overflowed { return true }
            if status != COMPRESSION_STATUS_OK || stalled { return false }
            guard let next = try? handle.read(upToCount: chunkBytes), !next.isEmpty else {
                return false // input exhausted without passing the limit
            }
            input = next
        }
    }

    /// Working buffer for the streaming inflate, in and out.
    private static let chunkBytes = 256 * 1024
}

enum VolumeSniff {
    /// True if `header` starts a NIfTI-1 or NIfTI-2 image.
    ///
    /// Checked against the header size field *and* the magic string, in both byte
    /// orders. The size field alone is not enough — 348 is a plausible leading
    /// int32 in arbitrary data — and the magic alone would miss byte-swapped
    /// files that NiiVue reads perfectly well.
    static func isNIfTI(_ header: Data) -> Bool {
        let bytes = [UInt8](header)
        func int32(at offset: Int) -> Int32? {
            guard bytes.count >= offset + 4 else { return nil }
            let value = bytes[offset..<offset + 4].reduce(Int32(0)) { ($0 << 8) | Int32($1) }
            return value
        }
        func magic(at offset: Int, _ expected: [String]) -> Bool {
            guard bytes.count >= offset + 3 else { return false }
            let text = String(bytes: bytes[offset..<offset + 3], encoding: .ascii) ?? ""
            return expected.contains(text)
        }
        guard let big = int32(at: 0) else { return false }
        let little = Int32(bigEndian: big.bigEndian).byteSwapped

        // NIfTI-1: sizeof_hdr 348, magic "n+1" (single file) or "ni1" (paired) at 344.
        if (big == 348 || little == 348) && magic(at: 344, ["n+1", "ni1"]) { return true }
        // NIfTI-2: sizeof_hdr 540, magic at offset 4.
        if (big == 540 || little == 540) && magic(at: 4, ["n+2", "ni2"]) { return true }
        return false
    }

    /// True when the gzip member at `url` inflates past `limit`. Thin passthrough
    /// so callers have one place to ask about size, whatever the format.
    static func inflatedSizeExceeds(_ url: URL, _ limit: Int) -> Bool {
        GzipPeek.inflatedSize(ofFileAt: url, exceeds: limit)
    }

    /// Total bytes this volume will occupy once decoded, or nil if the
    /// header is not a NIfTI we can measure.
    ///
    /// This exists because the file-size cap does **not** bound the decoded
    /// size: a few hundred kilobytes of gzip can claim any dimensions it likes,
    /// and the allocation that follows happens inside WebKit's content process
    /// where a refusal is a crash rather than an error. Measuring the header
    /// before the page ever fetches the file is the only point at which a
    /// hostile one can be turned away cheaply.
    ///
    /// **Frames are NOT clamped to one, and that is the whole point.** The page
    /// asks for `limitFrames4D: 1`, but NiiVue honours that lazily on exactly
    /// one path — `volume/NVVolume.ts` bails with `if (dv.getInt32(0, true)
    /// !== 348) return null`, so NIfTI-2, byte-swapped NIfTI-1, MGZ/NRRD/MHA
    /// and any uncompressed volume fetched by URL decompress and allocate
    /// **every** frame. Budgeting one frame for those was a 200× underestimate:
    /// a NIfTI-2 claiming 512³×200 uint8 measures 128 MB per frame and 25 GiB
    /// in total, gzips to ~25 MB, and passed both gates before this.
    ///
    /// There is deliberately no "one frame" variant of this. NiiVue's partial
    /// streaming loader is **unreachable from `loadVolumes`** — the worker
    /// fetches and decodes the whole buffer and applies the limit afterwards in
    /// `nii2volume`, and the main-thread fallback drops the limit entirely
    /// (`volume/loadBridge.ts`). Verified by measurement: a 2.65 MB
    /// 128×128×64×2600 `.nii.gz` drove the content process to 5.4 GiB while
    /// reporting "1 of 2600". So the bound is always the TOTAL.
    static func decodedSize(_ header: Data) -> Int? {
        let bytes = [UInt8](header)
        func value(at offset: Int, width: Int, swapped: Bool) -> Int64? {
            guard bytes.count >= offset + width else { return nil }
            let slice = Array(bytes[offset..<offset + width])
            let ordered = swapped ? slice.reversed().map { $0 } : slice
            return ordered.reduce(Int64(0)) { ($0 << 8) | Int64($1) }
        }

        // Layout differs between the two versions: NIfTI-1 keeps 16-bit dims at
        // 40 and the datatype at 70; NIfTI-2 widens dims to 64-bit at 16 and
        // moves the datatype to 12.
        let isNifti2: Bool
        var swapped: Bool
        if let big = value(at: 0, width: 4, swapped: false), big == 348 {
            isNifti2 = false; swapped = false
        } else if let little = value(at: 0, width: 4, swapped: true), little == 348 {
            isNifti2 = false; swapped = true
        } else if let big = value(at: 0, width: 4, swapped: false), big == 540 {
            isNifti2 = true; swapped = false
        } else if let little = value(at: 0, width: 4, swapped: true), little == 540 {
            isNifti2 = true; swapped = true
        } else {
            return nil
        }

        let dimBase = isNifti2 ? 16 : 40
        let dimWidth = isNifti2 ? 8 : 2
        let bitpixAt = isNifti2 ? 14 : 72
        guard let bitpix = value(at: bitpixAt, width: 2, swapped: swapped), bitpix > 0 else {
            return nil
        }

        // Frames live in dim[4..6]; a 4D series multiplies the whole volume.
        var frames: Int64 = 1
        for axis in 4...6 {
            guard let dim = value(at: dimBase + axis * dimWidth, width: dimWidth, swapped: swapped),
                  dim > 0 else { break }
            let (product, overflow) = frames.multipliedReportingOverflow(by: dim)
            if overflow { return Int.max }
            frames = product
        }

        var voxels: Int64 = 1
        for axis in 1...3 {
            guard let dim = value(at: dimBase + axis * dimWidth, width: dimWidth, swapped: swapped),
                  dim > 0 else {
                // A zero or negative dimension is not oversized, it is broken;
                // the page's own header check reports that far more usefully.
                return nil
            }
            // Multiply defensively: a hostile header's whole purpose is to make
            // this product overflow into something small and plausible.
            let (product, overflow) = voxels.multipliedReportingOverflow(by: dim)
            if overflow { return Int.max }
            voxels = product
        }
        func byteCount(for count: Int64) -> Int {
            let (bits, overflow) = count.multipliedReportingOverflow(by: bitpix)
            if overflow { return Int.max }
            let byteCount = bits / 8
            return byteCount > Int64(Int.max) ? Int.max : Int(byteCount)
        }
        let (allVoxels, overflow) = voxels.multipliedReportingOverflow(by: frames)
        return overflow ? Int.max : byteCount(for: allVoxels)
    }
}
