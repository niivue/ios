//
//  WKWebView+JavaScriptEvaluating.swift
//  NiiVue
//
//  Task 3: WKWebView conformance to JavaScriptEvaluating protocol
//

import Foundation
import WebKit

extension WKWebView: JavaScriptEvaluating {
    func evaluateCommand(_ javaScript: String) async throws {
        // Prefer the native async overload (deployment target iOS 16.4).
        _ = try await evaluateJavaScript(javaScript)
    }

    func evaluateString(_ javaScript: String) async throws -> String? {
        let trimmed = javaScript.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(
            !trimmed.hasPrefix("return "),
            "evaluateString expects an expression; use callAsyncString for function bodies."
        )
        // `evaluateJavaScript` returns an `Any?`; keep the public surface typed.
        return try await evaluateJavaScript(javaScript) as? String
    }

    func callAsyncString(_ functionBody: String) async throws -> String? {
        // `callAsyncJavaScript` awaits Promise results (required for Niivue APIs like `saveImage`).
        try await callAsyncJavaScript(functionBody, arguments: [:], in: nil, contentWorld: .page) as? String
    }
}
