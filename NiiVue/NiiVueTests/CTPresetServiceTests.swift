//
//  CTPresetServiceTests.swift
//  NiiVueTests
//
//  CT Adaptive Engine: Swift bridge service tests (TDD)
//

import XCTest
@testable import NiiVue

@MainActor
final class CTPresetServiceTests: XCTestCase {
    func testSetAutoApplyCTPresetWritesBooleanLiteral() async throws {
        let js = MockJavaScriptEvaluator()

        try await CTPresetService.setAutoApplyCTPreset(evaluator: js, enabled: true)

        XCTAssertEqual(js.scripts, ["window.autoApplyCTPreset = true"])
    }

    func testApplyAdaptivePresetBuildsCorrectJSCall() async throws {
        let js = MockJavaScriptEvaluator()

        try await CTPresetService.applyAdaptivePreset(evaluator: js, volumeIndex: 0)

        XCTAssertEqual(js.scripts, ["window.applyAdaptiveCTUrinaryPreset(0)"])
    }

    func testApplyPresetBuildsCorrectJSCallWithEscaping() async throws {
        let js = MockJavaScriptEvaluator()

        try await CTPresetService.applyPreset(evaluator: js, volumeIndex: 0, presetName: "ct_urinary_excretory")

        XCTAssertEqual(js.scripts, ["window.applyCTUrinaryPreset(0, \"ct_urinary_excretory\")"])
    }

    func testListPresetsParsesJSONStringArray() async throws {
        let js = MockJavaScriptEvaluator()
        js.nextString = "[\"ct_urinary_adaptive\",\"ct_urinary_stones\"]"

        let presets = try await CTPresetService.listPresets(evaluator: js)

        XCTAssertEqual(js.scripts, ["JSON.stringify(window.listCTUrinaryPresets())"])
        XCTAssertEqual(presets, ["ct_urinary_adaptive", "ct_urinary_stones"])
    }
}

