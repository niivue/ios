//
//  NiivueError.swift
//  NiiVue
//
//  Error types for the Swift ↔︎ WKWebView ↔︎ Niivue bridge.
//

import Foundation

public enum NiivueError: Error, LocalizedError, CustomStringConvertible {
    // MARK: - WebView lifecycle

    case webViewNotReady
    case webViewDeallocated

    // MARK: - JavaScript bridge

    case javaScriptEvaluationFailed(underlying: Error, script: String)
    case javaScriptPromiseRejected(reason: String, script: String)

    // MARK: - Files

    case fileNotFound(fileId: String)
    case unsupportedFileFormat(fileName: String, extension: String)
    case fileLoadFailed(fileName: String, reason: String?)

    // MARK: - Timeouts / cancellation

    case operationTimeout(operation: String, timeoutSeconds: Double)
    case cancelled(operation: String)

    public var errorDescription: String? {
        switch self {
        case .webViewNotReady:
            return "WebView is not ready."
        case .webViewDeallocated:
            return "WebView was deallocated."

        case .javaScriptEvaluationFailed(let underlying, _):
            return "JavaScript evaluation failed: \(underlying.localizedDescription)"
        case .javaScriptPromiseRejected(let reason, _):
            return "JavaScript promise rejected: \(reason)"

        case .fileNotFound(let fileId):
            return "File not found: \(fileId)"
        case .unsupportedFileFormat(let fileName, let ext):
            return "Unsupported file format: \(fileName) (.\(ext))"
        case .fileLoadFailed(let fileName, let reason):
            return "Failed to load \(fileName): \(reason ?? "unknown error")"

        case .operationTimeout(let operation, let timeoutSeconds):
            return "Operation '\(operation)' timed out after \(timeoutSeconds)s."
        case .cancelled(let operation):
            return "Operation '\(operation)' was cancelled."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .webViewNotReady:
            return "Wait for the viewer to finish loading before retrying."
        case .javaScriptEvaluationFailed:
            return "Retry the action. If it continues, restart the app."
        case .javaScriptPromiseRejected:
            return "Check the selected files and try again."
        case .unsupportedFileFormat:
            return "Supported formats include .nii and .nii.gz."
        case .operationTimeout:
            return "Try again. Large datasets may take several minutes on-device."
        case .fileNotFound, .fileLoadFailed, .webViewDeallocated, .cancelled:
            return nil
        }
    }

    public var description: String {
        errorDescription ?? "NiivueError"
    }

    public static func wrap(_ error: Error, context: String) -> NiivueError {
        if let niivueError = error as? NiivueError { return niivueError }
        if error is CancellationError { return .cancelled(operation: context) }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            return .cancelled(operation: context)
        }

        return .javaScriptEvaluationFailed(underlying: error, script: context)
    }
}

