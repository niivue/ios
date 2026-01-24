//
//  NiivueKit Error Handling & Async Patterns - Implementation Examples
//
//  These are reference implementations showing how to apply the patterns
//  from ERROR_HANDLING_ASYNC_PATTERNS.md to the NiivueKit SDK.
//
//  DO NOT add these directly to the project - they are examples to guide implementation.
//

import Foundation
import WebKit
import Combine
import os.log

// MARK: - 1. Error Types Implementation

/// Comprehensive error types for NiivueKit operations
public enum NiivueError: Error, LocalizedError, CustomStringConvertible {

    // MARK: - JavaScript Bridge Errors

    case javaScriptEvaluationFailed(underlying: Error, script: String)
    case javaScriptTypeMismatch(expected: String, actual: String, script: String)
    case javaScriptNullResult(script: String)
    case javaScriptPromiseRejected(reason: String, script: String)
    case javaScriptFunctionUnavailable(functionName: String)

    // MARK: - File Loading Errors

    case unsupportedFileFormat(fileName: String, extension: String)
    case fileLoadFailed(fileName: String, reason: String?)
    case fileNotFound(fileId: String)
    case fileEncodingFailed(fileName: String, underlying: Error)
    case fileTooLarge(fileName: String, sizeBytes: Int64, maxSizeBytes: Int64)

    // MARK: - DICOM Conversion Errors

    case dicomConversionFailed(seriesId: String, reason: String?)
    case dicomSeriesInvalid(seriesId: String, reason: String)
    case dicomManifestFailed(seriesId: String, underlying: Error)
    case dicomSeriesNotFound(seriesId: String)

    // MARK: - WebView Lifecycle Errors

    case webViewInitializationTimeout(timeoutSeconds: Double)
    case webViewNotReady
    case webViewDeallocated
    case webViewNavigationFailed(url: String, underlying: Error?)
    case urlSchemeHandlerFailed(url: String, underlying: Error)

    // MARK: - Timeout Errors

    case operationTimeout(operation: String, timeoutSeconds: Double)
    case fileLoadTimeout(fileName: String, timeoutSeconds: Double)
    case dicomConversionTimeout(seriesId: String, timeoutSeconds: Double)

    // MARK: - State Synchronization Errors

    case volumeCountMismatch(swift: Int, javascript: Int)
    case volumeNotFound(index: Int, volumeCount: Int)
    case sessionStateInvalid(reason: String)
    case sessionRestoreFailed(underlying: Error)

    // MARK: - Cancellation

    case cancelled(operation: String)

    // MARK: - LocalizedError Implementation

