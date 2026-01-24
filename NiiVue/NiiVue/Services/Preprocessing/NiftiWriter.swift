import Foundation
import DicomCore
import nnUNetPreprocessing
import simd

protocol NiftiWriting {
    func write(_ volume: VolumeBuffer, to url: URL) throws
}

struct NiftiWriter: NiftiWriting {
    func write(_ volume: VolumeBuffer, to url: URL) throws {
        try Self.write(volume: volume, to: url)
    }

    static func write(volume: VolumeBuffer, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let header = makeHeader(for: volume)
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: volume.data)
    }

    static func write(dicomVolume: DicomSeriesVolume, to url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        let header = makeHeader(for: dicomVolume)
        try handle.write(contentsOf: header)
        try handle.write(contentsOf: dicomVolume.voxels)
    }

    private static func makeHeader(for volume: VolumeBuffer) -> Data {
        var header = Data(count: 352)
        header.withUnsafeMutableBytes { raw in
            writeInt32LE(348, to: raw, offset: 0)

            writeInt16LE(3, to: raw, offset: 40)
            writeInt16LE(Int16(volume.shape.width), to: raw, offset: 42)
            writeInt16LE(Int16(volume.shape.height), to: raw, offset: 44)
            writeInt16LE(Int16(volume.shape.depth), to: raw, offset: 46)
            writeInt16LE(1, to: raw, offset: 48)
            writeInt16LE(1, to: raw, offset: 50)
            writeInt16LE(1, to: raw, offset: 52)
            writeInt16LE(1, to: raw, offset: 54)

            writeInt16LE(16, to: raw, offset: 70) // DT_FLOAT32
            writeInt16LE(32, to: raw, offset: 72) // bitpix

            let spacingX = volume.spacing.z
            let spacingY = volume.spacing.y
            let spacingZ = volume.spacing.x
            writeFloat32LE(0, to: raw, offset: 76) // pixdim[0]
            writeFloat32LE(Float32(spacingX), to: raw, offset: 80) // pixdim[1]
            writeFloat32LE(Float32(spacingY), to: raw, offset: 84) // pixdim[2]
            writeFloat32LE(Float32(spacingZ), to: raw, offset: 88) // pixdim[3]

            writeFloat32LE(352, to: raw, offset: 108) // vox_offset

            writeInt16LE(0, to: raw, offset: 252) // qform_code
            writeInt16LE(1, to: raw, offset: 254) // sform_code

            let originRAS = lpsToRas(volume.origin)
            let dirZ = lpsToRas(volume.orientation.columns.0)
            let dirY = lpsToRas(volume.orientation.columns.1)
            let dirX = lpsToRas(volume.orientation.columns.2)

            writeFloat32LE(Float32(dirX.x * spacingX), to: raw, offset: 280)
            writeFloat32LE(Float32(dirY.x * spacingY), to: raw, offset: 284)
            writeFloat32LE(Float32(dirZ.x * spacingZ), to: raw, offset: 288)
            writeFloat32LE(Float32(originRAS.x), to: raw, offset: 292)

            writeFloat32LE(Float32(dirX.y * spacingX), to: raw, offset: 296)
            writeFloat32LE(Float32(dirY.y * spacingY), to: raw, offset: 300)
            writeFloat32LE(Float32(dirZ.y * spacingZ), to: raw, offset: 304)
            writeFloat32LE(Float32(originRAS.y), to: raw, offset: 308)

            writeFloat32LE(Float32(dirX.z * spacingX), to: raw, offset: 312)
            writeFloat32LE(Float32(dirY.z * spacingY), to: raw, offset: 316)
            writeFloat32LE(Float32(dirZ.z * spacingZ), to: raw, offset: 320)
            writeFloat32LE(Float32(originRAS.z), to: raw, offset: 324)

            raw.storeBytes(of: UInt8(ascii: "n"), toByteOffset: 344, as: UInt8.self)
            raw.storeBytes(of: UInt8(ascii: "+"), toByteOffset: 345, as: UInt8.self)
            raw.storeBytes(of: UInt8(ascii: "1"), toByteOffset: 346, as: UInt8.self)
            raw.storeBytes(of: 0 as UInt8, toByteOffset: 347, as: UInt8.self)
        }
        return header
    }

    private static func makeHeader(for volume: DicomSeriesVolume) -> Data {
        var header = Data(count: 352)
        header.withUnsafeMutableBytes { raw in
            writeInt32LE(348, to: raw, offset: 0)

            writeInt16LE(3, to: raw, offset: 40)
            writeInt16LE(Int16(volume.width), to: raw, offset: 42)
            writeInt16LE(Int16(volume.height), to: raw, offset: 44)
            writeInt16LE(Int16(volume.depth), to: raw, offset: 46)
            writeInt16LE(1, to: raw, offset: 48)
            writeInt16LE(1, to: raw, offset: 50)
            writeInt16LE(1, to: raw, offset: 52)
            writeInt16LE(1, to: raw, offset: 54)

            let datatype: Int16 = volume.isSignedPixel ? 4 : 512 // DT_INT16 or DT_UINT16
            writeInt16LE(datatype, to: raw, offset: 70)
            writeInt16LE(16, to: raw, offset: 72) // bitpix

            let spacingX = volume.spacing.x
            let spacingY = volume.spacing.y
            let spacingZ = volume.spacing.z
            writeFloat32LE(0, to: raw, offset: 76) // pixdim[0]
            writeFloat32LE(Float32(spacingX), to: raw, offset: 80) // pixdim[1]
            writeFloat32LE(Float32(spacingY), to: raw, offset: 84) // pixdim[2]
            writeFloat32LE(Float32(spacingZ), to: raw, offset: 88) // pixdim[3]

            writeFloat32LE(352, to: raw, offset: 108) // vox_offset

            let slope = volume.rescaleSlope == 0 ? 1.0 : volume.rescaleSlope
            writeFloat32LE(Float32(slope), to: raw, offset: 112) // scl_slope
            writeFloat32LE(Float32(volume.rescaleIntercept), to: raw, offset: 116) // scl_inter

            writeInt16LE(0, to: raw, offset: 252) // qform_code
            writeInt16LE(1, to: raw, offset: 254) // sform_code

            let originRAS = lpsToRas(volume.origin)
            let dirX = lpsToRas(volume.orientation.columns.0)
            let dirY = lpsToRas(volume.orientation.columns.1)
            let dirZ = lpsToRas(volume.orientation.columns.2)

            writeFloat32LE(Float32(dirX.x * spacingX), to: raw, offset: 280)
            writeFloat32LE(Float32(dirY.x * spacingY), to: raw, offset: 284)
            writeFloat32LE(Float32(dirZ.x * spacingZ), to: raw, offset: 288)
            writeFloat32LE(Float32(originRAS.x), to: raw, offset: 292)

            writeFloat32LE(Float32(dirX.y * spacingX), to: raw, offset: 296)
            writeFloat32LE(Float32(dirY.y * spacingY), to: raw, offset: 300)
            writeFloat32LE(Float32(dirZ.y * spacingZ), to: raw, offset: 304)
            writeFloat32LE(Float32(originRAS.y), to: raw, offset: 308)

            writeFloat32LE(Float32(dirX.z * spacingX), to: raw, offset: 312)
            writeFloat32LE(Float32(dirY.z * spacingY), to: raw, offset: 316)
            writeFloat32LE(Float32(dirZ.z * spacingZ), to: raw, offset: 320)
            writeFloat32LE(Float32(originRAS.z), to: raw, offset: 324)

            raw.storeBytes(of: UInt8(ascii: "n"), toByteOffset: 344, as: UInt8.self)
            raw.storeBytes(of: UInt8(ascii: "+"), toByteOffset: 345, as: UInt8.self)
            raw.storeBytes(of: UInt8(ascii: "1"), toByteOffset: 346, as: UInt8.self)
            raw.storeBytes(of: 0 as UInt8, toByteOffset: 347, as: UInt8.self)
        }
        return header
    }

    private static func lpsToRas(_ v: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(-v.x, -v.y, v.z)
    }

    private static func writeInt16LE(_ value: Int16, to raw: UnsafeMutableRawBufferPointer, offset: Int) {
        raw.storeBytes(of: value.littleEndian, toByteOffset: offset, as: Int16.self)
    }

    private static func writeInt32LE(_ value: Int32, to raw: UnsafeMutableRawBufferPointer, offset: Int) {
        raw.storeBytes(of: value.littleEndian, toByteOffset: offset, as: Int32.self)
    }

    private static func writeFloat32LE(_ value: Float32, to raw: UnsafeMutableRawBufferPointer, offset: Int) {
        raw.storeBytes(of: value.bitPattern.littleEndian, toByteOffset: offset, as: UInt32.self)
    }
}
