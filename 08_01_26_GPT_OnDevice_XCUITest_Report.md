# 08-01-26 On-Device XCUITest Report — NiiVue (Leandro’s iPhone)

**Date:** 2026-01-08  
**Updated:** 2026-01-09  
**Repo:** `niivue-ios-foundation` @ `2c8ffcd6c2e3f0b143e5f610ce031ef6235262d7`  
**Host:** macOS 26.1 (25B78), Xcode 26.2 (17C52)  
**Device:** “Leandro’s iPhone” (iOS 26.3), UDID `00008140-001664420413C01C`  

## Context / Scope

- CT Adaptive Engine is implemented end-to-end (TypeScript engine + Swift bridge + SwiftUI CT Presets sheet).
- On-device test runs validate both:
  - Existing core app behaviors (WebView readiness, volume loading, gestures, DICOM fixtures).
  - New CT Adaptive Engine flows (auto-apply flag injection, applying presets, and `ctPresetAnalysis` UI reporting).
- To avoid post-test diagnostics prompts during physical-device runs, all `xcodebuild test` commands use `-collect-test-diagnostics never`.

## Test Preparation (Device Fixture)

Some UI tests expect a KiTS23 DICOM series to already exist inside the app sandbox:

- Expected device path: `Documents/dicom-fixtures/VOLUME_MED_E_ABD_3`
- Host source used:
  - `/Users/leandroalmeida/Downloads/kits23-v1/src/kits23/workspace-kits23/TC_DA_PELVE/VOLUME_MED_E_ABD_3`

Copied fixture series into the app container:

```bash
xcrun devicectl device copy to \
  --device 00008140-001664420413C01C \
  --source /Users/leandroalmeida/Downloads/kits23-v1/src/kits23/workspace-kits23/TC_DA_PELVE/VOLUME_MED_E_ABD_3 \
  --domain-type appDataContainer \
  --domain-identifier com.niivue.mobile \
  --destination Documents/dicom-fixtures/VOLUME_MED_E_ABD_3 \
  --remove-existing-content true
```

## Smoke Run (Single Test)

Command:

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'platform=iOS,id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests/NiiVueUITests/testLaunchShowsPrimaryToolbarButtons \
  -derivedDataPath /tmp/NiiVueDerivedData-UI-Smoke-20260109 \
  -allowProvisioningUpdates \
  -collect-test-diagnostics never
```

Result:
- ✅ PASS — `NiiVueUITests.testLaunchShowsPrimaryToolbarButtons()` (on device)
- xcresult bundle:
  - `/tmp/NiiVueDerivedData-UI-Smoke-20260109/Logs/Test/Test-NiiVue-2026.01.09_00-06-48--0300.xcresult`

## Full On-Device UI Test Run

Command:

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'platform=iOS,id=00008140-001664420413C01C' \
  -only-testing:NiiVueUITests \
  -derivedDataPath /tmp/NiiVueDerivedData-NiiVueUITests-Device-20260109b \
  -allowProvisioningUpdates \
  -collect-test-diagnostics never
```

Result:
- ✅ **TEST SUCCEEDED**
- **Executed:** 30 tests
- **Failures:** 0
- **Skipped:** 1 (`testLaunchPerformance` is intentionally skipped on physical devices)
- xcresult bundle:
  - `/tmp/NiiVueDerivedData-NiiVueUITests-Device-20260109b/Logs/Test/Test-NiiVue-2026.01.09_00-08-02--0300.xcresult`

## Full On-Device Unit Test Run

Command:

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'platform=iOS,id=00008140-001664420413C01C' \
  -only-testing:NiiVueTests \
  -derivedDataPath /tmp/NiiVueDerivedData-NiiVueTests-Device-20260109 \
  -allowProvisioningUpdates \
  -collect-test-diagnostics never
```

Result:
- ✅ **TEST SUCCEEDED**
- **Executed:** 87 tests
- **Failures:** 0
- xcresult bundle:
  - `/tmp/NiiVueDerivedData-NiiVueTests-Device-20260109/Logs/Test/Test-NiiVue-2026.01.09_00-01-52--0300.xcresult`

## Coverage Highlights (What Was Exercised)

Representative coverage from `NiiVue/NiiVueUITests/NiiVueUITests.swift`:

- WebView boot + readiness signals (`niivue.isReady`, `niivue.volumeCount`, `niivue.lastError`, `niivue.lastJSLog`)
- Viewer interaction UX:
  - 2D stack scroll scrubs slices
  - two-finger pan updates offset
  - pinch zoom updates viewport scale
  - window/level gesture updates WW/WL without scrolling slices
- DICOM harness (fixture-driven, no DocumentPicker):
  - KiTS23 series loads and exposes volume count + status
  - missing fixture directory surfaces a user-visible failure and does not crash
  - post-load 2D interactions on real CT series (stack scroll + window/level)
- Sheet entry points:
  - Volumes / Segmentation / Sessions sheets open reliably and expose expected controls
- CT Adaptive Engine:
  - CT Presets sheet opens and can apply presets
  - `ctPresetAnalysis` is reported from JS → Swift and displayed in UI (`niivue.ctPresetAnalysis.phase`)
- Sessions save increments session count
- Launch tests in multiple orientations + appearances

## Notable Diagnostics / Warnings

- Repeated warning during device test runs:
  - `DVTDevice: Error locating DeviceSupport directory using Optional("arm64") or Optional("arm64e"): nilError`
  - Likely due to **device iOS 26.3** while host SDK is **iPhoneOS 26.2** (Xcode 26.2). Tests still executed successfully.
- Avoid interactive prompts: pass `-collect-test-diagnostics never` for physical-device runs.
- Observed once on an earlier run: `Timed out while enabling automation mode.` A retry succeeded. If this reappears:
  - Keep the device unlocked and awake during the entire run.
  - Start with the smoke test first, then run the full suite.

## Next Steps (If Additional CT Adaptive Engine Testing Is Desired)

- Add performance tests to benchmark the adaptive pipeline in WKWebView (targets are documented; measure on-device).
- Expand XCUITests to validate:
  - Auto-apply behavior when loading new volumes (`window.autoApplyCTPreset == true`)
  - Preset switching (adaptive vs fixed) and stability across multiple volumes
  - Failure/edge-case fallbacks (invalid windows, missing window functions, error surfaces)
