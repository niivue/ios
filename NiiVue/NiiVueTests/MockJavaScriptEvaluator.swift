//
//  MockJavaScriptEvaluator.swift
//  NiiVueTests
//
//  Task 3: Mock for testing JavaScript evaluation
//

import Foundation
@testable import NiiVue

@MainActor
final class MockJavaScriptEvaluator: JavaScriptEvaluating {
    var scripts: [String] = []
    var nextString: String?
    var nextAsyncString: String?

    func evaluateCommand(_ javaScript: String) async throws {
        scripts.append(javaScript)
    }

    func evaluateString(_ javaScript: String) async throws -> String? {
        let trimmed = javaScript.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(
            !trimmed.hasPrefix("return "),
            "evaluateString expects an expression; use callAsyncString for function bodies."
        )
        scripts.append(javaScript)
        return nextString
    }

    func callAsyncString(_ functionBody: String) async throws -> String? {
        scripts.append(functionBody)
        return nextAsyncString
    }
}