    public var errorDescription: String? {
        switch self {
        case .javaScriptEvaluationFailed(let error, _):
            return "JavaScript evaluation failed: \(error.localizedDescription)"
        case .javaScriptTypeMismatch(let expected, let actual, _):
            return "JavaScript type mismatch: expected \(expected), got \(actual)"
        case .javaScriptNullResult:
            return "JavaScript returned null when a value was expected"
        case .javaScriptPromiseRejected(let reason, _):
            return "JavaScript promise rejected: \(reason)"
        case .javaScriptFunctionUnavailable(let name):
            return "JavaScript function '\(name)' is not available"

        case .unsupportedFileFormat(let fileName, let ext):
            return "Unsupported file format: \(fileName) (.\(ext))"
        case .fileLoadFailed(let fileName, let reason):
            return "Failed to load \(fileName): \(reason ?? "unknown error")"
        case .fileNotFound(let fileId):
            return "File not found: \(fileId)"
        case .fileEncodingFailed(let fileName, let error):
            return "Failed to encode \(fileName): \(error.localizedDescription)"
        case .fileTooLarge(let fileName, let size, let max):
            return "File too large: \(fileName) (\(size) bytes, max: \(max) bytes)"

        case .dicomConversionFailed(let seriesId, let reason):
            return "DICOM conversion failed for series \(seriesId): \(reason ?? "unknown error")"
        case .dicomSeriesInvalid(let seriesId, let reason):
            return "Invalid DICOM series \(seriesId): \(reason)"
        case .dicomManifestFailed(let seriesId, let error):
            return "Failed to generate manifest for series \(seriesId): \(error.localizedDescription)"
        case .dicomSeriesNotFound(let seriesId):
            return "DICOM series not found: \(seriesId)"

        case .webViewInitializationTimeout(let timeout):
            return "WebView failed to initialize within \(timeout) seconds"
        case .webViewNotReady:
            return "WebView is not ready to receive commands"
        case .webViewDeallocated:
            return "WebView was deallocated during operation"
        case .webViewNavigationFailed(let url, let error):
            return "Failed to navigate to \(url): \(error?.localizedDescription ?? "unknown error")"
        case .urlSchemeHandlerFailed(let url, let error):
            return "URL scheme handler failed for \(url): \(error.localizedDescription)"

        case .operationTimeout(let operation, let timeout):
            return "Operation '\(operation)' timed out after \(timeout) seconds"
        case .fileLoadTimeout(let fileName, let timeout):
            return "Loading \(fileName) timed out after \(timeout) seconds"
        case .dicomConversionTimeout(let seriesId, let timeout):
            return "DICOM conversion for series \(seriesId) timed out after \(timeout) seconds"

        case .volumeCountMismatch(let swift, let js):
            return "Volume count mismatch: Swift has \(swift), JavaScript has \(js)"
        case .volumeNotFound(let index, let count):
            return "Volume at index \(index) not found (total volumes: \(count))"
        case .sessionStateInvalid(let reason):
            return "Invalid session state: \(reason)"
        case .sessionRestoreFailed(let error):
            return "Failed to restore session: \(error.localizedDescription)"

        case .cancelled(let operation):
            return "Operation '\(operation)' was cancelled"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .webViewInitializationTimeout:
            return "Try restarting the app or check your network connection"
        case .webViewNotReady:
            return "Wait for the WebView to finish loading before calling this method"
        case .unsupportedFileFormat:
            return "Supported formats: .nii, .nii.gz, .nrrd, .mgh, .mgz, .dcm"
        case .fileTooLarge:
            return "Try loading a smaller file or compress the data"
        case .dicomConversionFailed, .dicomConversionTimeout:
            return "Check that all DICOM files belong to the same series and are not corrupted"
        case .cancelled:
            return nil
        default:
            return "Check the error details and try again"
        }
    }

    public var description: String {
        errorDescription ?? "NiivueError"
    }

    // MARK: - Convenience Properties

    public var isTransient: Bool {
        switch self {
        case .webViewInitializationTimeout,
             .webViewNotReady,
             .operationTimeout,
             .fileLoadTimeout,
             .dicomConversionTimeout,
             .webViewNavigationFailed:
            return true
        case .javaScriptEvaluationFailed(let underlying, _):
            return (underlying as NSError).domain == NSURLErrorDomain
        default:
            return false
        }
    }

    public var isCancellation: Bool {
        if case .cancelled = self { return true }
        return false
    }

    public var isWarning: Bool {
        switch self {
        case .cancelled, .webViewNotReady:
            return true
        default:
            return false
        }
    }

    public static func wrap(_ error: Error, context: String) -> NiivueError {
        if let niivueError = error as? NiivueError {
            return niivueError
        }

        if (error as NSError).code == NSURLErrorCancelled {
            return .cancelled(operation: context)
        }

        return .javaScriptEvaluationFailed(underlying: error, script: context)
    }
}

// MARK: - 2. Timeout Support

extension Task where Failure == Error {
    /// Wraps an async operation with a timeout
    static func withTimeout<T>(
        seconds: TimeInterval,
        operation: String,
        priority: TaskPriority? = nil,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask(priority: priority) {
                try await work()
            }

            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NiivueError.operationTimeout(operation: operation, timeoutSeconds: seconds)
            }

            guard let result = try await group.next() else {
                throw NiivueError.operationTimeout(operation: operation, timeoutSeconds: seconds)
            }

            group.cancelAll()
            return result
        }
    }
}

// MARK: - 3. Cancellable Operations

/// Wrapper for cancellable long-running operations
@MainActor
public final class CancellableOperation<T> {
    private var task: Task<T, Error>?
    public private(set) var isCancelled = false
    public private(set) var isCompleted = false

