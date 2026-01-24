//
//  JavaScriptEvaluating.swift
//  NiiVue
//
//  Task 3: Protocol for async JavaScript evaluation
//  Enables testable Swift↔JS bridge by abstracting WKWebView's JS APIs.
//

import Foundation

/// Protocol for evaluating JavaScript asynchronously.
/// Conformers include `WKWebView` (production) and `MockJavaScriptEvaluator` (testing).
@MainActor
protocol JavaScriptEvaluating: AnyObject {
    /// Evaluates JavaScript for side effects (no return value needed).
    func evaluateCommand(_ javaScript: String) async throws

    /// Evaluates JavaScript and returns a string result.
    func evaluateString(_ javaScript: String) async throws -> String?

    /// Calls an async JavaScript function body and returns a string result.
    /// Use this for Niivue APIs that return Promises (e.g., `saveImage`).
    func callAsyncString(_ functionBody: String) async throws -> String?
}

// MARK: - NiivueError wrappers

extension JavaScriptEvaluating {
    func evaluateCommandSafe(_ javaScript: String) async throws {
        do {
            try await evaluateCommand(javaScript)
        } catch {
            throw NiivueError.wrap(error, context: javaScript)
        }
    }

    func evaluateStringSafe(_ javaScript: String) async throws -> String? {
        do {
            return try await evaluateString(javaScript)
        } catch {
            throw NiivueError.wrap(error, context: javaScript)
        }
    }

    func callAsyncStringSafe(_ functionBody: String) async throws -> String? {
        do {
            return try await callAsyncString(functionBody)
        } catch {
            throw NiivueError.wrap(error, context: functionBody)
        }
    }
}
