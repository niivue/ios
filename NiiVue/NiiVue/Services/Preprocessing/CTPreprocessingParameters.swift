import CryptoKit
import Foundation

public struct CTPreprocessingParameters: Codable, Sendable, Equatable {
    public struct ClipRange: Codable, Sendable, Equatable {
        public var min: Double
        public var max: Double

        public init(min: Double, max: Double) {
            self.min = min
            self.max = max
        }
    }

    public var lowerPercentile: Double
    public var upperPercentile: Double
    public var useZScoreNormalization: Bool

    public var isotropicTarget: Double?
    public var interpolationOrder: Int

    public var cropToNonzero: Bool
    public var paddingVoxels: Int

    public var customClipRange: ClipRange?
    public var useCustomClipAsPrefilter: Bool

    public init(
        lowerPercentile: Double = 0.5,
        upperPercentile: Double = 99.5,
        useZScoreNormalization: Bool = true,
        isotropicTarget: Double? = 1.0,
        interpolationOrder: Int = 3,
        cropToNonzero: Bool = true,
        paddingVoxels: Int = 10,
        customClipRange: ClipRange? = nil,
        useCustomClipAsPrefilter: Bool = false
    ) {
        self.lowerPercentile = lowerPercentile
        self.upperPercentile = upperPercentile
        self.useZScoreNormalization = useZScoreNormalization
        self.isotropicTarget = isotropicTarget
        self.interpolationOrder = interpolationOrder
        self.cropToNonzero = cropToNonzero
        self.paddingVoxels = paddingVoxels
        self.customClipRange = customClipRange
        self.useCustomClipAsPrefilter = useCustomClipAsPrefilter
    }

    public static let urinaryTractDefaults = CTPreprocessingParameters(
        lowerPercentile: 0.5,
        upperPercentile: 99.5,
        useZScoreNormalization: true,
        isotropicTarget: 1.0,
        interpolationOrder: 3,
        cropToNonzero: true,
        paddingVoxels: 10,
        customClipRange: nil,
        useCustomClipAsPrefilter: false
    )

    public static let quickPreview = CTPreprocessingParameters(
        lowerPercentile: 0.5,
        upperPercentile: 99.5,
        useZScoreNormalization: true,
        isotropicTarget: 2.0,
        interpolationOrder: 1,
        cropToNonzero: true,
        paddingVoxels: 10,
        customClipRange: nil,
        useCustomClipAsPrefilter: false
    )

    public var parametersHash: String {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(self)
            let digest = SHA256.hash(data: data)
            return digest.map { String(format: "%02x", $0) }.joined()
        } catch {
            return "invalid"
        }
    }
}

