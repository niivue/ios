# NiivueKit Error Handling - Quick Reference

**One-page cheat sheet for common error handling patterns**

---

## 1. Basic Error Handling

```swift
// Simple try-catch
do {
    try await webViewManager.loadVolume(url: url, fileName: fileName)
} catch let error as NiivueError {
    print("Error: \(error.localizedDescription)")
}
```

---

## 2. With Timeout

```swift
// Timeout after 30 seconds
try await Task.withTimeout(seconds: 30.0, operation: "loadVolume") {
    try await webViewManager.loadVolume(url: url, fileName: fileName)
}
```

---

## 3. With Retry

```swift
// Retry up to 3 times with exponential backoff
try await Task.withRetry(policy: .default) {
    try await webViewManager.loadVolume(url: url, fileName: fileName)
}

// Or use the robust variant (timeout + retry built-in)
try await webViewManager.loadVolumeRobust(url: url, fileName: fileName)
```

---

## 4. Cancellable Operation

```swift
class ViewModel {
    let operation = CancellableOperation<Void>()

    func startDicomLoading() async {
        try? await operation.start(timeout: 120.0) {
            try await webViewManager.loadDicomSeries(manifestUrl: url)
        }
    }

    func cancel() {
        operation.cancel()
    }
}
```

---

## 5. Fire-and-Forget (Settings)

```swift
// Settings that don't need error handling
Task {
    await webViewManager.setSliceType(.axial)
    await webViewManager.setColormap(volumeIndex: 0, colormap: "gray")
}
```

---

## 6. Combine Publisher

```swift
webViewManager
    .loadVolumePublisher(url: url, fileName: fileName)
    .sink(
        receiveCompletion: { completion in
            if case .failure(let error) = completion {
                self.showError(error)
            }
        },
        receiveValue: {
            print("Success")
        }
    )
    .store(in: &cancellables)
```

---

## 7. UIKit Callback

```swift
webViewManager.loadVolume(url: url, fileName: fileName) { result in
    switch result {
    case .success:
        self.showSuccess()
    case .failure(let error):
        self.showError(error)
    }
}
```

---

## 8. Error Classification

```swift
catch let error as NiivueError {
    if error.isTransient {
        // Retry button
    } else if error.isCancellation {
        // User cancelled - no alert needed
    } else {
        // Show error alert
    }
}
```

---

## 9. Error Alert (SwiftUI)

```swift
.alert("Error", isPresented: $showError, presenting: currentError) { error in
    Button("OK") { }

    if error.isTransient {
        Button("Retry") { retry() }
    }
} message: { error in
    Text(error.errorDescription ?? "Error")
    if let suggestion = error.recoverySuggestion {
        Text(suggestion).font(.caption)
    }
}
```

---

## 10. Logging

```swift
import os.log

// Info (success operations)
Logger.files.info("Loaded volume: \(fileName)")

// Debug (verbose, debug builds only)
Logger.bridge.debugLog("Evaluating JS: \(script)")

// Warning (recoverable errors)
Logger.niivue.warning("Retrying operation: \(error)")

// Error (unrecoverable failures)
Logger.files.error("Failed to load: \(error)")

// Error with context
Logger.files.errorWithContext(
    "Load failed",
    error: error,
    context: ["fileName": fileName, "url": url]
)
```

---

## Error Type Quick Reference

```swift
// JavaScript Bridge
.javaScriptEvaluationFailed(underlying: Error, script: String)
.javaScriptFunctionUnavailable(functionName: String)

// File Loading
.fileLoadFailed(fileName: String, reason: String?)
.fileNotFound(fileId: String)
.unsupportedFileFormat(fileName: String, extension: String)

// DICOM
.dicomConversionFailed(seriesId: String, reason: String?)
.dicomConversionTimeout(seriesId: String, timeoutSeconds: Double)

// WebView
.webViewInitializationTimeout(timeoutSeconds: Double)
.webViewNotReady

// Timeout
.operationTimeout(operation: String, timeoutSeconds: Double)

// Cancellation
.cancelled(operation: String)
```

---

## Retry Policies

```swift
// Default: 3 attempts, 1s initial delay, max 10s
RetryPolicy.default

// Aggressive: 5 attempts, 0.5s initial delay, max 5s
RetryPolicy.aggressive

// No retry: 1 attempt (fail fast)
RetryPolicy.noRetry

// Custom
RetryPolicy(
    maxAttempts: 3,
    initialDelay: 1.0,
    maxDelay: 10.0,
    shouldRetry: { error in
        (error as? NiivueError)?.isTransient ?? false
    }
)
```

