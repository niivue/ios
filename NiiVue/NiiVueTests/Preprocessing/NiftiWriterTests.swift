import XCTest
import nnUNetPreprocessing
import simd
@testable import NiiVue

final class NiftiWriterTests: XCTestCase {
    func testWriteWritesExpectedHeaderDimsPixdimAndSform() throws {
        let shape = (depth: 3, height: 4, width: 5) // (z, y, x)
        let voxelCount = shape.depth * shape.height * shape.width
        let floats = (0..<voxelCount).map { Float($0) }
        let data = floats.withUnsafeBytes { Data($0) }

        // VolumeBuffer uses (z, y, x) axis ordering for shape/spacing.
        let spacing = SIMD3<Double>(2.0, 3.0, 4.0) // (z, y, x)

        // Orientation columns in VolumeBuffer correspond to (z, y, x) axes in LPS.
        // Use identity in patient space (x,y,z), but reordered to (z,y,x) columns.
        let orientation = simd_double3x3(columns: (
            SIMD3<Double>(0, 0, 1), // z axis
            SIMD3<Double>(0, 1, 0), // y axis
            SIMD3<Double>(1, 0, 0)  // x axis
        ))
        let originLPS = SIMD3<Double>(10, 20, 30)

        let volume = VolumeBuffer(
            data: data,
            shape: shape,
            spacing: spacing,
            origin: originLPS,
            orientation: orientation
        )

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NiftiWriterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let outputURL = dir.appendingPathComponent("out.nii", isDirectory: false)
        try NiftiWriter.write(volume: volume, to: outputURL)

        let bytes = try Data(contentsOf: outputURL)
        XCTAssertGreaterThanOrEqual(bytes.count, 352)
        XCTAssertEqual(bytes.count, 352 + voxelCount * MemoryLayout<Float>.size)

        func readInt16LE(_ offset: Int) -> Int16 {
            let v = bytes.withUnsafeBytes { ptr -> Int16 in
                ptr.load(fromByteOffset: offset, as: Int16.self)
            }
            return Int16(littleEndian: v)
        }

        func readInt32LE(_ offset: Int) -> Int32 {
            let v = bytes.withUnsafeBytes { ptr -> Int32 in
                ptr.load(fromByteOffset: offset, as: Int32.self)
            }
            return Int32(littleEndian: v)
        }

        func readFloat32LE(_ offset: Int) -> Float32 {
            let v = bytes.withUnsafeBytes { ptr -> UInt32 in
                ptr.load(fromByteOffset: offset, as: UInt32.self)
            }
            return Float32(bitPattern: UInt32(littleEndian: v))
        }

        // sizeof_hdr at 0
        XCTAssertEqual(readInt32LE(0), 348)

        // dim starts at 40 (int16[8])
        let dim0 = readInt16LE(40)
        let dim1 = readInt16LE(42)
        let dim2 = readInt16LE(44)
        let dim3 = readInt16LE(46)
        XCTAssertEqual(dim0, 3)
        XCTAssertEqual(dim1, Int16(shape.width))
        XCTAssertEqual(dim2, Int16(shape.height))
        XCTAssertEqual(dim3, Int16(shape.depth))

        // datatype (int16) at 70? In NIfTI-1 it is at 70 (datatype) / 72? (bitpix)
        // Use official offsets: datatype=70, bitpix=72.
        XCTAssertEqual(readInt16LE(70), 16, "datatype should be DT_FLOAT32 (16)")
        XCTAssertEqual(readInt16LE(72), 32, "bitpix should be 32 for float32")

        // pixdim starts at 76 (float32[8]) in NIfTI-1
        let pixdim1 = readFloat32LE(80)
        let pixdim2 = readFloat32LE(84)
        let pixdim3 = readFloat32LE(88)
        XCTAssertEqual(pixdim1, Float32(spacing.z), accuracy: 1e-6) // x spacing
        XCTAssertEqual(pixdim2, Float32(spacing.y), accuracy: 1e-6) // y spacing
        XCTAssertEqual(pixdim3, Float32(spacing.x), accuracy: 1e-6) // z spacing

        // vox_offset at 108
        XCTAssertEqual(readFloat32LE(108), 352, accuracy: 1e-6)

        // qform_code at 252, sform_code at 254 (NIfTI-1)
        XCTAssertEqual(readInt16LE(252), 0, "qform_code should be 0 (we rely on sform)")
        XCTAssertEqual(readInt16LE(254), 1, "sform_code should be 1")

        // srow_x/y/z at 280/296/312
        let srowX = (0..<4).map { readFloat32LE(280 + $0 * 4) }
        let srowY = (0..<4).map { readFloat32LE(296 + $0 * 4) }
        let srowZ = (0..<4).map { readFloat32LE(312 + $0 * 4) }

        // Expected LPS->RAS conversion (negate X and Y).
        // Affine maps voxel i,j,k (x,y,z) to world RAS:
        // origin_RAS + dirX_RAS*i*spX + dirY_RAS*j*spY + dirZ_RAS*k*spZ
        let originRAS = SIMD3<Float32>(-Float32(originLPS.x), -Float32(originLPS.y), Float32(originLPS.z))
        XCTAssertEqual(srowX[0], -Float32(spacing.z), accuracy: 1e-6)
        XCTAssertEqual(srowX[1], 0, accuracy: 1e-6)
        XCTAssertEqual(srowX[2], 0, accuracy: 1e-6)
        XCTAssertEqual(srowX[3], originRAS.x, accuracy: 1e-6)

        XCTAssertEqual(srowY[0], 0, accuracy: 1e-6)
        XCTAssertEqual(srowY[1], -Float32(spacing.y), accuracy: 1e-6)
        XCTAssertEqual(srowY[2], 0, accuracy: 1e-6)
        XCTAssertEqual(srowY[3], originRAS.y, accuracy: 1e-6)

        XCTAssertEqual(srowZ[0], 0, accuracy: 1e-6)
        XCTAssertEqual(srowZ[1], 0, accuracy: 1e-6)
        XCTAssertEqual(srowZ[2], Float32(spacing.x), accuracy: 1e-6)
        XCTAssertEqual(srowZ[3], originRAS.z, accuracy: 1e-6)
    }
}
