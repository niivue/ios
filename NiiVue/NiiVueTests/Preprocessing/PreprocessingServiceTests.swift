import nnUNetPreprocessing
import simd
import XCTest
@testable import NiiVue

final class PreprocessingServiceTests: XCTestCase {
    private final class CountingDicomLoader: DicomSeriesVolumeLoading {
        private(set) var loadCount: Int = 0
        private let volume: VolumeBuffer

        init(volume: VolumeBuffer) {
            self.volume = volume
        }

        func loadSeries(from dicomFileURLs: [URL]) throws -> VolumeBuffer {
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

        // Synthetic 2x2x1 float32 volume (already HU) with identity orientation in patient space.
        let voxels = [Float(0), 100, 200, 300]
        let voxelData = voxels.withUnsafeBytes { Data($0) }
        let orientation = simd_double3x3(columns: (
            SIMD3<Double>(0, 0, 1), // z axis
            SIMD3<Double>(0, 1, 0), // y axis
            SIMD3<Double>(1, 0, 0)  // x axis
        ))
        let volume = VolumeBuffer(
            data: voxelData,
            shape: (depth: 1, height: 2, width: 2),
            spacing: SIMD3<Double>(1, 1, 1),
            origin: SIMD3<Double>(10, 20, 30),
            orientation: orientation
        )

        let loader = CountingDicomLoader(volume: volume)
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

        let volume = VolumeBuffer(
            data: Data(repeating: 0, count: 4 * MemoryLayout<Float>.size),
            shape: (depth: 1, height: 2, width: 2),
            spacing: SIMD3<Double>(1, 1, 1)
        )

        let loader = CountingDicomLoader(volume: volume)
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
