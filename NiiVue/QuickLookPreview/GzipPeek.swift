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

    /// Inflate at most `peekBytes` from the start of a gzip member.
    /// Returns nil if `data` is not gzip, or is truncated//corrupt.
    static func inflatePrefix(of data: Data) -> Data? {
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

        let deflate = data[index...]
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

    /// Bytes one frame of this volume will occupy once decoded, or nil if the
    /// header is not a NIfTI we can measure.
    ///
    /// This exists because the file-size cap does **not** bound the decoded
    /// size: a few hundred kilobytes of gzip can claim any dimensions it likes,
    /// and the allocation that follows happens inside WebKit's content process
    /// where a refusal is a crash rather than an error. Measuring the header
    /// before the page ever fetches the file is the only point at which a
    /// hostile one can be turned away cheaply.
    ///
    /// Frame count is deliberately clamped to one — the preview loads frame
    /// zero only (`limitFrames4D: 1`), so a 2000-volume time series is not
    /// oversized by virtue of being long.
    static func decodedFrameBytes(_ header: Data) -> Int? {
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
        let (bits, overflow) = voxels.multipliedReportingOverflow(by: bitpix)
        if overflow { return Int.max }
        let byteCount = bits / 8
        return byteCount > Int64(Int.max) ? Int.max : Int(byteCount)
    }
}
