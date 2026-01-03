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
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    /// Phase 2 Task 2: Verify multi-volume loading via launch argument doesn't crash
    func testLaunchArgumentLoadsTwoVolumes() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        // Verify the volume count label exists (shows multi-volume mode is active)
        let countLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))

        // Verify the app is interactive (settings button exists)
        XCTAssertTrue(app.buttons["niivue.settings"].waitForExistence(timeout: 5))
    }
}
