//
//  WKWebView+JavaScriptEvaluating.swift
//  NiiVue
//
//  Task 3: WKWebView conformance to JavaScriptEvaluating protocol
//

import WebKit

extension WKWebView: JavaScriptEvaluating {
    func evaluateCommand(_ javaScript: String) async throws {
        // Prefer the native async overload (deployment target iOS 16.4).
        _ = try await evaluateJavaScript(javaScript)
    }

    func evaluateString(_ javaScript: String) async throws -> String? {
        // `evaluateJavaScript` returns an `Any?`; keep the public surface typed.
        try await evaluateJavaScript(javaScript) as? String
    }

    func callAsyncString(_ functionBody: String) async throws -> String? {
        // `callAsyncJavaScript` awaits Promise results (required for Niivue APIs like `saveImage`).
        try await callAsyncJavaScript(functionBody, arguments: [:], in: nil, contentWorld: .page) as? String
    }
}
