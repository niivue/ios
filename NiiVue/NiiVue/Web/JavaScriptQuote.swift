//
//  JavaScriptQuote.swift
//  NiiVue
//
//  Task 2: JSON-safe JavaScript string quoting helper
//  Uses JSONEncoder to properly escape strings for safe JavaScript evaluation.
//

import Foundation

enum JavaScriptQuote {
    /// Converts a Swift string to a JSON string literal (with surrounding quotes).
    /// This is safe for embedding in JavaScript code evaluated via WKWebView.
    ///
    /// Example: `O'Reilly\nLine2` becomes `"O'Reilly\nLine2"` (properly escaped)
    static func jsonStringLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return string // includes surrounding quotes
    }
}
