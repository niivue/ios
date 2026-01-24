import XCTest
@testable import NiiVue

final class CTPreprocessingParametersTests: XCTestCase {
    func testDefaultInitialization() {
        let params = CTPreprocessingParameters()

        XCTAssertEqual(params.lowerPercentile, 0.5)
        XCTAssertEqual(params.upperPercentile, 99.5)
        XCTAssertTrue(params.useZScoreNormalization)

        XCTAssertEqual(params.isotropicTarget, 1.0)
        XCTAssertEqual(params.interpolationOrder, 3)

        XCTAssertTrue(params.cropToNonzero)
        XCTAssertEqual(params.paddingVoxels, 10)

        XCTAssertNil(params.customClipRange)
        XCTAssertFalse(params.useCustomClipAsPrefilter)
    }

    func testUrinaryTractDefaults() {
        let params = CTPreprocessingParameters.urinaryTractDefaults

        XCTAssertEqual(params.lowerPercentile, 0.5)
        XCTAssertEqual(params.upperPercentile, 99.5)
        XCTAssertEqual(params.isotropicTarget, 1.0)
        XCTAssertTrue(params.cropToNonzero)
        XCTAssertEqual(params.paddingVoxels, 10)
    }

    func testQuickPreviewPreset() {
        let params = CTPreprocessingParameters.quickPreview

        XCTAssertEqual(params.isotropicTarget, 2.0)
        XCTAssertEqual(params.interpolationOrder, 1) // Linear for speed
    }

    func testCodableRoundTrip() throws {
        let params = CTPreprocessingParameters.urinaryTractDefaults
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(params)
        let decoded = try decoder.decode(CTPreprocessingParameters.self, from: data)

        XCTAssertEqual(params, decoded)
    }

    func testParametersHashChangesWhenParametersChange() {
        let params1 = CTPreprocessingParameters.urinaryTractDefaults
        let params2 = CTPreprocessingParameters.urinaryTractDefaults
        var params3 = CTPreprocessingParameters.urinaryTractDefaults
        params3.lowerPercentile = 1.0

        XCTAssertEqual(params1.parametersHash, params2.parametersHash)
        XCTAssertNotEqual(params1.parametersHash, params3.parametersHash)
    }
}

