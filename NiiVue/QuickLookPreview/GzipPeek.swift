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
}
