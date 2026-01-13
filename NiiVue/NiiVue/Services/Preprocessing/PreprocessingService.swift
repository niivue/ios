import DicomCore
import Foundation
import nnUNetPreprocessing

protocol DicomSeriesVolumeLoading {
    func loadSeries(from dicomFileURLs: [URL]) throws -> DicomSeriesVolume
}

protocol VolumePreprocessing {
    func preprocess(_ volume: VolumeBuffer, parameters: CTPreprocessingParameters) async throws -> VolumeBuffer
}

struct PreprocessingService {
    let cache: PreprocessedVolumeCache
    let dicomLoader: DicomSeriesVolumeLoading
    let preprocessor: VolumePreprocessing
    let writer: NiftiWriting

    init(
        cache: PreprocessedVolumeCache,
        dicomLoader: DicomSeriesVolumeLoading,
        preprocessor: VolumePreprocessing,
        writer: NiftiWriting
    ) {
        self.cache = cache
        self.dicomLoader = dicomLoader
        self.preprocessor = preprocessor
        self.writer = writer
    }

    func preprocessDicomSeries(
        studyID: String,
        itemID: String,
        dicomFileURLs: [URL],
        parameters: CTPreprocessingParameters
    ) async throws -> PreprocessedResult {
        if let cached = await cache.getCached(studyID: studyID, itemID: itemID, parameters: parameters) {
            return cached
        }

        let start = Date()
        let series = try dicomLoader.loadSeries(from: dicomFileURLs)
        let volumeHU = DicomBridge.convert(series)
        let processed = try await preprocessor.preprocess(volumeHU, parameters: parameters)

        let stagingDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NiiVuePreprocessing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let generatedFileURL = stagingDir.appendingPathComponent("preprocessed.nii", isDirectory: false)

        try writer.write(processed, to: generatedFileURL)

        let result = try await cache.storeGenerated(
            studyID: studyID,
            itemID: itemID,
            generatedFileURL: generatedFileURL,
            processingTime: Date().timeIntervalSince(start),
            parameters: parameters
        )

        try? FileManager.default.removeItem(at: stagingDir)
        return result
    }
}

