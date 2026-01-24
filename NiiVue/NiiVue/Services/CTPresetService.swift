//
//  CTPresetService.swift
//  NiiVue
//
//  CT Urinary Tract Adaptive Preset Engine — Swift bridge service
//

import Foundation

/// A small Swift service that translates native CT preset intent into safe JS commands.
@MainActor
enum CTPresetService {
    static func setAutoApplyCTPreset(evaluator: JavaScriptEvaluating, enabled: Bool) async throws {
        let literal = enabled ? "true" : "false"
        try await evaluator.evaluateCommand("window.autoApplyCTPreset = \(literal)")
    }

    static func applyAdaptivePreset(evaluator: JavaScriptEvaluating, volumeIndex: Int = 0) async throws {
        try await evaluator.evaluateCommand("window.applyAdaptiveCTUrinaryPreset(\(volumeIndex))")
    }

    static func applyPreset(evaluator: JavaScriptEvaluating, volumeIndex: Int = 0, presetName: String) async throws {
        let presetEscaped = try JavaScriptQuote.jsonStringLiteral(presetName)
        try await evaluator.evaluateCommand("window.applyCTUrinaryPreset(\(volumeIndex), \(presetEscaped))")
    }

    static func listPresets(evaluator: JavaScriptEvaluating) async throws -> [String] {
        guard
            let json = try await evaluator.evaluateString("JSON.stringify(window.listCTUrinaryPresets())"),
            let data = json.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }

        return decoded
    }
}

