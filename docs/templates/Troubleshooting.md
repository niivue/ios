# Troubleshooting Guide

This guide covers common issues when using NiivueKit and their solutions.

---

## Table of Contents

1. [WebGL and Rendering Issues](#webgl-and-rendering-issues)
2. [Memory Pressure and Crashes](#memory-pressure-and-crashes)
3. [File Access and Loading Errors](#file-access-and-loading-errors)
4. [DICOM Import Problems](#dicom-import-problems)
5. [JavaScript Bridge Errors](#javascript-bridge-errors)
6. [Performance Issues](#performance-issues)
7. [Build and Dependency Errors](#build-and-dependency-errors)
8. [Debug Techniques](#debug-techniques)

---

## WebGL and Rendering Issues

### Black Screen After Loading Volume

**Symptoms:**
- WebView loads successfully (`isReady = true`)
- Volume loads without error
- Screen remains black

**Possible Causes:**

1. **WebGL context not initialized**
   ```swift
   // Check console for WebGL errors
   webView.evaluateJavaScript("console.log(nv.gl)") { result, error in
       print("WebGL context: \(result ?? "null")")
   }
   ```

2. **Slice type issue**
   ```swift
   // Try forcing a specific view mode
   try await webViewManager.setSliceType(.multiplanar)
   try await webViewManager.setSliceType(.axial)
   ```

3. **Volume data corrupted**
   ```swift
   // Verify volume loaded correctly
   print("Loaded volumes: \(webViewManager.volumes.count)")
   print("Volume info: \(webViewManager.volumes)")
   ```

**Solution:**
```swift
// Force redraw after loading
try await webViewManager.loadVolumeFromURL(url)
try await Task.sleep(nanoseconds: 500_000_000) // 500ms delay
try await webViewManager.setSliceType(.multiplanar)
```

---

### WebGL Context Loss

**Symptoms:**
- App works initially
- After backgrounding/foregrounding, rendering stops
- Console shows "WebGL context lost"

**Cause:**
iOS aggressively reclaims GPU resources when apps are backgrounded.

**Solution:**

Add context restoration handling:

```swift
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    var webViewManager: WebViewManager?

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Save current state
        Task {
            await saveCurrentSession()
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Restore state
        Task { @MainActor in
            // Force WebView reload
            webViewManager?.webView.reload()

            // Wait for ready state
            while !(webViewManager?.isReady ?? false) {
                try await Task.sleep(nanoseconds: 100_000_000)
            }

            // Restore volumes
            await restoreSession()
        }
    }
}
```

**Alternative:** Use `WKWebView` configuration to prevent context loss:

```swift
let config = WKWebViewConfiguration()
config.suppressesIncrementalRendering = false
// Reduce memory pressure
config.limitsNavigationsToAppBoundDomains = true
```

---

### Rendering Performance Degradation

**Symptoms:**
- Initial rendering is smooth
- After loading multiple volumes, FPS drops
- Pinch/pan gestures become laggy

**Solutions:**

1. **Enable nearest-neighbor interpolation** (sacrifices quality for speed):
   ```swift
   try await webViewManager.evaluateCommand(
       "nv.setInterpolation(true)"  // true = nearest, false = linear
   )
   ```

2. **Limit maximum overlays**:
   ```swift
   // Only keep essential overlays
   while webViewManager.volumes.count > 3 {
       // Remove oldest overlay
       try await webViewManager.removeVolume(at: 1) // Keep base volume
   }
   ```

3. **Reduce texture quality** for older devices:
   ```swift
   let memory = ProcessInfo.processInfo.physicalMemory
   if memory < 4_000_000_000 {  // < 4GB RAM
       // Use device-specific optimizations
       try await webViewManager.evaluateCommand(
           "nv.setHighResolutionCapable(false)"
       )
   }
   ```

---

## Memory Pressure and Crashes

### Out-of-Memory Crashes

**Symptoms:**
- App crashes when loading large volumes
- Console shows memory warnings
- Crash log: `Exception Type: EXC_RESOURCE RESOURCE_TYPE_MEMORY`

**Diagnosis:**

Check volume size before loading:

```swift
func estimateMemoryUsage(for url: URL) throws -> Int64 {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let fileSize = attributes[.size] as? Int64 ?? 0

    // Uncompressed NIfTI ~= file size * 10 (for .nii.gz)
    // WebGL texture ~= uncompressed size * 4 (RGBA)
    return fileSize * 40
}

// Example usage
do {
    let memoryRequired = try estimateMemoryUsage(for: volumeURL)
    let availableMemory = getAvailableMemory()

    if memoryRequired > availableMemory {
        throw VolumeError.insufficientMemory(
            required: memoryRequired,
            available: availableMemory
        )
    }
} catch {
    // Show alert to user
}

func getAvailableMemory() -> Int64 {
    var vmStats = vm_statistics64()
    var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

    let kr = withUnsafeMutablePointer(to: &vmStats) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
            host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &size)
        }
    }

    guard kr == KERN_SUCCESS else { return 0 }

    let freeMemory = Int64(vmStats.free_count) * Int64(vm_page_size)
    return freeMemory
}
```

**Solutions:**

1. **Downsample large volumes before loading**:
   ```swift
   // Use external tool to downsample
   // Or load with custom stride parameter (if supported)
   ```

2. **Load in chunks** (for 4D volumes):
   ```swift
   // Load only specific timepoints
   try await webViewManager.setFrame4D(volumeIndex: 0, frame: 0)
   ```

3. **Clear unused volumes**:
   ```swift
   // Remove all but base volume
   while webViewManager.volumes.count > 1 {
       try await webViewManager.removeVolume(at: 1)
   }
   ```

---

### Memory Leaks

**Symptoms:**
- Memory usage grows continuously
- App becomes sluggish over time
- Eventually crashes

**Common Causes:**

1. **Retain cycles in script message handlers**

   ❌ **Wrong:**
   ```swift
   class MyHandler: NSObject, WKScriptMessageHandler {
       var manager: WebViewManager  // Strong reference

       func userContentController(...) {
           manager.handleMessage(...)  // Cycle!
       }
   }
   ```

   ✅ **Correct:**
   ```swift
   class MyHandler: NSObject, WKScriptMessageHandler {
       weak var manager: WebViewManager?  // Weak reference

       func userContentController(...) {
           manager?.handleMessage(...)
       }
   }
   ```

2. **Unclosed security-scoped resources**

   ❌ **Wrong:**
   ```swift
   func loadFile(_ url: URL) {
       url.startAccessingSecurityScopedResource()
       // File operations...
       // LEAK: Never stopped accessing
   }
   ```

   ✅ **Correct:**
   ```swift
   func loadFile(_ url: URL) {
       let accessing = url.startAccessingSecurityScopedResource()
       defer {
           if accessing {
               url.stopAccessingSecurityScopedResource()
           }
       }
       // File operations...
   }
   ```

**Debugging:**

Use Instruments to detect leaks:

```bash
# Open Instruments
xcodebuild -scheme NiivueKit -destination 'platform=iOS,name=YourDevice' \
    -resultBundlePath TestResults.xcresult

# Open Leaks instrument
open -a Instruments
# Select "Leaks" template
# Run your app and monitor memory growth
```

---

## File Access and Loading Errors

### "File Not Found" Despite Valid URL

**Symptoms:**
```
Error: The file "scan.nii" couldn't be opened because there is no such file.
```

**Cause:** Security-scoped resource access not started.

**Solution:**

Always use security-scoped access for document picker files:

```swift
.fileImporter(isPresented: $showingPicker, allowedContentTypes: [.data]) { result in
    Task {
        do {
            let fileURL = try result.get()

            // CRITICAL: Start access before reading
            let accessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            // Now safe to access file
            try await webViewManager.loadVolumeFromFile(fileURL)

        } catch {
            print("Error: \(error)")
        }
    }
}
```

---

### Corrupted File Data

**Symptoms:**
- Loading succeeds but rendering fails
- Console shows "Invalid NIfTI header"
- WebGL errors about texture dimensions

**Diagnosis:**

Validate NIfTI header before loading:

```swift
func validateNIfTI(at url: URL) throws -> Bool {
    let data = try Data(contentsOf: url, options: .mappedIfSafe)

    // Check for NIfTI magic number
    guard data.count >= 348 else {
        throw ValidationError.fileTooSmall
    }

    // NIfTI-1: header size should be 348
    let headerSize = data.withUnsafeBytes { $0.load(as: Int32.self) }
    guard headerSize == 348 else {
        throw ValidationError.invalidHeader(size: headerSize)
    }

    // Check magic string at offset 344
    let magicRange = 344..<348
    let magic = String(data: data[magicRange], encoding: .utf8)
    guard magic == "n+1\0" || magic == "ni1\0" else {
        throw ValidationError.invalidMagic(magic ?? "")
    }

    return true
}
```

---

## DICOM Import Problems

### DICOM Conversion Fails

**Symptoms:**
```
Error: dcm2niix conversion failed
```

**Possible Causes:**

1. **Missing DICOM tags**

   Check if files are valid DICOM:
   ```swift
   func isDICOM(_ url: URL) -> Bool {
       guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
           return false
       }

       // DICOM files start with 128-byte preamble + "DICM"
       guard data.count > 132 else { return false }
       let magic = data[128..<132]
       return magic == Data([0x44, 0x49, 0x43, 0x4D]) // "DICM"
   }
   ```

2. **Mixed series selected**

   Users might select files from different series. Add validation:
   ```swift
   actor DicomValidator {
       func validateSameSeries(_ urls: [URL]) async throws -> Bool {
           var seriesUIDs = Set<String>()

           for url in urls {
               // Parse SeriesInstanceUID from DICOM
               let seriesUID = try extractSeriesUID(from: url)
               seriesUIDs.insert(seriesUID)
           }

           guard seriesUIDs.count == 1 else {
               throw DicomError.mixedSeries(count: seriesUIDs.count)
           }

           return true
       }
   }
   ```

---

### WASM Loading Failures

**Symptoms:**
```
Error: Failed to load dcm2niix.wasm
```

**Cause:** Vite build configuration issue or missing WASM file.

**Solution:**

Verify `vite.config.ts` has correct settings:

```typescript
export default defineConfig({
  optimizeDeps: {
    exclude: ['@niivue/dcm2niix']  // Don't pre-bundle WASM
  },
  worker: {
    format: 'es'  // ES modules for workers
  }
})
```

Check that WASM file is included in bundle:

```bash
cd NiiVue/React
npm run build
ls -lh dist/assets/*.wasm  # Should show dcm2niix.wasm
```

---

## JavaScript Bridge Errors

### "JavaScript execution failed"

**Symptoms:**
```
Error: A JavaScript exception occurred
```

**Cause:** Syntax error in generated JavaScript or undefined variables.

**Debugging:**

Enable JavaScript error logging:

```swift
// In WebViewManager initialization
webView.evaluateJavaScript("""
    window.addEventListener('error', function(e) {
        window.webkit.messageHandlers.errorHandler.postMessage({
            message: e.message,
            source: e.filename,
            lineno: e.lineno,
            colno: e.colno
        });
    });
""")

// Add error handler
config.userContentController.add(errorMessageHandler, name: "errorHandler")
```

**Common Mistakes:**

1. **Unescaped quotes**:
   ```swift
   // ❌ Wrong
   try await evaluator.evaluateCommand(
       "nv.loadFromUrl(\"file://path with "quotes".nii\")"
   )

   // ✅ Correct
   let escaped = try JavaScriptQuote.jsonStringLiteral(url)
   try await evaluator.evaluateCommand(
       "nv.loadFromUrl(\(escaped))"
   )
   ```

2. **Calling methods before ready**:
   ```swift
   // ❌ Wrong
   try await webViewManager.setColormap(...)  // Might fail if not ready

   // ✅ Correct
   while !webViewManager.isReady {
       try await Task.sleep(nanoseconds: 100_000_000)
   }
   try await webViewManager.setColormap(...)
   ```

---

## Performance Issues

### Slow Initial Load Time

**Symptoms:**
- WebView takes >5 seconds to initialize
- "Initializing NiivueKit..." screen persists

**Solutions:**

1. **Preload WebView early**:
   ```swift
   @main
   struct MyApp: App {
       @StateObject private var webViewManager = WebViewManager()

       init() {
           // Start loading immediately
           Task { @MainActor in
               _ = webViewManager.webView  // Triggers initialization
           }
       }

       var body: some Scene {
           WindowGroup {
               ContentView()
                   .environmentObject(webViewManager)
           }
       }
   }
   ```

2. **Optimize React bundle size**:
   ```bash
   cd NiiVue/React
   npm run build -- --minify

   # Check bundle size
   ls -lh dist/assets/*.js
   # Should be <500KB gzipped
   ```

---

### Laggy Touch Response

**Symptoms:**
- Delay between tap and crosshair move
- Pan gestures feel sluggish

**Solutions:**

1. **Reduce touch event throttling**:
   ```javascript
   // In App.tsx
   nv.setOpts({
       dragMode: DRAG_MODE.pan,
       touchFactor: 0.5  // Lower = more responsive (but more CPU)
   })
   ```

2. **Disable unnecessary callbacks**:
   ```swift
   // Only enable location updates when needed
   try await webViewManager.evaluateCommand("""
       nv.onLocationChange = isDetailViewOpen ? handleLocationChange : null
   """)
   ```

---

## Build and Dependency Errors

### "No such module 'NiivueKit'"

**Cause:** Swift Package Manager dependency not resolved.

**Solution:**

```bash
# Reset package cache
rm -rf ~/Library/Developer/Xcode/DerivedData
rm -rf .build

# In Xcode
File → Packages → Reset Package Caches
File → Packages → Resolve Package Versions
```

---

### React Build Failures

**Symptoms:**
```
ERROR: Cannot find module '@niivue/dicom-loader'
```

**Solution:**

```bash
cd NiiVue/React

# Clean install
rm -rf node_modules package-lock.json
npm install

# Verify dependencies
npm list @niivue/dicom-loader
# Should show: @niivue/dicom-loader@0.2.0
```

---

## Debug Techniques

### Enable Verbose Logging

```swift
// In WebViewManager
func enableDebugLogging() async throws {
    try await evaluator.evaluateCommand("""
        nv.setOpts({ logging: true });
        console.log('NiivueKit debug logging enabled');
    """)
}
```

### Inspect WebView DOM

Enable Safari Web Inspector:

1. On device: **Settings → Safari → Advanced → Web Inspector**
2. On Mac: **Safari → Develop → [Your Device] → NiivueKit**

### Capture Network Traffic

Monitor file loading:

```swift
URLProtocol.registerClass(LoggingURLProtocol.self)

class LoggingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        print("📡 Loading: \(request.url?.absoluteString ?? "")")
        return false  // Don't intercept, just log
    }
}
```

### Profile Memory Usage

```swift
func logMemoryUsage() {
    var taskInfo = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
    let kr = withUnsafeMutablePointer(to: &taskInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }

    if kr == KERN_SUCCESS {
        let usedMemory = taskInfo.resident_size / 1024 / 1024  // MB
        print("💾 Memory usage: \(usedMemory) MB")
    }
}
```

---

## Still Having Issues?

### Community Support

- **GitHub Issues**: [Report a bug](https://github.com/niivue/niivue-ios-foundation/issues/new?template=bug_report.md)
- **Discussions**: [Ask for help](https://github.com/niivue/niivue-ios-foundation/discussions)
- **FAQ**: [Check common questions](FAQ.md)

### When Reporting Bugs

Please include:

1. **Environment**:
   - iOS version
   - Device model
   - Xcode version
   - NiivueKit version

2. **Reproducible steps**:
   - Minimal code example
   - Sample data (if applicable)
   - Expected vs actual behavior

3. **Logs**:
   - Console output
   - Crash reports (if applicable)
   - Screenshots/recordings

### Crash Report Template

```markdown
**Environment:**
- NiivueKit: 1.0.0
- iOS: 17.2
- Device: iPhone 15 Pro

**Steps to Reproduce:**
1. Load volume from URL
2. Switch to render mode
3. App crashes

**Expected:**
3D rendering appears

**Actual:**
App crashes with EXC_BAD_ACCESS

**Console Output:**
```
[error] WebGL context lost
Fatal error: Unexpectedly found nil
```

**Crash Log:**
[Attach .crash file from Xcode Organizer]
```

---

## Preventive Measures

### Use Error Boundaries

```swift
struct ErrorBoundary<Content: View>: View {
    @State private var error: Error?
    let content: () -> Content

    var body: some View {
        Group {
            if let error = error {
                ErrorView(error: error) {
                    self.error = nil
                }
            } else {
                content()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .niivueError)) { notification in
            if let err = notification.object as? Error {
                self.error = err
            }
        }
    }
}

// Usage
ErrorBoundary {
    NiivueViewer()
}
```

### Implement Health Checks

```swift
actor HealthChecker {
    func checkWebViewHealth(manager: WebViewManager) async -> HealthStatus {
        // Check if ready
        guard manager.isReady else {
            return .notReady
        }

        // Check if WebGL context is alive
        do {
            let result = try await manager.evaluator.evaluateCommand(
                "nv.gl !== null && !nv.gl.isContextLost()"
            )
            guard result == "true" else {
                return .contextLost
            }
        } catch {
            return .error(error)
        }

        return .healthy
    }
}

enum HealthStatus {
    case healthy
    case notReady
    case contextLost
    case error(Error)
}
```

---

**Last Updated:** January 4, 2026
**NiivueKit Version:** 1.0.0
