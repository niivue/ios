# NiivueKit Error Handling & Async Patterns Design

**Version:** 1.0
**Date:** 2026-01-04
**Author:** Swift SDK Architecture Design

This document defines comprehensive error handling and async patterns for NiivueKit, a Swift SDK that bridges to the Niivue JavaScript library running in WKWebView.

---

## Table of Contents

1. [Error Types](#1-error-types)
2. [Async/Await Patterns](#2-asyncawait-patterns)
3. [Cancellation Support](#3-cancellation-support)
4. [Combine Integration](#4-combine-integration)
5. [Result Type Usage](#5-result-type-usage)
6. [Retry Logic](#6-retry-logic)
7. [Logging and Diagnostics](#7-logging-and-diagnostics)

---

## 1. Error Types

### 1.1 Core Error Enum

```swift
import Foundation
import os.log

/// Comprehensive error types for NiivueKit operations.
/// All errors provide localized descriptions and recovery suggestions where applicable.
public enum NiivueError: Error, LocalizedError, CustomStringConvertible {

    // MARK: - JavaScript Bridge Errors

    /// JavaScript evaluation failed with the underlying error
    case javaScriptEvaluationFailed(underlying: Error, script: String)

    /// JavaScript returned an unexpected type
    case javaScriptTypeMismatch(expected: String, actual: String, script: String)

    /// JavaScript returned null when a value was expected
    case javaScriptNullResult(script: String)

    /// JavaScript promise was rejected
    case javaScriptPromiseRejected(reason: String, script: String)

    /// JavaScript function not found or not ready
    case javaScriptFunctionUnavailable(functionName: String)

    // MARK: - File Loading Errors

    /// File format is not supported by Niivue
    case unsupportedFileFormat(fileName: String, extension: String)

    /// File loading failed (from Niivue JS)
    case fileLoadFailed(fileName: String, reason: String?)

    /// File not found in imported file store
    case fileNotFound(fileId: String)

    /// File encoding/decoding error
    case fileEncodingFailed(fileName: String, underlying: Error)

    /// File too large to process
    case fileTooLarge(fileName: String, sizeBytes: Int64, maxSizeBytes: Int64)

    // MARK: - DICOM Conversion Errors

    /// DICOM series conversion to NIfTI failed
    case dicomConversionFailed(seriesId: String, reason: String?)

    /// DICOM series is empty or invalid
    case dicomSeriesInvalid(seriesId: String, reason: String)

    /// DICOM manifest generation failed
    case dicomManifestFailed(seriesId: String, underlying: Error)

    /// DICOM series not registered in store
    case dicomSeriesNotFound(seriesId: String)

    // MARK: - WebView Lifecycle Errors

    /// WebView failed to initialize within timeout period
    case webViewInitializationTimeout(timeoutSeconds: Double)

    /// WebView is not ready to receive commands
    case webViewNotReady

    /// WebView was deallocated during operation
    case webViewDeallocated

    /// WebView navigation failed
    case webViewNavigationFailed(url: String, underlying: Error?)

    /// Custom URL scheme handler failed
    case urlSchemeHandlerFailed(url: String, underlying: Error)

    // MARK: - Timeout Errors

    /// Generic operation timeout
    case operationTimeout(operation: String, timeoutSeconds: Double)

    /// File load operation timed out
    case fileLoadTimeout(fileName: String, timeoutSeconds: Double)

    /// DICOM conversion timed out
    case dicomConversionTimeout(seriesId: String, timeoutSeconds: Double)

    // MARK: - State Synchronization Errors

    /// Volume count mismatch between Swift and JavaScript
    case volumeCountMismatch(swift: Int, javascript: Int)

    /// Volume not found at specified index
    case volumeNotFound(index: Int, volumeCount: Int)

    /// Session state is corrupted or invalid
    case sessionStateInvalid(reason: String)

    /// Session restore failed
    case sessionRestoreFailed(underlying: Error)

    // MARK: - Cancellation

    /// Operation was cancelled by user or system
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

    public var failureReason: String? {
        switch self {
        case .javaScriptEvaluationFailed(_, let script):
            return "Script: \(script.prefix(100))..."
        case .javaScriptTypeMismatch(_, _, let script):
            return "Script: \(script.prefix(100))..."
        case .javaScriptNullResult(let script):
            return "Script: \(script.prefix(100))..."
        case .javaScriptPromiseRejected(_, let script):
            return "Script: \(script.prefix(100))..."
        default:
            return nil
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .webViewInitializationTimeout:
            return "Try restarting the app or check your network connection"
        case .webViewNotReady:
            return "Wait for the WebView to finish loading before calling this method"
        case .unsupportedFileFormat(_, let ext):
            return "Supported formats: .nii, .nii.gz, .nrrd, .mgh, .mgz, .dcm"
        case .fileTooLarge:
            return "Try loading a smaller file or compress the data"
        case .dicomConversionFailed, .dicomConversionTimeout:
            return "Check that all DICOM files belong to the same series and are not corrupted"
        case .cancelled:
            return nil // Cancellation is normal
        default:
            return "Check the error details and try again"
        }
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        errorDescription ?? "NiivueError"
    }

    // MARK: - Convenience Properties

    /// Whether this error represents a transient failure that might succeed on retry
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
            // Network errors are transient
            return (underlying as NSError).domain == NSURLErrorDomain
        default:
            return false
        }
    }

    /// Whether this error represents a cancelled operation
    public var isCancellation: Bool {
        if case .cancelled = self {
            return true
        }
        return false
    }

    /// Whether this error should be logged as a warning vs error
    public var isWarning: Bool {
        switch self {
        case .cancelled, .webViewNotReady:
            return true
        default:
            return false
        }
    }
}
```

### 1.2 Error Extension for Underlying Errors

```swift
extension NiivueError {
    /// Extracts the root underlying error if available
    public var underlyingError: Error? {
        switch self {
        case .javaScriptEvaluationFailed(let error, _):
            return error
        case .fileEncodingFailed(_, let error):
            return error
        case .dicomManifestFailed(_, let error):
            return error
        case .webViewNavigationFailed(_, let error):
            return error
        case .urlSchemeHandlerFailed(_, let error):
            return error
        case .sessionRestoreFailed(let error):
            return error
        default:
            return nil
        }
    }

    /// Converts a generic Error to NiivueError with context
    public static func wrap(_ error: Error, context: String) -> NiivueError {
        if let niivueError = error as? NiivueError {
            return niivueError
        }

        // Check for cancellation
        if (error as NSError).code == NSURLErrorCancelled {
            return .cancelled(operation: context)
        }

        return .javaScriptEvaluationFailed(underlying: error, script: context)
    }
}
```

---

## 2. Async/Await Patterns

### 2.1 Async Throws Operations

All operations that cross the JS bridge or involve I/O should be `async throws`:

```swift
@MainActor
public protocol NiivueOperations {

    // MARK: - Volume Loading (async throws)

    /// Loads a volume from a URL. Throws NiivueError if loading fails.
    func loadVolume(url: String, fileName: String) async throws

    /// Loads multiple volumes from URLs. Throws on first failure.
    func loadVolumes(_ specs: [(url: String, name: String)]) async throws

    /// Adds volumes without clearing existing ones. Throws on failure.
    func addVolumes(_ specs: [(url: String, name: String)]) async throws

    // MARK: - DICOM Operations (async throws)

    /// Converts and loads a DICOM series. This is a long-running operation.
    func loadDicomSeries(manifestUrl: String) async throws

    // MARK: - State Export (async throws)

    /// Exports current viewer state as JSON. Throws if export fails.
    func exportViewerState() async throws -> String

    /// Exports full session snapshot including volume sources. Throws if export fails.
    func exportSessionSnapshot() async throws -> String

    // MARK: - Drawing Operations (async throws)

    /// Saves current drawing as base64-encoded NIfTI. Returns nil if no drawing exists.
    func saveDrawing() async throws -> String?

    /// Undoes last drawing operation. Throws if undo fails.
    func drawUndo() async throws
}
```

### 2.2 Async Non-Throwing Operations

Simple property setters that are fire-and-forget can be `async` without `throws`:

```swift
@MainActor
public protocol NiivueConfiguration {

    // MARK: - View Settings (async, no throws - fire and forget)

    /// Sets the slice type. Does not throw; failures are logged.
    func setSliceType(_ sliceType: SliceType) async

    /// Sets the multiplanar layout. Does not throw; failures are logged.
    func setLayout(_ layout: Layout) async

    /// Sets crosshair visibility. Does not throw; failures are logged.
    func setCrosshairVisible(visible: Bool) async

    // MARK: - Volume Settings (async, no throws)

    /// Sets colormap for a volume. Does not throw; failures are logged.
    func setColormap(volumeIndex: Int, colormap: String) async

    /// Sets opacity for a volume. Does not throw; failures are logged.
    func setOpacity(volumeIndex: Int, opacity: Double) async

    /// Sets 4D frame for a volume. Does not throw; failures are logged.
    func setFrame4D(volumeIndex: Int, frame: Int) async
}

// Implementation that logs but doesn't throw
extension WebViewManager: NiivueConfiguration {
    public func setSliceType(_ sliceType: SliceType) async {
        do {
            try await evaluator.evaluateCommand("window.setSliceType(\(sliceType.rawValue))")
        } catch {
            Logger.niivue.warning("Failed to set slice type: \(error.localizedDescription)")
        }
    }

    public func setColormap(volumeIndex: Int, colormap: String) async {
        do {
            let escaped = try JavaScriptQuote.jsonStringLiteral(colormap)
            try await evaluator.evaluateCommand("window.setColormap(\(volumeIndex), \(escaped))")
        } catch {
            Logger.niivue.warning("Failed to set colormap: \(error.localizedDescription)")
        }
    }
}
```

### 2.3 Fire-and-Forget Pattern

For operations where we don't care about completion or errors:

```swift
extension WebViewManager {
    /// Fire-and-forget pattern for non-critical operations
    private func fireAndForget(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                Logger.niivue.debug("Fire-and-forget operation failed: \(error)")
            }
        }
    }

    /// Example: Update crosshair color (non-critical)
    public func updateCrosshairColor() {
        fireAndForget {
            try await self.evaluator.evaluateCommand("window.setCrosshairColor()")
        }
    }
}
```

### 2.4 Timeout Wrapper

All async operations should support configurable timeouts:

```swift
extension Task where Failure == Error {
    /// Wraps an async operation with a timeout
    static func withTimeout<T>(
        seconds: TimeInterval,
        operation: String,
        priority: TaskPriority? = nil,
        work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the actual work
            group.addTask(priority: priority) {
                try await work()
            }

            // Add the timeout
            group.addTask(priority: .utility) {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NiivueError.operationTimeout(operation: operation, timeoutSeconds: seconds)
            }

            // Return first result (either completion or timeout)
            guard let result = try await group.next() else {
                throw NiivueError.operationTimeout(operation: operation, timeoutSeconds: seconds)
            }

            // Cancel the other task
            group.cancelAll()

            return result
        }
    }
}

// Usage example:
func loadVolumeWithTimeout(url: String, fileName: String) async throws {
    try await Task.withTimeout(
        seconds: 30.0,
        operation: "loadVolume(\(fileName))"
    ) {
        try await self.loadImageFromUrl(url: url, fileName: fileName)
    }
}
```

---

## 3. Cancellation Support

### 3.1 Task Cancellation Integration

All long-running operations must check for cancellation:

```swift
extension WebViewManager {
    /// Loads a DICOM series with proper cancellation support
    func loadDicomSeriesWithCancellation(manifestUrl: String) async throws {
        // Check cancellation before starting
        try Task.checkCancellation()

        let escapedUrl = try JavaScriptQuote.jsonStringLiteral(manifestUrl)

        // Start the operation
        let task = Task {
            try await evaluator.callAsyncString(
                "return await window.loadDicomSeriesFromManifest(\(escapedUrl))"
            )
        }

        // Monitor for cancellation
        while !task.isCancelled {
            if Task.isCancelled {
                task.cancel()
                throw NiivueError.cancelled(operation: "loadDicomSeries")
            }

            // Check if complete
            if task.isCompleted {
                break
            }

            // Brief sleep to avoid tight loop
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }

        // Get result or throw if cancelled
        try Task.checkCancellation()
        _ = try await task.value
    }
}
```

### 3.2 Cancellable Operation Wrapper

Reusable wrapper for cancellable operations:

```swift
/// Wrapper for cancellable long-running operations
@MainActor
public final class CancellableOperation<T> {
    private var task: Task<T, Error>?
    public private(set) var isCancelled = false
    public private(set) var isCompleted = false

    public init() {}

    /// Starts the operation
    public func start(
        timeout: TimeInterval? = nil,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        // Cancel any existing task
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
            let result = try await task.value
            return result
        } catch is CancellationError {
            throw NiivueError.cancelled(operation: "CancellableOperation")
        }
    }

    /// Cancels the operation
    public func cancel() {
        isCancelled = true
        task?.cancel()
        task = nil
    }
}

// Usage:
class DicomLoader {
    private let operation = CancellableOperation<Void>()

    func loadDicomSeries(manifestUrl: String) async throws {
        try await operation.start(timeout: 120.0) {
            try await self.webViewManager.loadDicomSeriesFromManifestURL(manifestUrl)
        }
    }

    func cancelLoading() {
        operation.cancel()
    }
}
```

### 3.3 Cleanup on Cancellation

```swift
extension WebViewManager {
    /// Loads volumes with proper cleanup on cancellation
    func loadVolumesWithCleanup(_ specs: [(url: String, name: String)]) async throws {
        // Store original state for rollback
        let originalVolumes = volumes
        let originalSources = volumeSources

        do {
            try await loadVolumesFromUrls(specs)
        } catch {
            // Cleanup on failure or cancellation
            if Task.isCancelled {
                // Restore original state
                volumes = originalVolumes
                volumeSources = originalSources
                throw NiivueError.cancelled(operation: "loadVolumes")
            }
            throw error
        }
    }
}
```

---

## 4. Combine Integration

### 4.1 Publishers for Continuous Events

State changes should be published via Combine:

```swift
import Combine

@MainActor
public final class NiivueViewModel: ObservableObject {
    // MARK: - Published State

    /// Current volume list (emits on every volume change)
    @Published public private(set) var volumes: [VolumeInfo] = []

    /// Current crosshair location (emits on every location change)
    @Published public private(set) var crosshairLocation: String?

    /// WebView ready state (emits on initialization complete)
    @Published public private(set) var isReady: Bool = false

    /// Last error (emits when errors occur, nil when cleared)
    @Published public private(set) var lastError: NiivueError?

    // MARK: - Custom Publishers

    /// Publisher that emits when a volume is loaded
    public var volumeLoadedPublisher: AnyPublisher<VolumeInfo, Never> {
        $volumes
            .compactMap { $0.last }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Publisher that emits when ready state changes to true
    public var readyPublisher: AnyPublisher<Void, Never> {
        $isReady
            .filter { $0 }
            .map { _ in () }
            .eraseToAnyPublisher()
    }

    /// Publisher that emits errors (non-nil values only)
    public var errorPublisher: AnyPublisher<NiivueError, Never> {
        $lastError
            .compactMap { $0 }
            .eraseToAnyPublisher()
    }
}

// Usage in SwiftUI:
struct ContentView: View {
    @StateObject var viewModel: NiivueViewModel

    var body: some View {
        VStack {
            // React to ready state
            if viewModel.isReady {
                Text("Ready")
            } else {
                ProgressView("Loading...")
            }

            // Display errors
            if let error = viewModel.lastError {
                ErrorView(error: error)
            }

            // Display volumes
            ForEach(viewModel.volumes, id: \.id) { volume in
                VolumeRow(volume: volume)
            }
        }
        .onReceive(viewModel.errorPublisher) { error in
            // Show alert for errors
            showErrorAlert(error)
        }
    }
}
```

### 4.2 One-Shot Publishers for Load Operations

For single async operations, bridge to Combine:

```swift
extension WebViewManager {
    /// Publisher that loads a volume and emits completion
    public func loadVolumePublisher(
        url: String,
        fileName: String
    ) -> AnyPublisher<Void, NiivueError> {
        Future { promise in
            Task {
                do {
                    try await self.loadImageFromUrl(url: url, fileName: fileName)
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
    public func exportViewerStatePublisher() -> AnyPublisher<String, NiivueError> {
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

// Usage:
cancellables.insert(
    webViewManager
        .loadVolumePublisher(url: fileUrl, fileName: fileName)
        .receive(on: DispatchQueue.main)
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    self.handleError(error)
                }
            },
            receiveValue: {
                print("Volume loaded successfully")
            }
        )
)
```

### 4.3 Error Handling in Combine Streams

```swift
extension Publishers {
    /// Custom operator for handling NiivueErrors in Combine streams
    func handleNiivueError(
        _ handler: @escaping (NiivueError) -> Void
    ) -> Publishers.Catch<Self, Empty<Self.Output, Never>> where Self.Failure == NiivueError {
        self.catch { error -> Empty<Self.Output, Never> in
            handler(error)
            return Empty()
        }
    }
}

// Usage:
webViewManager
    .loadVolumePublisher(url: url, fileName: fileName)
    .handleNiivueError { error in
        Logger.niivue.error("Failed to load volume: \(error)")
        self.showErrorAlert(error)
    }
    .sink { _ in
        print("Success")
    }
    .store(in: &cancellables)
```

---

## 5. Result Type Usage

### 5.1 When to Use Result vs Async Throws

**Use `async throws`:**
- Primary API for modern Swift code
- When calling from other async contexts
- When you want automatic error propagation

**Use `Result<T, NiivueError>`:**
- When providing callbacks for UIKit compatibility
- When you need to store success/failure without executing
- When building functional pipelines

### 5.2 Callback-Based APIs for UIKit Compatibility

```swift
extension WebViewManager {
    /// UIKit-compatible callback-based API for loading volumes
    public func loadVolume(
        url: String,
        fileName: String,
        completion: @escaping (Result<Void, NiivueError>) -> Void
    ) {
        Task {
            do {
                try await loadImageFromUrl(url: url, fileName: fileName)
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

    /// UIKit-compatible callback for DICOM loading
    public func loadDicomSeries(
        manifestUrl: String,
        progress: ((Double) -> Void)? = nil,
        completion: @escaping (Result<Void, NiivueError>) -> Void
    ) {
        Task {
            do {
                // TODO: Wire up progress reporting
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

// Usage in UIKit:
class ViewController: UIViewController {
    func loadVolume() {
        webViewManager.loadVolume(
            url: fileUrl,
            fileName: fileName
        ) { result in
            switch result {
            case .success:
                self.showSuccessMessage()
            case .failure(let error):
                self.showError(error)
            }
        }
    }
}
```

### 5.3 Result for Deferred Execution

```swift
/// Represents a volume load operation that can be executed later
public struct VolumeLoadOperation {
    public let url: String
    public let fileName: String

    /// Executes the load operation and returns a Result
    public func execute(
        using webViewManager: WebViewManager
    ) async -> Result<Void, NiivueError> {
        do {
            try await webViewManager.loadImageFromUrl(url: url, fileName: fileName)
            return .success(())
        } catch let error as NiivueError {
            return .failure(error)
        } catch {
            return .failure(.wrap(error, context: "VolumeLoadOperation.execute"))
        }
    }
}

// Usage: Build pipeline, execute later
let operations = [
    VolumeLoadOperation(url: "niivue://app/files/1", fileName: "brain.nii.gz"),
    VolumeLoadOperation(url: "niivue://app/files/2", fileName: "mask.nii.gz")
]

for operation in operations {
    let result = await operation.execute(using: webViewManager)
    if case .failure(let error) = result {
        print("Failed: \(error)")
        break
    }
}
```

---

## 6. Retry Logic

### 6.1 Exponential Backoff for WebView Initialization

```swift
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

    /// Initializes WebView with exponential backoff retry
    public func initialize(
        webViewManager: WebViewManager
    ) async throws {
        var lastError: NiivueError?

        for attempt in 0..<maxRetries {
            do {
                // Attempt to load
                webViewManager.load()

                // Wait for ready with timeout
                try await waitForReady(webViewManager: webViewManager, timeoutSeconds: 30.0)

                Logger.niivue.info("WebView initialized successfully on attempt \(attempt + 1)")
                return

            } catch let error as NiivueError {
                lastError = error

                // Don't retry non-transient errors
                guard error.isTransient else {
                    throw error
                }

                // Calculate backoff delay
                let delay = min(
                    initialDelaySeconds * pow(2.0, Double(attempt)),
                    maxDelaySeconds
                )

                Logger.niivue.warning(
                    "WebView initialization failed (attempt \(attempt + 1)/\(maxRetries)), retrying in \(delay)s: \(error)"
                )

                // Wait before retry
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // All retries exhausted
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

// Usage:
let initializer = WebViewInitializer(maxRetries: 3)
try await initializer.initialize(webViewManager: webViewManager)
```

### 6.2 Retry for Transient File Load Failures

```swift
extension WebViewManager {
    /// Loads a volume with automatic retry for transient failures
    public func loadVolumeWithRetry(
        url: String,
        fileName: String,
        maxRetries: Int = 2
    ) async throws {
        var lastError: NiivueError?

        for attempt in 0..<maxRetries {
            do {
                try await loadImageFromUrl(url: url, fileName: fileName)
                return
            } catch let error as NiivueError {
                lastError = error

                // Only retry transient errors
                guard error.isTransient else {
                    throw error
                }

                Logger.niivue.warning(
                    "Volume load failed (attempt \(attempt + 1)/\(maxRetries)): \(error)"
                )

                // Brief delay before retry
                if attempt < maxRetries - 1 {
                    try await Task.sleep(nanoseconds: 500_000_000) // 500ms
                }
            }
        }

        throw lastError ?? NiivueError.fileLoadFailed(fileName: fileName, reason: "Unknown error")
    }
}
```

### 6.3 Configurable Retry Policy

```swift
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
    /// Executes an async operation with retry according to policy
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

        throw lastError ?? NiivueError.operationTimeout(
            operation: "withRetry",
            timeoutSeconds: 0
        )
    }
}

// Usage:
try await Task.withRetry(policy: .default) {
    try await webViewManager.loadImageFromUrl(url: url, fileName: fileName)
}
```

---

## 7. Logging and Diagnostics

### 7.1 OSLog Integration

```swift
import os.log

extension Logger {
    /// Logger for NiivueKit operations
    static let niivue = Logger(subsystem: "com.niivue.niivuekit", category: "niivue")

    /// Logger for WebView bridge operations
    static let bridge = Logger(subsystem: "com.niivue.niivuekit", category: "bridge")

    /// Logger for file operations
    static let files = Logger(subsystem: "com.niivue.niivuekit", category: "files")

    /// Logger for DICOM operations
    static let dicom = Logger(subsystem: "com.niivue.niivuekit", category: "dicom")
}
```

### 7.2 Debug vs Release Logging Levels

```swift
extension Logger {
    /// Logs based on build configuration
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

// Usage:
extension WebViewManager {
    func loadImageFromUrl(url: String, fileName: String) async throws {
        Logger.bridge.debugLog("Loading volume: \(fileName) from \(url)")

        do {
            lastErrorMessage = nil
            volumes.removeAll()
            volumeSources = [.init(url: url, name: fileName)]

            let urlEscaped = try JavaScriptQuote.jsonStringLiteral(url)
            let nameEscaped = try JavaScriptQuote.jsonStringLiteral(fileName)

            _ = try await evaluator.callAsyncString(
                "return await window.loadImageFromUrl(\(urlEscaped), \(nameEscaped))"
            )

            Logger.files.info("Successfully loaded volume: \(fileName)")

        } catch {
            let niivueError = NiivueError.wrap(error, context: "loadImageFromUrl")

            Logger.files.errorWithContext(
                "Failed to load volume",
                error: niivueError,
                context: ["fileName": fileName, "url": url]
            )

            lastErrorMessage = niivueError.localizedDescription
            throw niivueError
        }
    }
}
```

### 7.3 Error Context Preservation

```swift
/// Context information for error diagnostics
public struct ErrorContext {
    public let operation: String
    public let timestamp: Date
    public let threadInfo: String
    public let additionalInfo: [String: String]

    public init(
        operation: String,
        additionalInfo: [String: String] = [:]
    ) {
        self.operation = operation
        self.timestamp = Date()
        self.threadInfo = Thread.current.description
        self.additionalInfo = additionalInfo
    }

    public var description: String {
        var lines = [
            "Operation: \(operation)",
            "Timestamp: \(timestamp)",
            "Thread: \(threadInfo)"
        ]

        if !additionalInfo.isEmpty {
            lines.append("Additional Info:")
            for (key, value) in additionalInfo.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(key): \(value)")
            }
        }

        return lines.joined(separator: "\n")
    }
}

extension NiivueError {
    /// Creates an error with diagnostic context
    public static func withContext(
        _ baseError: NiivueError,
        context: ErrorContext
    ) -> NiivueError {
        Logger.niivue.error("Error occurred:\n\(context.description)\n\(baseError)")
        return baseError
    }
}

// Usage:
do {
    try await loadVolume(url: url, fileName: fileName)
} catch {
    let context = ErrorContext(
        operation: "loadVolumeFromUserSelection",
        additionalInfo: [
            "fileName": fileName,
            "url": url,
            "volumeCount": "\(volumes.count)"
        ]
    )

    let error = NiivueError.wrap(error, context: "loadVolumeFromUserSelection")
    throw NiivueError.withContext(error, context: context)
}
```

### 7.4 Performance Logging

```swift
/// Measures and logs operation performance
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

// Usage:
func loadVolumeWithLogging(url: String, fileName: String) async throws {
    let perf = PerformanceLogger(operation: "loadVolume(\(fileName))")
    defer { perf.end(success: volumes.contains { $0.name == fileName }) }

    try await loadImageFromUrl(url: url, fileName: fileName)
}
```

---

## Summary

This design provides:

1. **Comprehensive Error Types**: `NiivueError` enum covers all failure modes with localized descriptions and recovery suggestions
2. **Async/Await Patterns**: Clear guidelines on when to use `async throws`, `async`, or fire-and-forget
3. **Cancellation Support**: Proper Task cancellation with cleanup and `CancellableOperation` wrapper
4. **Combine Integration**: Publishers for continuous events and one-shot operations with error handling
5. **Result Type Usage**: Callback-based APIs for UIKit compatibility alongside modern async APIs
6. **Retry Logic**: Exponential backoff for transient failures with configurable retry policies
7. **Logging and Diagnostics**: OSLog integration with context preservation and performance tracking

All patterns are designed to work seamlessly with the existing WKWebView bridge architecture while providing robust error handling and excellent developer experience.
