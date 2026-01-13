import XCTest
@testable import NiiVue

final class PreprocessingContextTests: XCTestCase {
    func testCodableRoundTripPreservesContext() throws {
        let context = PreprocessingContext(
            dicomOriginLPS: .init(x: 1, y: 2, z: 3),
            dicomOrientationLPS: .identity,
            inputShape: .init(depth: 10, height: 20, width: 30),
            inputSpacing: .init(z: 2.5, y: 0.8, x: 0.8),
            transposeForward: [0, 1, 2],
            transposeBackward: [0, 1, 2],
            cropBoundingBox: .init(start: (z: 1, y: 2, x: 3), end: (z: 9, y: 18, x: 29)),
            outputShape: .init(depth: 8, height: 16, width: 26),
            outputSpacing: .init(z: 1.0, y: 1.0, x: 1.0)
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(context)
        let decoded = try decoder.decode(PreprocessingContext.self, from: data)

        XCTAssertEqual(decoded, context)
    }
}
