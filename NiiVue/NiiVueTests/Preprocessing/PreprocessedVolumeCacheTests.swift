import XCTest
@testable import NiiVue

final class PreprocessedVolumeCacheTests: XCTestCase {
    private var cache: PreprocessedVolumeCache!
    private var testDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("NiiVueCacheTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true)
        cache = PreprocessedVolumeCache(baseURL: testDir)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: testDir)
        try await super.tearDown()
    }

    func testCacheMissReturnsNil() async {
        let result = await cache.getCached(
            studyID: "missing-study",
            itemID: "missing-item",
            parameters: .urinaryTractDefaults
        )
        XCTAssertNil(result)
    }

    func testHasCachedReturnsFalseForMiss() async {
        let hasCached = await cache.hasCached(
            studyID: "missing-study",
            itemID: "missing-item",
            parameters: .urinaryTractDefaults
        )
        XCTAssertFalse(hasCached)
    }

    func testStoreAndRetrieveReturnsCachedResult() async throws {
        let sourceFile = testDir.appendingPathComponent("source.nii", isDirectory: false)
        try Data("test".utf8).write(to: sourceFile)

        let result = PreprocessedResult(
            outputURL: sourceFile,
            processingTime: 0.01,
            parameters: .urinaryTractDefaults
        )

        try await cache.store(studyID: "study1", itemID: "item1", result: result)

        let retrieved = await cache.getCached(
            studyID: "study1",
            itemID: "item1",
            parameters: .urinaryTractDefaults
        )

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.parameters, result.parameters)
        XCTAssertTrue(retrieved?.outputURL.path.hasPrefix(testDir.path) ?? false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retrieved?.outputURL.path ?? ""))
    }

    func testStorePreservesCompoundNiiGzExtension() async throws {
        let sourceFile = testDir.appendingPathComponent("source.nii.gz", isDirectory: false)
        try Data("test".utf8).write(to: sourceFile)

        let result = PreprocessedResult(
            outputURL: sourceFile,
            processingTime: 0.01,
            parameters: .urinaryTractDefaults
        )

        try await cache.store(studyID: "study1", itemID: "item1", result: result)

        let retrieved = await cache.getCached(
            studyID: "study1",
            itemID: "item1",
            parameters: .urinaryTractDefaults
        )

        XCTAssertEqual(retrieved?.outputURL.lastPathComponent, "preprocessed.nii.gz")
        XCTAssertTrue(FileManager.default.fileExists(atPath: retrieved?.outputURL.path ?? ""))
    }

    func testInvalidateStudyRemovesCachedResult() async throws {
        let sourceFile = testDir.appendingPathComponent("source.nii", isDirectory: false)
        try Data("test".utf8).write(to: sourceFile)

        let result = PreprocessedResult(
            outputURL: sourceFile,
            processingTime: 0.01,
            parameters: .urinaryTractDefaults
        )

        try await cache.store(studyID: "study1", itemID: "item1", result: result)

        await cache.invalidate(studyID: "study1")

        let retrieved = await cache.getCached(
            studyID: "study1",
            itemID: "item1",
            parameters: .urinaryTractDefaults
        )
        XCTAssertNil(retrieved)
    }

    func testDifferentParametersNotCached() async throws {
        let sourceFile = testDir.appendingPathComponent("source.nii", isDirectory: false)
        try Data("test".utf8).write(to: sourceFile)

        let result = PreprocessedResult(
            outputURL: sourceFile,
            processingTime: 0.01,
            parameters: .urinaryTractDefaults
        )

        try await cache.store(studyID: "study1", itemID: "item1", result: result)

        let retrieved = await cache.getCached(
            studyID: "study1",
            itemID: "item1",
            parameters: .quickPreview
        )

        XCTAssertNil(retrieved)
    }

    func testStoreGeneratedMovesFileAndWritesMetadata() async throws {
        let generatedFile = testDir.appendingPathComponent("generated.nii", isDirectory: false)
        try Data("generated".utf8).write(to: generatedFile)

        let parameters = CTPreprocessingParameters.urinaryTractDefaults
        let stored = try await cache.storeGenerated(
            studyID: "study1",
            itemID: "item1",
            generatedFileURL: generatedFile,
            processingTime: 1.23,
            parameters: parameters
        )

        XCTAssertEqual(stored.outputURL.lastPathComponent, "preprocessed.nii")
        XCTAssertTrue(FileManager.default.fileExists(atPath: stored.outputURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: generatedFile.path), "Generated file should be moved into cache (no extra copy).")

        let retrieved = await cache.getCached(studyID: "study1", itemID: "item1", parameters: parameters)
        XCTAssertEqual(retrieved, stored)
    }
}
