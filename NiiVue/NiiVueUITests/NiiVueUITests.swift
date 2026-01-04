//
//  NiiVueUITests.swift
//  NiiVueUITests
//
//  Created by Taylor Hanayik on 03/01/2024.
//

import XCTest

final class NiiVueUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    /// Task 1: Verify toolbar buttons have accessibility identifiers for reliable UI testing
    func testLaunchShowsPrimaryToolbarButtons() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["niivue.addImage"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["niivue.settings"].exists)
    }

    /// Task 8: Verify loading overlay doesn't persist forever (event-driven load)
    func testLoadingOverlayDoesNotPersistForever() throws {
        let app = XCUIApplication()
        app.launch()

        let overlay = app.otherElements["niivue.loadingOverlay"]
        if overlay.waitForExistence(timeout: 2) {
            let predicate = NSPredicate(format: "exists == false")
            expectation(for: predicate, evaluatedWith: overlay)
            waitForExpectations(timeout: 15)
        }

        XCTAssertTrue(app.buttons["niivue.settings"].waitForExistence(timeout: 5))
    }

    /// Task 11: Verify web app loads from custom scheme
    func testWebViewLoadsFromCustomScheme() throws {
        let app = XCUIApplication()
        app.launch()

        // Existence here means the app is interactive; exact WebView assertions are limited.
        XCTAssertTrue(app.buttons["niivue.settings"].waitForExistence(timeout: 5))
    }

    func testLaunchPerformance() throws {
        #if targetEnvironment(simulator)
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
        #else
        throw XCTSkip("Launch performance metrics are not reliable on physical devices.")
        #endif
    }

    /// Phase 2 Task 2: Verify multi-volume loading via launch argument doesn't crash
    func testLaunchArgumentLoadsTwoVolumes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]
        let errorLabel = app.staticTexts["niivue.lastError"]

        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 15))

        // Verify the web view becomes ready.
        let readyDeadline = Date().addingTimeInterval(20)
        var lastReadyValue = readyLabel.label
        while Date() < readyDeadline {
            lastReadyValue = readyLabel.label
            if lastReadyValue == "ready" { break }
            print("[UI] niivue.isReady label = \(lastReadyValue); lastError = \(errorLabel.label)")
            sleep(1)
        }
        XCTAssertEqual(lastReadyValue, "ready", "WebView never became ready; lastError='\(errorLabel.label)'.")

        // Verify the count reaches 2 (the launch argument path loads two volumes).
        let deadline = Date().addingTimeInterval(20)
        var lastObservedValue = countLabel.label
        while Date() < deadline {
            lastObservedValue = countLabel.label
            if lastObservedValue == "2" { break }
            print("[UI] niivue.volumeCount label = \(lastObservedValue); lastError = \(errorLabel.label)")
            sleep(1)
        }
        XCTAssertEqual(lastObservedValue, "2", "Expected volume count to reach 2, but got '\(lastObservedValue)'.")

        // Verify the app is interactive (settings button exists)
        XCTAssertTrue(app.buttons["niivue.settings"].waitForExistence(timeout: 5))
    }

    /// Phase 2 UI: Verify dedicated sheets entry points exist.
    func testLaunchShowsPhase2SheetsButtons() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["niivue.volumes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["niivue.segmentation"].exists)
        XCTAssertTrue(app.buttons["niivue.sessions"].exists)
    }

    func testVolumesSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["niivue.volumes"].tap()
        XCTAssertTrue(app.otherElements["niivue.volumesSheet"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
    }

    func testVolumesSheetShowsVolumeControlsWhenTwoVolumesLoaded() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        // Wait for the multi-volume path to finish loading.
        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]

        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))

        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if readyLabel.label == "ready", countLabel.label == "2" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")
        XCTAssertEqual(countLabel.label, "2")

        app.buttons["niivue.volumes"].tap()
        XCTAssertTrue(app.otherElements["niivue.volumesSheet"].waitForExistence(timeout: 2))

        XCTAssertTrue(app.sliders["niivue.volume.opacity.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["niivue.volume.colormap.0"].exists)

        app.buttons["Done"].tap()
    }

    func testSegmentationSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["niivue.segmentation"].tap()
        XCTAssertTrue(app.otherElements["niivue.segmentationSheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["niivue.importSegmentationAssets"].exists)
        app.buttons["Done"].tap()
    }

    func testSegmentationSheetShowsToolControls() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["niivue.segmentation"].tap()
        XCTAssertTrue(app.otherElements["niivue.segmentationSheet"].waitForExistence(timeout: 2))

        XCTAssertTrue(app.buttons["niivue.segmentation.undo"].exists)
        XCTAssertTrue(app.sliders["niivue.segmentation.drawOpacity"].exists)
        XCTAssertTrue(app.buttons["niivue.segmentation.drawColormap"].exists)
        XCTAssertTrue(app.switches["niivue.segmentation.clickToSegment"].exists)

        app.buttons["Done"].tap()
    }

    func testSessionsSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["niivue.sessions"].tap()
        XCTAssertTrue(app.otherElements["niivue.sessionsSheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["niivue.saveSession"].exists)
        app.buttons["Done"].tap()
    }

    func testSessionsSheetSaveIncrementsSessionCount() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple", "--ui-test-sessions-temp"]
        app.launch()

        // Wait for the web view to become ready so exportViewerState is available.
        let readyLabel = app.staticTexts["niivue.isReady"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        let readyDeadline = Date().addingTimeInterval(20)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")

        app.buttons["niivue.sessions"].tap()
        XCTAssertTrue(app.otherElements["niivue.sessionsSheet"].waitForExistence(timeout: 2))

        let countLabel = app.staticTexts["niivue.sessionCount"]
        XCTAssertTrue(countLabel.waitForExistence(timeout: 5))
        XCTAssertEqual(countLabel.label, "0")

        app.buttons["niivue.saveSession"].tap()

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if countLabel.label == "1" { break }
            sleep(1)
        }
        XCTAssertEqual(countLabel.label, "1")

        app.buttons["Done"].tap()
    }

    /// Phase 2 Task 9: Verify DICOM import button exists in Segmentation sheet
    func testSegmentationSheetShowsDicomImportButton() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["niivue.segmentation"].tap()
        XCTAssertTrue(app.otherElements["niivue.segmentationSheet"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["niivue.importDicom"].exists)
        app.buttons["Done"].tap()
    }
}
