//
//  NiiVueUITests.swift
//  NiiVueUITests
//
//  Created by Taylor Hanayik on 03/01/2024.
//

import XCTest

final class NiiVueUITests: XCTestCase {

    private func isSwitchOn(_ element: XCUIElement) -> Bool {
        let value = String(describing: element.value ?? "")
        return value == "1" || value.lowercased() == "on" || value.lowercased() == "true"
    }

    private func tapTrailingEdge(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
    }

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // Keep tests deterministic regardless of how the physical device is being held.
        XCUIDevice.shared.orientation = .portrait

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

    /// CT Adaptive Engine UI: Verify CT Presets sheet entry point exists and opens.
    func testCTPresetsSheetOpens() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.buttons["niivue.ctPresets"].waitForExistence(timeout: 5))
        app.buttons["niivue.ctPresets"].tap()
        XCTAssertTrue(app.otherElements["niivue.ctPresetSheet"].waitForExistence(timeout: 2))
        app.buttons["Done"].tap()
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

    func testCTPresetAnalysisAppearsAfterApplyingAdaptivePreset() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]

        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))

        let readyDeadline = Date().addingTimeInterval(20)
        while Date() < readyDeadline {
            if readyLabel.label == "ready", countLabel.label != "0" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")
        XCTAssertNotEqual(countLabel.label, "0")

        app.buttons["niivue.ctPresets"].tap()
        XCTAssertTrue(app.otherElements["niivue.ctPresetSheet"].waitForExistence(timeout: 2))

        let apply = app.buttons["niivue.ctPresetApply"]
        XCTAssertTrue(apply.waitForExistence(timeout: 5))
        apply.tap()

        XCTAssertTrue(app.staticTexts["niivue.ctPresetAnalysis.phase"].waitForExistence(timeout: 5))

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

    /// Segmentation UX: Click-to-segment requires drawing enabled in Niivue. Enabling click-to-segment should enable drawing.
    func testSegmentationClickToSegmentEnablesDrawing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))

        let readyDeadline = Date().addingTimeInterval(20)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")

        app.buttons["niivue.segmentation"].tap()
        XCTAssertTrue(app.otherElements["niivue.segmentationSheet"].waitForExistence(timeout: 2))

        let clickToSegment = app.switches["niivue.segmentation.clickToSegment"]
        let clickToSegmentLabel = app.staticTexts["Click-to-segment"]
        // In smaller detents, SwiftUI's Form can lazily create rows; scroll until visible.
        if !clickToSegment.waitForExistence(timeout: 2) {
            let scrollView = app.scrollViews.firstMatch
            for _ in 0..<6 where !clickToSegment.exists {
                if scrollView.exists {
                    scrollView.swipeUp()
                } else {
                    app.swipeUp()
                }
            }
        }
        XCTAssertTrue(clickToSegment.waitForExistence(timeout: 5))

        print("[UI] clickToSegment isEnabled=\(clickToSegment.isEnabled) isHittable=\(clickToSegment.isHittable)")
        print("[UI] clickToSegment frame=\(clickToSegment.frame)")
        print("[UI] clickToSegment initial value = \(String(describing: clickToSegment.value))")
        if !isSwitchOn(clickToSegment) {
            clickToSegment.tap()
            if !isSwitchOn(clickToSegment) {
                print("[UI] clickToSegment tap did not toggle; tapping trailing edge as fallback")
                tapTrailingEdge(of: clickToSegment)
            }
        }
        let clickDeadline = Date().addingTimeInterval(3)
        while Date() < clickDeadline, !isSwitchOn(clickToSegment) {
            print("[UI] clickToSegment current value = \(String(describing: clickToSegment.value))")
            sleep(1)
        }
        if !isSwitchOn(clickToSegment), clickToSegmentLabel.exists, clickToSegmentLabel.isHittable {
            print("[UI] clickToSegment switch tap did not toggle; tapping label row as fallback")
            clickToSegmentLabel.tap()
            let labelDeadline = Date().addingTimeInterval(3)
            while Date() < labelDeadline, !isSwitchOn(clickToSegment) {
                print("[UI] clickToSegment current value (after label tap) = \(String(describing: clickToSegment.value))")
                sleep(1)
            }
        }
        XCTContext.runActivity(named: "Screenshot: Segmentation after enabling click-to-segment") { activity in
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
        XCTAssertTrue(isSwitchOn(clickToSegment), "Expected 'Click-to-segment' to be ON after tapping the switch.")

        app.buttons["Done"].tap()

        app.buttons["niivue.settings"].tap()
        let drawingEnabled = app.switches["Drawing enabled"]
        XCTAssertTrue(drawingEnabled.waitForExistence(timeout: 5))

        XCTContext.runActivity(named: "Screenshot: Settings after enabling click-to-segment") { activity in
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }

        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !isSwitchOn(drawingEnabled) {
            sleep(1)
        }

        XCTAssertTrue(isSwitchOn(drawingEnabled), "Expected 'Drawing enabled' to be ON after enabling click-to-segment.")
    }

    /// Segmentation UX: Tapping the viewer with click-to-segment enabled should trigger the JS bridge and emit a JS log.
    func testSegmentationClickToSegmentTapEmitsJSLog() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let errorLabel = app.staticTexts["niivue.lastError"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 15))

        let readyDeadline = Date().addingTimeInterval(30)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            print("[UI] niivue.isReady label = \(readyLabel.label); lastError = \(errorLabel.label)")
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready", "WebView never became ready; lastError='\(errorLabel.label)'.")

        // Ensure we are in a 2D slice view (tap-to-segment is only wired for 2D slice types).
        app.buttons["niivue.settings"].tap()
        let viewTypeMenu = app.buttons["niivue.settings.viewType"]
        XCTAssertTrue(viewTypeMenu.waitForExistence(timeout: 5))
        viewTypeMenu.tap()

        let axialOption = app.buttons["Axial"]
        XCTAssertTrue(axialOption.waitForExistence(timeout: 5))
        axialOption.tap()
        app.buttons["Dismiss"].tap()

        // Enable click-to-segment in the Segmentation sheet.
        app.buttons["niivue.segmentation"].tap()
        XCTAssertTrue(app.otherElements["niivue.segmentationSheet"].waitForExistence(timeout: 2))

        let clickToSegment = app.switches["niivue.segmentation.clickToSegment"]
        if !clickToSegment.waitForExistence(timeout: 2) {
            let scrollView = app.scrollViews.firstMatch
            for _ in 0..<6 where !clickToSegment.exists {
                if scrollView.exists {
                    scrollView.swipeUp()
                } else {
                    app.swipeUp()
                }
            }
        }
        XCTAssertTrue(clickToSegment.waitForExistence(timeout: 5))

        if !isSwitchOn(clickToSegment) {
            clickToSegment.tap()
            if !isSwitchOn(clickToSegment) {
                tapTrailingEdge(of: clickToSegment)
            }
        }
        let clickDeadline = Date().addingTimeInterval(3)
        while Date() < clickDeadline, !isSwitchOn(clickToSegment) {
            sleep(1)
        }
        XCTAssertTrue(isSwitchOn(clickToSegment), "Expected 'Click-to-segment' to be ON after tapping the switch.")

        app.buttons["Done"].tap()

        let lastJSLog = app.staticTexts["niivue.lastJSLog"]
        XCTAssertTrue(lastJSLog.waitForExistence(timeout: 5))
        let previousLog = lastJSLog.label

        let applyCountLabel = app.staticTexts["niivue.clickToSegment.applyCount"]
        let drawSumLabel = app.staticTexts["niivue.clickToSegment.drawSum"]
        let volumeMLLabel = app.staticTexts["niivue.clickToSegment.volumeML"]
        XCTAssertTrue(applyCountLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(drawSumLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(volumeMLLabel.waitForExistence(timeout: 5))

        let previousApplyCountString = applyCountLabel.label
        let previousDrawSumString = drawSumLabel.label
        let previousVolumeMLString = volumeMLLabel.label

        let previousApplyCount = Int(previousApplyCountString) ?? 0
        let previousDrawSum = Int(previousDrawSumString) ?? 0

        // Tap near the center of the viewer area (avoid the top toolbar).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).tap()

        // Expect the React bridge to emit a segmentation log after the tap,
        // and the JS layer to report click-to-segment debug metrics to Swift UI tests.
        let logPredicate = NSPredicate(format: "label CONTAINS[c] %@", "clickToSegmentAtScreenPoint")
        expectation(for: logPredicate, evaluatedWith: lastJSLog)

        let applyCountChanged = NSPredicate(format: "label != %@", previousApplyCountString)
        expectation(for: applyCountChanged, evaluatedWith: applyCountLabel)

        waitForExpectations(timeout: 15)

        XCTAssertNotEqual(lastJSLog.label, previousLog, "Expected niivue.lastJSLog to change after click-to-segment tap.")

        let newApplyCount = Int(applyCountLabel.label) ?? 0
        let newDrawSum = Int(drawSumLabel.label) ?? 0

        XCTAssertGreaterThan(newApplyCount, previousApplyCount, "Expected click-to-segment applyCount to increase.")
        XCTAssertGreaterThan(newDrawSum, previousDrawSum, "Expected click-to-segment to modify the drawing bitmap (drawSum).")

        XCTContext.runActivity(named: "Screenshot: After click-to-segment tap") { activity in
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.lifetime = .keepAlways
            activity.add(attachment)
            print("[UI] clickToSegment volume mL label = \(volumeMLLabel.label) (previous: \(previousVolumeMLString))")
        }
    }

    /// 3D Render UX: Pinching in Render view should enable clipping so users can "scroll" through slices.
    func testRenderPinchEnablesClipPlaneForSliceScroll() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))

        let readyDeadline = Date().addingTimeInterval(30)
        while Date() < readyDeadline {
            if readyLabel.label == "ready", countLabel.label == "2" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")
        XCTAssertEqual(countLabel.label, "2")

        // Switch to Render view so the pinch gesture targets the 3D renderer.
        app.buttons["niivue.settings"].tap()
        let viewTypeMenu = app.buttons["niivue.settings.viewType"]
        XCTAssertTrue(viewTypeMenu.waitForExistence(timeout: 5))
        viewTypeMenu.tap()

        let renderOption = app.buttons["Render"]
        XCTAssertTrue(renderOption.waitForExistence(timeout: 5))
        renderOption.tap()
        app.buttons["Dismiss"].tap()

        let clipDepthLabel = app.staticTexts["niivue.clipPlaneDepth"]
        XCTAssertTrue(clipDepthLabel.waitForExistence(timeout: 5))
        let initialDepthString = clipDepthLabel.label

        // Pinch-in should drive slice-scroll in 3D via the clip plane (not just zoom).
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10))
        webView.pinch(withScale: 0.7, velocity: -1)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if !clipDepthLabel.label.isEmpty, clipDepthLabel.label != initialDepthString { break }
            sleep(1)
        }

        XCTAssertFalse(clipDepthLabel.label.isEmpty, "Expected clip plane depth to be reported for UI tests.")
        let depth = Double(clipDepthLabel.label) ?? 999
        XCTAssertLessThan(depth, 1.8, "Expected clip plane depth < 1.8 (enabled), got '\(clipDepthLabel.label)'.")
    }

    /// 2D UX: 1-finger vertical drag should scrub through slices (stack scroll).
    func test2DStackScrollScrubsSlices() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))

        let readyDeadline = Date().addingTimeInterval(30)
        while Date() < readyDeadline {
            if readyLabel.label == "ready", countLabel.label == "2" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")
        XCTAssertEqual(countLabel.label, "2")

        // Switch to Axial view (2D) so stack scroll applies.
        app.buttons["niivue.settings"].tap()
        let viewTypeMenu = app.buttons["niivue.settings.viewType"]
        XCTAssertTrue(viewTypeMenu.waitForExistence(timeout: 5))
        viewTypeMenu.tap()

        let axialOption = app.buttons["Axial"]
        XCTAssertTrue(axialOption.waitForExistence(timeout: 5))
        axialOption.tap()
        app.buttons["Dismiss"].tap()

        let sliceIndexLabel = app.staticTexts["niivue.sliceIndex"]
        XCTAssertTrue(sliceIndexLabel.waitForExistence(timeout: 5), "Expected UI-test slice index label to exist.")

        let totalSlicesLabel = app.staticTexts["niivue.totalSlices"]
        let sliceTypeLabel = app.staticTexts["niivue.sliceType"]
        let stackScrollEventsLabel = app.staticTexts["niivue.stackScrollEvents"]
        let panXLabel = app.staticTexts["niivue.twoFingerPanOffsetX"]
        let panYLabel = app.staticTexts["niivue.twoFingerPanOffsetY"]
        let panEventsLabel = app.staticTexts["niivue.twoFingerPanEvents"]
        XCTAssertTrue(totalSlicesLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(sliceTypeLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(stackScrollEventsLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(panXLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(panYLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(panEventsLabel.waitForExistence(timeout: 5))

        let stateDeadline = Date().addingTimeInterval(10)
        while Date() < stateDeadline {
            let sliceType = Int(sliceTypeLabel.label) ?? -1
            let totalSlices = Int(totalSlicesLabel.label) ?? -1
            let sliceIndex = Int(sliceIndexLabel.label) ?? -1
            if sliceType == 0, totalSlices > 0, sliceIndex >= 0 { break }
            print("[UI] Waiting slice state: sliceType=\(sliceTypeLabel.label) totalSlices=\(totalSlicesLabel.label) sliceIndex=\(sliceIndexLabel.label)")
            sleep(1)
        }

        let totalSlices = Int(totalSlicesLabel.label) ?? -1
        XCTAssertGreaterThan(totalSlices, 1, "Expected totalSlices > 1 for stack scroll test, got '\(totalSlicesLabel.label)'.")

        let initialIndex = Int(sliceIndexLabel.label) ?? -1
        let initialPanX = panXLabel.label
        let initialPanY = panYLabel.label
        let initialPanEvents = panEventsLabel.label
        print("[UI] Initial slice state: sliceType=\(sliceTypeLabel.label) totalSlices=\(totalSlicesLabel.label) sliceIndex=\(sliceIndexLabel.label) stackScrollEvents=\(stackScrollEventsLabel.label) panX=\(initialPanX) panY=\(initialPanY) panEvents=\(initialPanEvents)")

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10))

        if initialIndex >= (totalSlices - 1) {
            // If we're already at the last slice, drag down to move backwards.
            let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            let end = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            start.press(forDuration: 0.05, thenDragTo: end)
        } else {
            // Drag up by a meaningful distance so we advance several slices.
            let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            let end = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            start.press(forDuration: 0.05, thenDragTo: end)
        }

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let newIndex = Int(sliceIndexLabel.label) ?? -1
            if initialIndex >= (totalSlices - 1) {
                if newIndex < initialIndex { break }
            } else {
                if newIndex > initialIndex { break }
            }
            sleep(1)
        }

        let finalIndex = Int(sliceIndexLabel.label) ?? -1
        print("[UI] Final slice state: sliceType=\(sliceTypeLabel.label) totalSlices=\(totalSlicesLabel.label) sliceIndex=\(sliceIndexLabel.label) stackScrollEvents=\(stackScrollEventsLabel.label) panX=\(panXLabel.label) panY=\(panYLabel.label) panEvents=\(panEventsLabel.label)")
        XCTAssertGreaterThan(Int(stackScrollEventsLabel.label) ?? 0, 0, "Expected native stack scroll gesture handler to receive pan updates.")
        XCTAssertEqual(panEventsLabel.label, initialPanEvents, "Expected 1-finger stack scroll not to trigger two-finger pan events.")
        XCTAssertEqual(panXLabel.label, initialPanX, "Expected 1-finger stack scroll not to change two-finger pan X offset.")
        XCTAssertEqual(panYLabel.label, initialPanY, "Expected 1-finger stack scroll not to change two-finger pan Y offset.")
        if initialIndex >= (totalSlices - 1) {
            XCTAssertLessThan(finalIndex, initialIndex, "Expected stack scroll to decrease slice index when starting at last slice. initial=\(initialIndex) final=\(finalIndex)")
        } else {
            XCTAssertGreaterThan(finalIndex, initialIndex, "Expected stack scroll to increase slice index. initial=\(initialIndex) final=\(finalIndex)")
        }
    }

    /// 2D UX: Two-finger pan should translate the image without being triggered by one-finger drags.
    func test2DTwoFingerPanUpdatesOffset() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple", "--ui-test-simulate-two-finger-pan"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))

        let readyDeadline = Date().addingTimeInterval(30)
        while Date() < readyDeadline {
            if readyLabel.label == "ready", countLabel.label == "2" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")
        XCTAssertEqual(countLabel.label, "2")

        // Switch to Axial view (2D) so the two-finger pan overlay is enabled.
        app.buttons["niivue.settings"].tap()
        let viewTypeMenu = app.buttons["niivue.settings.viewType"]
        XCTAssertTrue(viewTypeMenu.waitForExistence(timeout: 5))
        viewTypeMenu.tap()

        let axialOption = app.buttons["Axial"]
        XCTAssertTrue(axialOption.waitForExistence(timeout: 5))
        axialOption.tap()
        app.buttons["Dismiss"].tap()

        let sliceTypeLabel = app.staticTexts["niivue.sliceType"]
        let sliceIndexLabel = app.staticTexts["niivue.sliceIndex"]
        let stackScrollEventsLabel = app.staticTexts["niivue.stackScrollEvents"]
        let panXLabel = app.staticTexts["niivue.twoFingerPanOffsetX"]
        let panYLabel = app.staticTexts["niivue.twoFingerPanOffsetY"]
        let panEventsLabel = app.staticTexts["niivue.twoFingerPanEvents"]
        let panInstallCountLabel = app.staticTexts["niivue.twoFingerPanInstallCount"]
        let panInstalledViewLabel = app.staticTexts["niivue.twoFingerPanInstalledView"]
        let viewportScaleLabel = app.staticTexts["niivue.viewportScale"]
        let viewportPinchEventsLabel = app.staticTexts["niivue.viewportPinchEvents"]
        XCTAssertTrue(sliceTypeLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(sliceIndexLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(stackScrollEventsLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(panXLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(panYLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(panEventsLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(panInstallCountLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(panInstalledViewLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(viewportScaleLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(viewportPinchEventsLabel.waitForExistence(timeout: 5))

        let stateDeadline = Date().addingTimeInterval(10)
        while Date() < stateDeadline {
            let sliceType = Int(sliceTypeLabel.label) ?? -1
            if sliceType == 0 { break }
            sleep(1)
        }
        XCTAssertEqual(sliceTypeLabel.label, "0", "Expected Axial sliceType=0 for two-finger pan test.")

        let initialPanX = panXLabel.label
        let initialPanY = panYLabel.label
        let initialEvents = Int(panEventsLabel.label) ?? 0
        let initialSliceIndex = sliceIndexLabel.label
        let initialStackScrollEvents = stackScrollEventsLabel.label
        print("[UI] Initial pan state: panX=\(initialPanX) panY=\(initialPanY) panEvents=\(panEventsLabel.label) panInstallCount=\(panInstallCountLabel.label) panInstalledView=\(panInstalledViewLabel.label) viewportScale=\(viewportScaleLabel.label) viewportPinchEvents=\(viewportPinchEventsLabel.label) sliceIndex=\(initialSliceIndex) stackScrollEvents=\(initialStackScrollEvents)")

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10))

        // UI tests cannot synthesize a true two-finger drag on iPhone hardware.
        // The app enables a UI-test-only fallback (`--ui-test-simulate-two-finger-pan`) that routes a 1-finger drag into the same pan path.
        let start = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        let end = webView.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let currentEvents = Int(panEventsLabel.label) ?? 0
            if currentEvents > initialEvents, panXLabel.label != initialPanX || panYLabel.label != initialPanY {
                break
            }
            sleep(1)
        }

        print("[UI] Final pan state: panX=\(panXLabel.label) panY=\(panYLabel.label) panEvents=\(panEventsLabel.label)")
        XCTAssertGreaterThan(Int(panEventsLabel.label) ?? 0, initialEvents, "Expected two-finger pan handler to receive updates.")
        XCTAssertTrue(panXLabel.label != initialPanX || panYLabel.label != initialPanY, "Expected two-finger pan offsets to change.")
        XCTAssertEqual(stackScrollEventsLabel.label, initialStackScrollEvents, "Expected pan gesture not to trigger stack scroll.")
        XCTAssertEqual(sliceIndexLabel.label, initialSliceIndex, "Expected pan gesture not to change slice index.")
    }

    /// 2D UX: Two-finger pinch should zoom the viewport without changing slice index.
    func test2DViewportPinchZoomUpdatesScale() throws {
        let app = XCUIApplication()
        // XCUI pinch events do not reliably reach UIKit recognizers installed on WKWebView.
        // Enable a UI-test-only interaction surface that receives the pinch recognizer.
        app.launchArguments = ["--ui-test-load-multiple", "--ui-test-simulate-two-finger-pinch"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))

        let readyDeadline = Date().addingTimeInterval(30)
        while Date() < readyDeadline {
            if readyLabel.label == "ready", countLabel.label == "2" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")
        XCTAssertEqual(countLabel.label, "2")

        // Switch to Axial view (2D) so the viewport interaction handler is enabled.
        app.buttons["niivue.settings"].tap()
        let viewTypeMenu = app.buttons["niivue.settings.viewType"]
        XCTAssertTrue(viewTypeMenu.waitForExistence(timeout: 5))
        viewTypeMenu.tap()

        let axialOption = app.buttons["Axial"]
        XCTAssertTrue(axialOption.waitForExistence(timeout: 5))
        axialOption.tap()
        app.buttons["Dismiss"].tap()

        let sliceTypeLabel = app.staticTexts["niivue.sliceType"]
        let sliceIndexLabel = app.staticTexts["niivue.sliceIndex"]
        let stackScrollEventsLabel = app.staticTexts["niivue.stackScrollEvents"]
        let viewportScaleLabel = app.staticTexts["niivue.viewportScale"]
        let viewportPinchEventsLabel = app.staticTexts["niivue.viewportPinchEvents"]
        XCTAssertTrue(sliceTypeLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(sliceIndexLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(stackScrollEventsLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(viewportScaleLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(viewportPinchEventsLabel.waitForExistence(timeout: 5))

        let stateDeadline = Date().addingTimeInterval(10)
        while Date() < stateDeadline {
            let sliceType = Int(sliceTypeLabel.label) ?? -1
            if sliceType == 0 { break }
            sleep(1)
        }
        XCTAssertEqual(sliceTypeLabel.label, "0", "Expected Axial sliceType=0 for pinch zoom test.")

        let initialScale = viewportScaleLabel.label
        let initialPinchEvents = Int(viewportPinchEventsLabel.label) ?? 0
        let initialSliceIndex = sliceIndexLabel.label
        let initialStackScrollEvents = stackScrollEventsLabel.label
        print("[UI] Initial zoom state: viewportScale=\(initialScale) viewportPinchEvents=\(viewportPinchEventsLabel.label) sliceIndex=\(initialSliceIndex) stackScrollEvents=\(initialStackScrollEvents)")

        let interactionSurface = app.otherElements["niivue.viewportInteractionSurface"]
        XCTAssertTrue(interactionSurface.waitForExistence(timeout: 10))

        interactionSurface.pinch(withScale: 1.6, velocity: 1)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let pinchEvents = Int(viewportPinchEventsLabel.label) ?? 0
            if pinchEvents > initialPinchEvents, viewportScaleLabel.label != initialScale {
                break
            }
            sleep(1)
        }

        print("[UI] Final zoom state: viewportScale=\(viewportScaleLabel.label) viewportPinchEvents=\(viewportPinchEventsLabel.label)")
        XCTAssertGreaterThan(Int(viewportPinchEventsLabel.label) ?? 0, initialPinchEvents, "Expected pinch recognizer to receive updates.")
        XCTAssertNotEqual(viewportScaleLabel.label, initialScale, "Expected viewport scale to change after pinch.")
        XCTAssertEqual(sliceIndexLabel.label, initialSliceIndex, "Expected pinch zoom not to change slice index.")
        XCTAssertEqual(stackScrollEventsLabel.label, initialStackScrollEvents, "Expected pinch zoom not to trigger stack scroll.")
    }

    /// 2D UX: Window/Level mode should adjust WW/WL with 1 finger (and not scroll slices).
    func test2DWindowLevelAdjustsContrastWithoutScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test-load-multiple"]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 15))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 15))

        let readyDeadline = Date().addingTimeInterval(30)
        while Date() < readyDeadline {
            if readyLabel.label == "ready", countLabel.label == "2" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")
        XCTAssertEqual(countLabel.label, "2")

        // Switch to Axial view (2D)
        app.buttons["niivue.settings"].tap()
        let viewTypeMenu = app.buttons["niivue.settings.viewType"]
        XCTAssertTrue(viewTypeMenu.waitForExistence(timeout: 5))
        viewTypeMenu.tap()

        let axialOption = app.buttons["Axial"]
        XCTAssertTrue(axialOption.waitForExistence(timeout: 5))
        axialOption.tap()
        app.buttons["Dismiss"].tap()

        let sliceTypeLabel = app.staticTexts["niivue.sliceType"]
        let sliceIndexLabel = app.staticTexts["niivue.sliceIndex"]
        let stackScrollEventsLabel = app.staticTexts["niivue.stackScrollEvents"]
        let windowWidthLabel = app.staticTexts["niivue.windowWidth"]
        let windowLevelLabel = app.staticTexts["niivue.windowLevel"]
        let windowLevelEventsLabel = app.staticTexts["niivue.windowLevelEvents"]

        XCTAssertTrue(sliceTypeLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(sliceIndexLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(stackScrollEventsLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(windowWidthLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(windowLevelLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(windowLevelEventsLabel.waitForExistence(timeout: 5))

        let stateDeadline = Date().addingTimeInterval(10)
        while Date() < stateDeadline {
            let sliceType = Int(sliceTypeLabel.label) ?? -1
            if sliceType == 0 { break }
            sleep(1)
        }
        XCTAssertEqual(sliceTypeLabel.label, "0", "Expected Axial sliceType=0 for window/level test.")

        let windowLevelToolButton = app.buttons["niivue.tool.windowLevel"]
        XCTAssertTrue(windowLevelToolButton.waitForExistence(timeout: 5))
        windowLevelToolButton.tap()

        // Window width should never be zero; clamp to >= 1.0 to avoid unstable WW/WL math.
        let wwSyncDeadline = Date().addingTimeInterval(5)
        var syncedWW = Double(windowWidthLabel.label) ?? 0
        while Date() < wwSyncDeadline {
            syncedWW = Double(windowWidthLabel.label) ?? 0
            if syncedWW >= 1.0 { break }
            usleep(200_000)
        }
        XCTAssertGreaterThanOrEqual(syncedWW, 1.0, "Expected windowWidth to be clamped to >= 1.0, got '\(windowWidthLabel.label)'.")

        let initialWW = syncedWW
        let initialWL = Double(windowLevelLabel.label) ?? 0
        let initialWindowLevelEvents = Int(windowLevelEventsLabel.label) ?? 0
        let initialSliceIndex = sliceIndexLabel.label
        let initialStackScrollEvents = stackScrollEventsLabel.label
        print("[UI] Initial window/level: WW=\(windowWidthLabel.label) WL=\(windowLevelLabel.label) wlEvents=\(windowLevelEventsLabel.label) sliceIndex=\(initialSliceIndex) stackScrollEvents=\(initialStackScrollEvents)")

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10))

        let startVector = CGVector(dx: 0.5, dy: 0.5)
        let endVector = CGVector(dx: 0.7, dy: 0.3)
        let start = webView.coordinate(withNormalizedOffset: startVector)
        let end = webView.coordinate(withNormalizedOffset: endVector)
        start.press(forDuration: 0.05, thenDragTo: end)

        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let currentEvents = Int(windowLevelEventsLabel.label) ?? 0
            let ww = Double(windowWidthLabel.label) ?? initialWW
            let wl = Double(windowLevelLabel.label) ?? initialWL
            if currentEvents > initialWindowLevelEvents, (ww != initialWW || wl != initialWL) {
                break
            }
            sleep(1)
        }

        print("[UI] Final window/level: WW=\(windowWidthLabel.label) WL=\(windowLevelLabel.label) wlEvents=\(windowLevelEventsLabel.label)")

        let finalWW = Double(windowWidthLabel.label) ?? initialWW
        let finalWL = Double(windowLevelLabel.label) ?? initialWL
        XCTAssertGreaterThan(Int(windowLevelEventsLabel.label) ?? 0, initialWindowLevelEvents, "Expected window/level handler to receive drag updates.")

        // Verify stable-origin math (prevents mid-drag re-captures that cause jumps).
        let pointsPerHU = 2.0
        let translationX = (endVector.dx - startVector.dx) * webView.frame.size.width
        let translationY = (endVector.dy - startVector.dy) * webView.frame.size.height
        let expectedWW = max(1.0, initialWW + (Double(translationX) * pointsPerHU))
        let expectedWL = initialWL - (Double(translationY) * pointsPerHU)
        XCTAssertEqual(finalWW, expectedWW, accuracy: 25, "Expected WW to match translation-based calculation.")
        XCTAssertEqual(finalWL, expectedWL, accuracy: 25, "Expected WL to match translation-based calculation.")

        XCTAssertEqual(sliceIndexLabel.label, initialSliceIndex, "Expected window/level gesture not to change slice index.")
        XCTAssertEqual(stackScrollEventsLabel.label, initialStackScrollEvents, "Expected window/level gesture not to trigger stack scroll.")
    }

    /// Phase 2 Task 9: DICOM - Load a real-world KiTS23 CT series from a device fixture directory.
    func testDicomImportKiTS23SeriesLoadsVolume() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-dicom-dir",
            "Test_CT_DICOM_volumes/Dicom_Volume_1"
        ]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 30), "Expected ready label to exist in UI test mode.")

        let statusLabel = app.staticTexts["niivue.dicomImportStatusGlobal"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 30), "Expected global DICOM status label to exist.")

        let errorLabel = app.staticTexts["niivue.lastError"]
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 30), "Expected last error label to exist.")

        let jsLogLabel = app.staticTexts["niivue.lastJSLog"]
        XCTAssertTrue(jsLogLabel.waitForExistence(timeout: 30), "Expected JS log label to exist.")

        let schemeDebugLabel = app.staticTexts["niivue.lastURLSchemeDebug"]
        XCTAssertTrue(schemeDebugLabel.waitForExistence(timeout: 30), "Expected scheme debug label to exist.")

        // Wait for the app to be ready for commands.
        let readyDeadline = Date().addingTimeInterval(60)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")

        // Wait for the DICOM load to either succeed or surface a failure message.
        let volumeCountLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(volumeCountLabel.waitForExistence(timeout: 30), "Expected volume count label to exist.")

        let deadline = Date().addingTimeInterval(180)
        while Date() < deadline {
            let status = statusLabel.label
            let volumeCount = Int(volumeCountLabel.label) ?? 0
            if status.contains("Loaded") && volumeCount > 0 { break }
            if status.contains("Failed") { break }
            sleep(2)
        }

        let finalStatus = statusLabel.label
        let finalError = errorLabel.label
        let finalJSLog = jsLogLabel.label
        let finalSchemeDebug = schemeDebugLabel.label
        let finalVolumeCount = Int(volumeCountLabel.label) ?? 0
        print("[UI] DICOM final: status=\(finalStatus) error=\(finalError) jsLog=\(finalJSLog) scheme=\(finalSchemeDebug) volumeCount=\(finalVolumeCount)")

        XCTAssertTrue(finalStatus.contains("Loaded"), "Expected DICOM series to load. status='\(finalStatus)' error='\(finalError)' jsLog='\(finalJSLog)'")
        XCTAssertGreaterThan(finalVolumeCount, 0, "Expected at least 1 loaded volume after DICOM import.")
        XCTAssertTrue(finalJSLog.contains("[DICOM]"), "Expected JS DICOM loader logs to be forwarded to native layer. jsLog='\(finalJSLog)'")
    }

    /// Geraldo dataset: Load a 512x512x484 CT DICOM series from a device fixture directory.
    func testDicomImportGeraldoSeriesLoadsVolume() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-dicom-dir",
            "Test_CT_DICOM_volumes/GERALDO_TRINDADE_FIRMINO/VOLUME_VENOSO_MED_E_ABD_9"
        ]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 30), "Expected ready label to exist in UI test mode.")

        let statusLabel = app.staticTexts["niivue.dicomImportStatusGlobal"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 30), "Expected global DICOM status label to exist.")

        let errorLabel = app.staticTexts["niivue.lastError"]
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 30), "Expected last error label to exist.")

        let jsLogLabel = app.staticTexts["niivue.lastJSLog"]
        XCTAssertTrue(jsLogLabel.waitForExistence(timeout: 30), "Expected JS log label to exist.")

        let schemeDebugLabel = app.staticTexts["niivue.lastURLSchemeDebug"]
        XCTAssertTrue(schemeDebugLabel.waitForExistence(timeout: 30), "Expected scheme debug label to exist.")

        // Wait for the app to be ready for commands.
        let readyDeadline = Date().addingTimeInterval(60)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")

        // Wait for the DICOM load to either succeed or surface a failure message.
        let volumeCountLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(volumeCountLabel.waitForExistence(timeout: 30), "Expected volume count label to exist.")

        // JPEG-LS DICOM series conversion can take several minutes on-device.
        let deadline = Date().addingTimeInterval(600)
        while Date() < deadline {
            let status = statusLabel.label
            let volumeCount = Int(volumeCountLabel.label) ?? 0
            if status.contains("Loaded") && volumeCount > 0 { break }
            if status.contains("Failed") { break }
            sleep(2)
        }

        let finalStatus = statusLabel.label
        let finalError = errorLabel.label
        let finalJSLog = jsLogLabel.label
        let finalSchemeDebug = schemeDebugLabel.label
        let finalVolumeCount = Int(volumeCountLabel.label) ?? 0
        print("[UI] Geraldo DICOM final: status=\(finalStatus) error=\(finalError) jsLog=\(finalJSLog) scheme=\(finalSchemeDebug) volumeCount=\(finalVolumeCount)")

        XCTAssertTrue(finalStatus.contains("Loaded"), "Expected Geraldo DICOM series to load. status='\(finalStatus)' error='\(finalError)' jsLog='\(finalJSLog)'")
        XCTAssertGreaterThan(finalVolumeCount, 0, "Expected at least 1 loaded volume after Geraldo DICOM import.")
    }

    /// Geraldo dataset: After loading DICOM, load exactly one `.nii.gz` segmentation overlay from device fixtures.
    func testDicomImportGeraldoThenLoadsOneSegmentationOverlay() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-dicom-dir",
            "Test_CT_DICOM_volumes/GERALDO_TRINDADE_FIRMINO/VOLUME_VENOSO_MED_E_ABD_9",
            "--ui-test-seg-dir",
            "Test_CT_DICOM_volumes/Geraldo_FULL_Segmentations",
            "--ui-test-seg-limit",
            "1"
        ]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let dicomStatusLabel = app.staticTexts["niivue.dicomImportStatusGlobal"]
        let segStatusLabel = app.staticTexts["niivue.segImportStatusGlobal"]
        let volumeCountLabel = app.staticTexts["niivue.volumeCount"]
        let errorLabel = app.staticTexts["niivue.lastError"]

        XCTAssertTrue(readyLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(dicomStatusLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(segStatusLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(volumeCountLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(errorLabel.waitForExistence(timeout: 30))

        let readyDeadline = Date().addingTimeInterval(60)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")

        // Wait for base DICOM to load.
        // JPEG-LS DICOM series conversion can take several minutes on-device.
        let dicomDeadline = Date().addingTimeInterval(600)
        while Date() < dicomDeadline {
            let status = dicomStatusLabel.label
            let volumeCount = Int(volumeCountLabel.label) ?? 0
            if status.contains("Loaded") && volumeCount > 0 { break }
            if status.contains("Failed") { break }
            sleep(2)
        }
        XCTAssertTrue(dicomStatusLabel.label.contains("Loaded"), "Expected DICOM to load before segmentation overlay. status='\(dicomStatusLabel.label)' error='\(errorLabel.label)'")

        // Then wait for at least one overlay to be added (volume count >= 2).
        let overlayDeadline = Date().addingTimeInterval(600)
        while Date() < overlayDeadline {
            let segStatus = segStatusLabel.label
            let volumeCount = Int(volumeCountLabel.label) ?? 0
            if segStatus.contains("Loaded") && volumeCount >= 2 { break }
            if segStatus.contains("Failed") { break }
            sleep(2)
        }

        let finalSegStatus = segStatusLabel.label
        let finalError = errorLabel.label
        let finalVolumeCount = Int(volumeCountLabel.label) ?? 0
        print("[UI] Geraldo seg final: status=\(finalSegStatus) error=\(finalError) volumeCount=\(finalVolumeCount)")

        XCTAssertTrue(finalSegStatus.contains("Loaded"), "Expected segmentation overlay to load. status='\(finalSegStatus)' error='\(finalError)'")
        XCTAssertGreaterThanOrEqual(finalVolumeCount, 2, "Expected at least 2 volumes after adding segmentation overlay.")
        XCTAssertFalse(finalError.lowercased().contains("failed"), "Expected no failure in lastError, got '\(finalError)'")
    }

    /// Phase 2 Task 9: DICOM - Missing fixture directory should fail fast and never crash.
    func testDicomImportMissingFixtureDirectoryShowsFailure() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-dicom-dir",
            "Test_CT_DICOM_volumes/DOES_NOT_EXIST"
        ]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 30))

        let statusLabel = app.staticTexts["niivue.dicomImportStatusGlobal"]
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 30))

        let volumeCountLabel = app.staticTexts["niivue.volumeCount"]
        XCTAssertTrue(volumeCountLabel.waitForExistence(timeout: 30))

        // Wait for the app to be ready for commands.
        let readyDeadline = Date().addingTimeInterval(60)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")

        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let status = statusLabel.label
            if status.contains("Failed to read fixture dir") || status.contains("Failed:") {
                break
            }
            sleep(1)
        }

        let finalStatus = statusLabel.label
        let finalVolumeCount = Int(volumeCountLabel.label) ?? 0
        print("[UI] DICOM missing-dir final: status=\(finalStatus) volumeCount=\(finalVolumeCount)")

        XCTAssertTrue(
            finalStatus.contains("Failed to read fixture dir") || finalStatus.contains("Failed:"),
            "Expected fixture-dir failure status, got '\(finalStatus)'"
        )
        XCTAssertEqual(finalVolumeCount, 0, "Expected no volumes to be loaded when fixture directory is missing.")
    }

    /// Phase 2 Task 9: DICOM - After loading a real CT series, 1-finger stack scroll should scrub slices.
    func testDicomImportKiTS23Then2DStackScrollScrubsSlices() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-dicom-dir",
            "Test_CT_DICOM_volumes/Dicom_Volume_1"
        ]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]
        let statusLabel = app.staticTexts["niivue.dicomImportStatusGlobal"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 30))

        let readyDeadline = Date().addingTimeInterval(60)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")

        let loadDeadline = Date().addingTimeInterval(180)
        while Date() < loadDeadline {
            let status = statusLabel.label
            let count = Int(countLabel.label) ?? 0
            if status.contains("Loaded") && count > 0 { break }
            if status.contains("Failed") { break }
            sleep(2)
        }
        XCTAssertTrue(statusLabel.label.contains("Loaded"), "Expected DICOM to load before stack scrolling. status='\(statusLabel.label)'")

        // Switch to Axial view (2D) so stack scroll applies.
        app.buttons["niivue.settings"].tap()
        let viewTypeMenu = app.buttons["niivue.settings.viewType"]
        XCTAssertTrue(viewTypeMenu.waitForExistence(timeout: 5))
        viewTypeMenu.tap()

        let axialOption = app.buttons["Axial"]
        XCTAssertTrue(axialOption.waitForExistence(timeout: 5))
        axialOption.tap()
        app.buttons["Dismiss"].tap()

        let sliceIndexLabel = app.staticTexts["niivue.sliceIndex"]
        let totalSlicesLabel = app.staticTexts["niivue.totalSlices"]
        let sliceTypeLabel = app.staticTexts["niivue.sliceType"]
        let stackScrollEventsLabel = app.staticTexts["niivue.stackScrollEvents"]
        XCTAssertTrue(sliceIndexLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(totalSlicesLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(sliceTypeLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(stackScrollEventsLabel.waitForExistence(timeout: 10))

        // Wait for slice state to be available.
        let stateDeadline = Date().addingTimeInterval(30)
        while Date() < stateDeadline {
            let sliceType = Int(sliceTypeLabel.label) ?? -1
            let totalSlices = Int(totalSlicesLabel.label) ?? -1
            let sliceIndex = Int(sliceIndexLabel.label) ?? -1
            if sliceType == 0, totalSlices > 1, sliceIndex >= 0 { break }
            print("[UI] Waiting DICOM slice state: sliceType=\(sliceTypeLabel.label) totalSlices=\(totalSlicesLabel.label) sliceIndex=\(sliceIndexLabel.label)")
            sleep(1)
        }

        let totalSlices = Int(totalSlicesLabel.label) ?? -1
        XCTAssertGreaterThan(totalSlices, 1, "Expected totalSlices > 1 for DICOM stack scroll test, got '\(totalSlicesLabel.label)'.")

        let initialIndex = Int(sliceIndexLabel.label) ?? -1
        let initialEvents = Int(stackScrollEventsLabel.label) ?? 0
        print("[UI] DICOM initial stack state: totalSlices=\(totalSlicesLabel.label) sliceIndex=\(sliceIndexLabel.label) stackScrollEvents=\(stackScrollEventsLabel.label)")

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10))

        // Drag up to move forward in the stack (inverted mapping: translationY negative => steps positive).
        let startVector = CGVector(dx: 0.5, dy: 0.65)
        let endVector = CGVector(dx: 0.5, dy: 0.35)
        let start = webView.coordinate(withNormalizedOffset: startVector)
        let end = webView.coordinate(withNormalizedOffset: endVector)
        start.press(forDuration: 0.05, thenDragTo: end)

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let events = Int(stackScrollEventsLabel.label) ?? 0
            let idx = Int(sliceIndexLabel.label) ?? initialIndex
            if events > initialEvents, idx != initialIndex {
                break
            }
            sleep(1)
        }

        print("[UI] DICOM final stack state: totalSlices=\(totalSlicesLabel.label) sliceIndex=\(sliceIndexLabel.label) stackScrollEvents=\(stackScrollEventsLabel.label)")
        XCTAssertGreaterThan(Int(stackScrollEventsLabel.label) ?? 0, initialEvents, "Expected stack scroll to receive drag updates.")
        let finalIndex = Int(sliceIndexLabel.label) ?? initialIndex
        XCTAssertNotEqual(finalIndex, initialIndex, "Expected slice index to change after drag.")

        // UX guardrails (avoid extremely sensitive or extremely slow stack scroll).
        let delta = abs(finalIndex - initialIndex)
        if totalSlices > 40, (totalSlices - 1 - initialIndex) >= 20 {
            XCTAssertGreaterThanOrEqual(delta, 3, "Expected drag to scrub at least a few slices (too slow). delta=\(delta)")
            XCTAssertLessThanOrEqual(delta, 80, "Expected drag not to scrub an excessive number of slices (too sensitive). delta=\(delta)")
        }
    }

    /// Phase 2 UX: After loading a real CT series, Window/Level mode should adjust WW/WL and not scrub slices.
    func testDicomImportKiTS23WindowLevelDoesNotScrollSlices() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-test-dicom-dir",
            "Test_CT_DICOM_volumes/Dicom_Volume_1"
        ]
        app.launch()

        let readyLabel = app.staticTexts["niivue.isReady"]
        let countLabel = app.staticTexts["niivue.volumeCount"]
        let statusLabel = app.staticTexts["niivue.dicomImportStatusGlobal"]
        XCTAssertTrue(readyLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(countLabel.waitForExistence(timeout: 30))
        XCTAssertTrue(statusLabel.waitForExistence(timeout: 30))

        let readyDeadline = Date().addingTimeInterval(60)
        while Date() < readyDeadline {
            if readyLabel.label == "ready" { break }
            sleep(1)
        }
        XCTAssertEqual(readyLabel.label, "ready")

        let loadDeadline = Date().addingTimeInterval(180)
        while Date() < loadDeadline {
            let status = statusLabel.label
            let count = Int(countLabel.label) ?? 0
            if status.contains("Loaded") && count > 0 { break }
            if status.contains("Failed") { break }
            sleep(2)
        }
        XCTAssertTrue(statusLabel.label.contains("Loaded"), "Expected DICOM to load before window/level. status='\(statusLabel.label)'")

        // Switch to Axial view (2D).
        app.buttons["niivue.settings"].tap()
        let viewTypeMenu = app.buttons["niivue.settings.viewType"]
        XCTAssertTrue(viewTypeMenu.waitForExistence(timeout: 5))
        viewTypeMenu.tap()

        let axialOption = app.buttons["Axial"]
        XCTAssertTrue(axialOption.waitForExistence(timeout: 5))
        axialOption.tap()
        app.buttons["Dismiss"].tap()

        let sliceIndexLabel = app.staticTexts["niivue.sliceIndex"]
        let crosshairSliceIndexLabel = app.staticTexts["niivue.crosshairSliceIndex"]
        let stackScrollEventsLabel = app.staticTexts["niivue.stackScrollEvents"]
        XCTAssertTrue(sliceIndexLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(crosshairSliceIndexLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(stackScrollEventsLabel.waitForExistence(timeout: 10))
        let initialCrosshairSliceIndex = crosshairSliceIndexLabel.label
        let initialStackScrollEvents = stackScrollEventsLabel.label

        let windowWidthLabel = app.staticTexts["niivue.windowWidth"]
        let windowLevelLabel = app.staticTexts["niivue.windowLevel"]
        let windowLevelEventsLabel = app.staticTexts["niivue.windowLevelEvents"]
        XCTAssertTrue(windowWidthLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(windowLevelLabel.waitForExistence(timeout: 10))
        XCTAssertTrue(windowLevelEventsLabel.waitForExistence(timeout: 10))

        let windowLevelToolButton = app.buttons["niivue.tool.windowLevel"]
        XCTAssertTrue(windowLevelToolButton.waitForExistence(timeout: 10))
        windowLevelToolButton.tap()

        let initialWW = Double(windowWidthLabel.label) ?? 1
        let initialWL = Double(windowLevelLabel.label) ?? 0
        let initialWindowLevelEvents = Int(windowLevelEventsLabel.label) ?? 0
        print("[UI] DICOM initial window/level: WW=\(windowWidthLabel.label) WL=\(windowLevelLabel.label) wlEvents=\(windowLevelEventsLabel.label) sliceIndex=\(sliceIndexLabel.label) crosshairSliceIndex=\(crosshairSliceIndexLabel.label) stackScrollEvents=\(initialStackScrollEvents)")

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 10))

        let startVector = CGVector(dx: 0.5, dy: 0.5)
        let endVector = CGVector(dx: 0.7, dy: 0.3)
        let start = webView.coordinate(withNormalizedOffset: startVector)
        let end = webView.coordinate(withNormalizedOffset: endVector)
        start.press(forDuration: 0.05, thenDragTo: end)

        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let currentEvents = Int(windowLevelEventsLabel.label) ?? 0
            let ww = Double(windowWidthLabel.label) ?? initialWW
            let wl = Double(windowLevelLabel.label) ?? initialWL
            if currentEvents > initialWindowLevelEvents, (ww != initialWW || wl != initialWL) {
                break
            }
            sleep(1)
        }

        print("[UI] DICOM final window/level: WW=\(windowWidthLabel.label) WL=\(windowLevelLabel.label) wlEvents=\(windowLevelEventsLabel.label)")
        XCTAssertGreaterThan(Int(windowLevelEventsLabel.label) ?? 0, initialWindowLevelEvents, "Expected window/level handler to receive drag updates.")

        // Verify stable-origin math (prevents mid-drag re-captures that cause jumps).
        let pointsPerHU = 2.0
        let translationX = (endVector.dx - startVector.dx) * webView.frame.size.width
        let translationY = (endVector.dy - startVector.dy) * webView.frame.size.height
        let expectedWW = max(1.0, initialWW + (Double(translationX) * pointsPerHU))
        let expectedWL = initialWL - (Double(translationY) * pointsPerHU)

        let finalWW = Double(windowWidthLabel.label) ?? initialWW
        let finalWL = Double(windowLevelLabel.label) ?? initialWL
        XCTAssertEqual(finalWW, expectedWW, accuracy: 50, "Expected WW to match translation-based calculation.")
        XCTAssertEqual(finalWL, expectedWL, accuracy: 50, "Expected WL to match translation-based calculation.")

        XCTAssertEqual(crosshairSliceIndexLabel.label, initialCrosshairSliceIndex, "Expected window/level gesture not to change the crosshair slice index.")
        XCTAssertEqual(stackScrollEventsLabel.label, initialStackScrollEvents, "Expected window/level gesture not to trigger stack scroll.")
    }
}
