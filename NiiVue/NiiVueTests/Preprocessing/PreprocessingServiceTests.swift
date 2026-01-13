import DicomCore
import nnUNetPreprocessing
import simd
import XCTest
@testable import NiiVue

final class PreprocessingServiceTests: XCTestCase {
    private final class CountingDicomLoader: DicomSeriesVolumeLoading {
        private(set) var loadCount: Int = 0
        private let volume: DicomSeriesVolume

        init(volume: DicomSeriesVolume) {
            self.volume = volume
        }

        func loadSeries(from dicomFileURLs: [URL]) throws -> DicomSeriesVolume {
            loadCount += 1
            return volume
        }
    }

    private final class CountingPreprocessor: VolumePreprocessing {
        private(set) var preprocessCount: Int = 0

        func preprocess(_ volume: VolumeBuffer, parameters: CTPreprocessingParameters) async throws -> VolumeBuffer {
            preprocessCount += 1
            return volume
        }
    }

    private final class CountingWriter: NiftiWriting {
        private(set) var writeCount: Int = 0

        func write(_ volume: VolumeBuffer, to url: URL) throws {
            writeCount += 1

            // Minimal NIfTI-like blob: header+extension+payload (we verify full correctness in NiftiWriterTests).
            let size = 352 + volume.voxelCount * MemoryLayout<Float>.size
            try Data(repeating: 0, count: size).write(to: url)
        }
    }

    func testCacheMissPreprocessesAndStoresInCache() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreprocessingServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = PreprocessedVolumeCache(baseURL: tempDir.appendingPathComponent("cache", isDirectory: true))

        // Synthetic 2x2x1 signed-int16 volume (raw) with identity orientation in patient space.
        let voxels = [Int16(0), 100, 200, 300]
        let voxelData = voxels.withUnsafeBytes { Data($0) }
        let orientation = simd_double3x3(columns: (
            SIMD3<Double>(1, 0, 0), // row
            SIMD3<Double>(0, 1, 0), // column
            SIMD3<Double>(0, 0, 1)  // normal
        ))

        let series = DicomSeriesVolume(
            voxels: voxelData,
            width: 2,
            height: 2,
            depth: 1,
            spacing: SIMD3<Double>(1, 1, 1),
            orientation: orientation,
            origin: SIMD3<Double>(10, 20, 30),
            rescaleSlope: 1.0,
            rescaleIntercept: 0.0,
            bitsAllocated: 16,
            isSignedPixel: true,
            seriesDescription: "test"
        )

        let loader = CountingDicomLoader(volume: series)
        let preprocessor = CountingPreprocessor()
        let writer = CountingWriter()

        let service = PreprocessingService(
            cache: cache,
            dicomLoader: loader,
            preprocessor: preprocessor,
            writer: writer
        )

        let parameters = CTPreprocessingParameters.urinaryTractDefaults
        let result = try await service.preprocessDicomSeries(
            studyID: "study1",
            itemID: "item1",
            dicomFileURLs: [tempDir.appendingPathComponent("dummy.dcm")],
            parameters: parameters
        )

        XCTAssertEqual(loader.loadCount, 1)
        XCTAssertEqual(preprocessor.preprocessCount, 1)
        XCTAssertEqual(writer.writeCount, 1)

        XCTAssertEqual(result.outputURL.lastPathComponent, "preprocessed.nii")
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))

        let cached = await cache.getCached(studyID: "study1", itemID: "item1", parameters: parameters)
        XCTAssertEqual(cached, result)
    }

    func testCacheHitReturnsWithoutInvokingDependencies() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreprocessingServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let cache = PreprocessedVolumeCache(baseURL: tempDir.appendingPathComponent("cache", isDirectory: true))
        let parameters = CTPreprocessingParameters.urinaryTractDefaults

        // Seed cache with an existing preprocessed file.
        let generatedFile = tempDir.appendingPathComponent("seed.nii", isDirectory: false)
        try Data(repeating: 1, count: 352 + 4 * MemoryLayout<Float>.size).write(to: generatedFile)
        _ = try await cache.storeGenerated(
            studyID: "study1",
            itemID: "item1",
            generatedFileURL: generatedFile,
            processingTime: 0.01,
            parameters: parameters
        )

        let voxels = [Int16(0), 0, 0, 0]
        let voxelData = voxels.withUnsafeBytes { Data($0) }
        let orientation = simd_double3x3(columns: (
            SIMD3<Double>(1, 0, 0),
            SIMD3<Double>(0, 1, 0),
            SIMD3<Double>(0, 0, 1)
        ))

        let series = DicomSeriesVolume(
            voxels: voxelData,
            width: 2,
            height: 2,
            depth: 1,
            spacing: SIMD3<Double>(1, 1, 1),
            orientation: orientation,
            origin: SIMD3<Double>(0, 0, 0),
            rescaleSlope: 1.0,
            rescaleIntercept: 0.0,
            bitsAllocated: 16,
            isSignedPixel: true,
            seriesDescription: "test"
        )

        let loader = CountingDicomLoader(volume: series)
        let preprocessor = CountingPreprocessor()
        let writer = CountingWriter()

        let service = PreprocessingService(
            cache: cache,
            dicomLoader: loader,
            preprocessor: preprocessor,
            writer: writer
        )

        let result = try await service.preprocessDicomSeries(
            studyID: "study1",
            itemID: "item1",
            dicomFileURLs: [tempDir.appendingPathComponent("dummy.dcm")],
            parameters: parameters
        )

        XCTAssertEqual(loader.loadCount, 0)
        XCTAssertEqual(preprocessor.preprocessCount, 0)
        XCTAssertEqual(writer.writeCount, 0)
        XCTAssertEqual(result.outputURL.lastPathComponent, "preprocessed.nii")
    }
}