    public init() {}

    public func start(
        timeout: TimeInterval? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        cancel()

        isCancelled = false
        isCompleted = false

        let task = Task {
            defer { isCompleted = true }

            if let timeout = timeout {
                return try await Task.withTimeout(
                    seconds: timeout,
                    operation: "CancellableOperation"
                ) {
                    try await operation()
                }
            } else {
                return try await operation()
            }
        }

        self.task = task

        do {
            return try await task.value
        } catch is CancellationError {
            throw NiivueError.cancelled(operation: "CancellableOperation")
        }
    }

    public func cancel() {
        isCancelled = true
        task?.cancel()
        task = nil
    }
}

// MARK: - 4. Retry Policy

public struct RetryPolicy {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let maxDelay: TimeInterval
    public let shouldRetry: (Error) -> Bool

    public static let `default` = RetryPolicy(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 10.0,
        shouldRetry: { error in
            (error as? NiivueError)?.isTransient ?? false
        }
    )

    public static let aggressive = RetryPolicy(
        maxAttempts: 5,
        initialDelay: 0.5,
        maxDelay: 5.0,
        shouldRetry: { _ in true }
    )

    public static let noRetry = RetryPolicy(
        maxAttempts: 1,
        initialDelay: 0,
        maxDelay: 0,
        shouldRetry: { _ in false }
    )
}

extension Task where Failure == Error {
    static func withRetry<T>(
        policy: RetryPolicy = .default,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<policy.maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                guard policy.shouldRetry(error) else {
                    throw error
                }

                if attempt < policy.maxAttempts - 1 {
                    let delay = min(
                        policy.initialDelay * pow(2.0, Double(attempt)),
                        policy.maxDelay
                    )
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NiivueError.operationTimeout(operation: "withRetry", timeoutSeconds: 0)
    }
}

// MARK: - 5. WebView Initializer with Retry

@MainActor
public final class WebViewInitializer {
    private let maxRetries: Int
    private let initialDelaySeconds: TimeInterval
    private let maxDelaySeconds: TimeInterval

    public init(
        maxRetries: Int = 3,
        initialDelaySeconds: TimeInterval = 1.0,
        maxDelaySeconds: TimeInterval = 10.0
    ) {
        self.maxRetries = maxRetries
        self.initialDelaySeconds = initialDelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
    }