---

## Common Patterns

### Pattern: WebView Initialization

```swift
let initializer = WebViewInitializer(maxRetries: 3)
try await initializer.initialize(webViewManager: webViewManager)
```

### Pattern: Load with Progress

```swift
// UIKit callback with progress
webViewManager.loadDicomSeries(
    manifestUrl: url,
    progress: { progress in
        self.progressBar.progress = Float(progress)
    },
    completion: { result in
        // Handle result
    }
)
```

### Pattern: Performance Logging

```swift
let perf = PerformanceLogger(operation: "loadVolume")
defer { perf.end(success: success) }

try await webViewManager.loadVolume(url: url, fileName: fileName)
```

### Pattern: Error Context

```swift
do {
    try await operation()
} catch {
    let context = ErrorContext(
        operation: "loadVolume",
        additionalInfo: ["fileName": fileName, "url": url]
    )
    throw NiivueError.withContext(.wrap(error, context: "operation"), context: context)
}
```

---

## SwiftUI Integration

```swift
struct ContentView: View {
    @StateObject var viewModel: NiivueViewModel
    @State private var currentError: NiivueError?

    var body: some View {
        VStack {
            // UI content
        }
        .task {
            do {
                try await viewModel.loadVolume(url: url, fileName: fileName)
            } catch let error as NiivueError {
                currentError = error
            }
        }
        .alert("Error", isPresented: .constant(currentError != nil), presenting: currentError) { error in
            Button("OK") { currentError = nil }
        } message: { error in
            Text(error.errorDescription ?? "Error")
        }
    }
}
```

---

## UIKit Integration

```swift
class ViewController: UIViewController {
    func loadVolume() {
        showLoadingIndicator()

        webViewManager.loadVolume(url: url, fileName: fileName) { [weak self] result in
            self?.hideLoadingIndicator()

            switch result {
            case .success:
                self?.showSuccess()
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
            alert.addAction(UIAlertAction(title: "Retry", style: .default) { _ in
                self.loadVolume()
            })
        }

        present(alert, animated: true)
    }
}
```

---

## Testing Patterns

```swift
// Test error description
func testErrorDescription() {
    let error = NiivueError.fileLoadFailed(fileName: "test.nii", reason: "Corrupted")
    XCTAssertEqual(error.errorDescription, "Failed to load test.nii: Corrupted")
}

// Test timeout
func testTimeout() async throws {
    do {
        try await Task.withTimeout(seconds: 0.1, operation: "test") {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        XCTFail("Expected timeout")
    } catch let error as NiivueError {
        XCTAssertTrue(error is NiivueError)
    }
}

// Test cancellation
func testCancellation() async throws {
    let operation = CancellableOperation<String>()

    let task = Task {
        try await operation.start {
            try await Task.sleep(nanoseconds: 10_000_000_000)
            return "done"
        }
    }

    try await Task.sleep(nanoseconds: 100_000_000)
    operation.cancel()

    do {
        _ = try await task.value
        XCTFail("Expected cancellation")
    } catch let error as NiivueError {
        XCTAssertTrue(error.isCancellation)
    }
}
```

---

## Performance Tips

1. Use timeout only for critical operations
2. Use fire-and-forget for settings
3. Use `.debugLog()` instead of `.debug()` (stripped in release)
4. Use `.noRetry` for operations that should fail fast
5. Batch settings updates to reduce bridge calls

---

## Troubleshooting

| Symptom | Likely Cause | Solution |
|---------|--------------|----------|
| "WebView not ready" | Called before initialization | Wait for `isReady` or use `readyPublisher` |
| Timeout errors | Operation taking too long | Increase timeout or check network |
| "File not found" | Invalid file ID | Check file was imported correctly |
| Promise rejected | JavaScript error | Check browser console logs |
| Cancellation errors | User cancelled | Normal - don't show error alert |

---

## Quick Start Checklist

- [ ] Add `NiivueError.swift` to project
- [ ] Add `Task+Timeout.swift` extension
- [ ] Add `Task+Retry.swift` extension
- [ ] Add `Logger+Niivue.swift` extensions
- [ ] Add `CancellableOperation.swift` wrapper
- [ ] Update `WebViewManager` with error handling
- [ ] Add error alerts to UI
- [ ] Write tests for error scenarios

---

## Resources

- **Full Design:** `ERROR_HANDLING_ASYNC_PATTERNS.md`
- **Examples:** `NiivueKit_ErrorHandling_Examples.swift`
- **Integration:** `INTEGRATION_GUIDE.md`
- **Summary:** `ERROR_HANDLING_SUMMARY.md`
