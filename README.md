# Niivue iOS

The Niivue iOS applications allow users to view, draw, and segment medical images in formats commonly used in medical research. 

The native components of the application are written in Swift, and the medical images are rendered using Niivue in a web view.

## Features

- View MRI/CT images in common formats used in medical research
- Draw and segment images (Apple Pencil is supported as a touch device)
- Save and load images from the local device (no data is sent to a server)
- Works in Airplane mode
- Customise viewing optons (e.g. window/level, zoom/pan, etc.)
- Multiple layouts supported
- Save drawings to Files app on iPhone/iPad

## macOS support

The Niivue iOS application is is primarily designed for iPhone and iPad, but it can also be run on macOS as long as the macOS machine has an Apple Silicon chip (ARM).

# App screenshots

## iPhone
![iphone](./screenshots/iphone.png)

# iPad
![ipad](./screenshots/ipad.png)

# MacOS
![macos](./screenshots/macos.png)

## Development - Getting Started

### Xcode

- Open `NiiVue/NiiVue.xcodeproj`
- Build/run on a physical device (the project’s test strategy assumes device-only for WebGL/WKWebView reliability)

### Documentation

- `docs/INDEX.md` — NiivueKit architecture + SPM package design docs
- `00_START_HERE.txt` — Niivue API inventory overview (what’s wrapped vs missing)
- `INTEGRATION_GUIDE.md` — Error handling + async patterns integration checklist

### Device Fixtures (DICOM + Segmentations)

Copy the local fixture folder into the app’s Documents container on a physical device:

```bash
scripts/copy-test-ct-volumes-to-device.sh <DEVICE_UDID>
```

Defaults:
- `DEVICE_UDID=00008140-001664420413C01C` (Leandro’s iPhone)
- `BUNDLE_ID=com.niivue.mobile`

### On-Device UI Tests (no simulator)

```bash
xcodebuild test \
  -project NiiVue/NiiVue.xcodeproj \
  -scheme NiiVue \
  -destination 'platform=iOS,id=<DEVICE_UDID>' \
  -only-testing:NiiVueUITests \
  -allowProvisioningUpdates \
  -collect-test-diagnostics never
```