    public func initialize(webViewManager: WebViewManager) async throws {
        var lastError: NiivueError?

        for attempt in 0..<maxRetries {
            do {
                webViewManager.load()
                try await waitForReady(webViewManager: webViewManager, timeoutSeconds: 30.0)
                Logger.niivue.info("WebView initialized successfully on attempt \(attempt + 1)")
                return

            } catch let error as NiivueError {
                lastError = error

                guard error.isTransient else {
                    throw error
                }

                let delay = min(
                    initialDelaySeconds * pow(2.0, Double(attempt)),
                    maxDelaySeconds
                )

                Logger.niivue.warning(
                    "WebView initialization failed (attempt \(attempt + 1)/\(maxRetries)), retrying in \(delay)s: \(error)"
                )

                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NiivueError.webViewInitializationTimeout(timeoutSeconds: 30.0)
    }

    private func waitForReady(
        webViewManager: WebViewManager,
        timeoutSeconds: TimeInterval
    ) async throws {
        let startTime = Date()

        while !webViewManager.isReady {
            if Date().timeIntervalSince(startTime) > timeoutSeconds {
                throw NiivueError.webViewInitializationTimeout(timeoutSeconds: timeoutSeconds)
            }

            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
            try Task.checkCancellation()
        }
    }
}

// MARK: - 6. Logging Infrastructure

extension Logger {
    static let niivue = Logger(subsystem: "com.niivue.niivuekit", category: "niivue")
    static let bridge = Logger(subsystem: "com.niivue.niivuekit", category: "bridge")
    static let files = Logger(subsystem: "com.niivue.niivuekit", category: "files")
    static let dicom = Logger(subsystem: "com.niivue.niivuekit", category: "dicom")

    func debugLog(_ message: String) {
        #if DEBUG
        self.debug("\(message)")
        #endif
    }

    func errorWithContext(_ message: String, error: Error, context: [String: Any] = [:]) {
        var contextString = ""
        if !context.isEmpty {
            contextString = " | Context: \(context)"
        }
        self.error("\(message): \(error.localizedDescription)\(contextString)")
    }
}

public struct PerformanceLogger {
    private let operation: String
    private let startTime: CFAbsoluteTime

    public init(operation: String) {
        self.operation = operation
        self.startTime = CFAbsoluteTimeGetCurrent()
        Logger.niivue.debug("[\(operation)] Started")
    }

    public func end(success: Bool = true) {
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        let status = success ? "Completed" : "Failed"
        Logger.niivue.info("[\(operation)] \(status) in \(String(format: "%.3f", duration))s")
    }
}

// MARK: - 7. Enhanced WebViewManager with Error Handling

// Example: How to enhance existing WebViewManager methods with proper error handling
extension WebViewManager {

    /// Loads a volume with timeout, retry, and comprehensive error handling
    func loadVolumeRobust(url: String, fileName: String) async throws {
        let perf = PerformanceLogger(operation: "loadVolume(\(fileName))")
        defer { perf.end(success: volumes.contains { $0.name == fileName }) }

        Logger.bridge.debugLog("Loading volume: \(fileName) from \(url)")

        // Check if WebView is ready
        guard isReady else {
            throw NiivueError.webViewNotReady
        }

        do {
            // Load with timeout and retry
            try await Task.withRetry(policy: .default) {
                try await Task.withTimeout(seconds: 30.0, operation: "loadVolume") {
                    try await self.loadImageFromUrl(url: url, fileName: fileName)
                }
            }

            Logger.files.info("Successfully loaded volume: \(fileName)")

        } catch let error as NiivueError {
            Logger.files.errorWithContext(
                "Failed to load volume",
                error: error,
                context: ["fileName": fileName, "url": url]
            )
            lastErrorMessage = error.localizedDescription
            throw error

        } catch {
            let niivueError = NiivueError.wrap(error, context: "loadVolumeRobust")
            Logger.files.errorWithContext(
                "Unexpected error loading volume",
                error: niivueError,
                context: ["fileName": fileName, "url": url]
            )
            lastErrorMessage = niivueError.localizedDescription
            throw niivueError
        }
    }

    /// Loads DICOM series with cancellation support
    func loadDicomSeriesCancellable(
        manifestUrl: String,
        cancellationToken: CancellableOperation<Void>
    ) async throws {
        let perf = PerformanceLogger(operation: "loadDicomSeries")
        defer { perf.end() }

        guard isReady else {
            throw NiivueError.webViewNotReady
        }

        do {
            try await cancellationToken.start(timeout: 120.0) {
                let escaped = try JavaScriptQuote.jsonStringLiteral(manifestUrl)
                _ = try await self.evaluator.callAsyncString(
                    "return await window.loadDicomSeriesFromManifest(\(escaped))"
                )
            }

            Logger.dicom.info("Successfully loaded DICOM series")

        } catch let error as NiivueError {
            if error.isCancellation {
                Logger.dicom.info("DICOM loading cancelled")
            } else {
                Logger.dicom.error("DICOM loading failed: \(error)")
            }
            throw error
        }
    }

    /// Fire-and-forget pattern for non-critical settings
    func setSliceTypeFireAndForget(_ sliceType: Int) {
        Task {
            do {
                try await evaluator.evaluateCommand("window.setSliceType(\(sliceType))")
            } catch {
                Logger.bridge.debug("Fire-and-forget setSliceType failed: \(error)")
            }
        }
    }
}

// MARK: - 8. Combine Publishers

@MainActor
extension WebViewManager {

    /// Publisher that loads a volume and emits completion
    func loadVolumePublisher(
        url: String,
        fileName: String
    ) -> AnyPublisher<Void, NiivueError> {
        Future { promise in
            Task {
                do {
                    try await self.loadVolumeRobust(url: url, fileName: fileName)
                    promise(.success(()))
                } catch let error as NiivueError {
                    promise(.failure(error))
                } catch {
                    promise(.failure(.wrap(error, context: "loadVolumePublisher")))
                }
            }
        }
        .eraseToAnyPublisher()
    }

    /// Publisher that exports viewer state
    func exportViewerStatePublisher() -> AnyPublisher<String, NiivueError> {
        Future { promise in
            Task {
                do {
                    let state = try await self.exportViewerStateJSON()
                    promise(.success(state))
                } catch let error as NiivueError {
                    promise(.failure(error))
                } catch {
                    promise(.failure(.wrap(error, context: "exportViewerStatePublisher")))
                }
            }
        }
        .eraseToAnyPublisher()
    }
}

// MARK: - 9. UIKit Compatibility Layer

extension WebViewManager {

    /// UIKit-compatible callback-based API for loading volumes
    func loadVolume(
        url: String,
        fileName: String,
        completion: @escaping (Result<Void, NiivueError>) -> Void
    ) {
        Task {
            do {
                try await loadVolumeRobust(url: url, fileName: fileName)
                await MainActor.run {
                    completion(.success(()))
                }
            } catch let error as NiivueError {
                await MainActor.run {
                    completion(.failure(error))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(.wrap(error, context: "loadVolume")))
                }
            }
        }
    }

    /// UIKit-compatible callback for DICOM loading with progress
    func loadDicomSeries(
        manifestUrl: String,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<Void, NiivueError>) -> Void
    ) {
        Task {
            do {
                try await loadDicomSeriesFromManifestURL(manifestUrl)
                await MainActor.run {
                    completion(.success(()))
                }
            } catch let error as NiivueError {
                await MainActor.run {
                    completion(.failure(error))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(.wrap(error, context: "loadDicomSeries")))
                }
            }
        }
    }
}

