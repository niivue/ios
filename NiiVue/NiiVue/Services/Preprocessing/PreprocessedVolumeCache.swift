import Foundation

public struct PreprocessedResult: Codable, Sendable, Equatable {
    public var outputURL: URL
    public var processingTime: TimeInterval
    public var parameters: CTPreprocessingParameters
    public var timestamp: Date

    public init(
        outputURL: URL,
        processingTime: TimeInterval,
        parameters: CTPreprocessingParameters,
        timestamp: Date = Date()
    ) {
        self.outputURL = outputURL
        self.processingTime = processingTime
        self.parameters = parameters
        self.timestamp = timestamp
    }
}

public actor PreprocessedVolumeCache {
    private let baseURL: URL
    private var memoryCache: [String: PreprocessedResult] = [:]

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NiiVue/PreprocessedCache", isDirectory: true)

        try? FileManager.default.createDirectory(at: self.baseURL, withIntermediateDirectories: true)
    }

    public func hasCached(
        studyID: String,
        itemID: String,
        parameters: CTPreprocessingParameters
    ) -> Bool {
        getCached(studyID: studyID, itemID: itemID, parameters: parameters) != nil
    }

    public func getCached(
        studyID: String,
        itemID: String,
        parameters: CTPreprocessingParameters
    ) -> PreprocessedResult? {
        let key = cacheKey(studyID: studyID, itemID: itemID, parameters: parameters)

        if let result = memoryCache[key] {
            guard FileManager.default.fileExists(atPath: result.outputURL.path) else {
                memoryCache.removeValue(forKey: key)
                return nil
            }
            return result
        }

        let metadataURL = cacheDirectory(studyID: studyID, itemID: itemID, parametersHash: parameters.parametersHash)
            .appendingPathComponent("metadata.json", isDirectory: false)

        guard FileManager.default.fileExists(atPath: metadataURL.path),
              let data = try? Data(contentsOf: metadataURL)
        else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(PreprocessedResult.self, from: data),
              FileManager.default.fileExists(atPath: decoded.outputURL.path)
        else {
            return nil
        }

        memoryCache[key] = decoded
        return decoded
    }

    public func store(
        studyID: String,
        itemID: String,
        result: PreprocessedResult
    ) throws {
        let parametersHash = result.parameters.parametersHash
        let cacheDir = cacheDirectory(studyID: studyID, itemID: itemID, parametersHash: parametersHash)
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let ext: String
        if result.outputURL.pathExtension.lowercased() == "gz",
           result.outputURL.deletingPathExtension().pathExtension.lowercased() == "nii"
        {
            ext = "nii.gz"
        } else if result.outputURL.pathExtension.isEmpty {
            ext = "nii"
        } else {
            ext = result.outputURL.pathExtension
        }

        let cachedVolumeURL = cacheDir.appendingPathComponent("preprocessed.\(ext)", isDirectory: false)
        if FileManager.default.fileExists(atPath: cachedVolumeURL.path) {
            try FileManager.default.removeItem(at: cachedVolumeURL)
        }
        try FileManager.default.copyItem(at: result.outputURL, to: cachedVolumeURL)

        var storedResult = result
        storedResult.outputURL = cachedVolumeURL

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let metadataData = try encoder.encode(storedResult)
        try metadataData.write(to: cacheDir.appendingPathComponent("metadata.json", isDirectory: false))

        memoryCache[cacheKey(studyID: studyID, itemID: itemID, parameters: result.parameters)] = storedResult
    }

    public func invalidate(studyID: String) {
        let prefix = "\(studyID)/"
        memoryCache.keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { memoryCache.removeValue(forKey: $0) }

        let studyDir = baseURL.appendingPathComponent(studyID, isDirectory: true)
        try? FileManager.default.removeItem(at: studyDir)
    }

    private func cacheKey(
        studyID: String,
        itemID: String,
        parameters: CTPreprocessingParameters
    ) -> String {
        "\(studyID)/\(itemID)/\(parameters.parametersHash)"
    }

    private func cacheDirectory(studyID: String, itemID: String, parametersHash: String) -> URL {
        baseURL
            .appendingPathComponent(studyID, isDirectory: true)
            .appendingPathComponent(itemID, isDirectory: true)
            .appendingPathComponent(parametersHash, isDirectory: true)
    }

    public func cachedFileURL(
        studyID: String,
        itemID: String,
        parametersHash: String,
        fileName: String
    ) -> URL {
        cacheDirectory(studyID: studyID, itemID: itemID, parametersHash: parametersHash)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}