// MARK: - 10. Usage Examples

// Example: SwiftUI ViewModel
@MainActor
final class NiivueViewModel: ObservableObject {
    @Published var volumes: [VolumeInfo] = []
    @Published var isReady: Bool = false
    @Published var lastError: NiivueError?

    private let webViewManager: WebViewManager
    private let dicomOperation = CancellableOperation<Void>()

    init(webViewManager: WebViewManager) {
        self.webViewManager = webViewManager
    }

    func loadVolume(url: String, fileName: String) async {
        do {
            try await webViewManager.loadVolumeRobust(url: url, fileName: fileName)
            lastError = nil
        } catch let error as NiivueError {
            lastError = error
        } catch {
            lastError = .wrap(error, context: "loadVolume")
        }
    }

    func loadDicomSeries(manifestUrl: String) async {
        do {
            try await webViewManager.loadDicomSeriesCancellable(
                manifestUrl: manifestUrl,
                cancellationToken: dicomOperation
            )
            lastError = nil
        } catch let error as NiivueError {
            if !error.isCancellation {
                lastError = error
            }
        } catch {
            lastError = .wrap(error, context: "loadDicomSeries")
        }
    }

    func cancelDicomLoading() {
        dicomOperation.cancel()
    }
}

// Example: UIKit ViewController
class NiivueViewController: UIViewController {
    private var webViewManager: WebViewManager!

    func loadVolumeFromPicker(url: String, fileName: String) {
        showLoadingIndicator()

        webViewManager.loadVolume(url: url, fileName: fileName) { [weak self] result in
            self?.hideLoadingIndicator()

            switch result {
            case .success:
                self?.showSuccessMessage("Volume loaded successfully")
            case .failure(let error):
                self?.showErrorAlert(error)
            }
        }
    }

    private func showErrorAlert(_ error: NiivueError) {
        let alert = UIAlertController(
            title: "Error",
            message: error.errorDescription,
            preferredStyle: .alert
        )

        if let suggestion = error.recoverySuggestion {
            alert.message = "\(error.errorDescription ?? "")\n\n\(suggestion)"
        }

        alert.addAction(UIAlertAction(title: "OK", style: .default))

        if error.isTransient {
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { [weak self] _ in
                // Retry logic
            })
        }

        present(alert, animated: true)
    }

    private func showLoadingIndicator() { /* ... */ }
    private func hideLoadingIndicator() { /* ... */ }
    private func showSuccessMessage(_ message: String) { /* ... */ }
}
