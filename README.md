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

The app is a SwiftUI shell around a `WKWebView` that renders with
[NiiVue](https://github.com/niivue/niivue). The web viewer lives in
[`NiiVue/React`](NiiVue/React) and is documented in its own
[README](NiiVue/React/README.md).

Requirements: Xcode with the iOS platform installed, and Node.js 20.19+ (for
the Vite 8 build).

```bash
cd NiiVue/React
npm install
npm run build     # produces NiiVue/React/dist, which the app bundles
```

Then open `NiiVue/NiiVue.xcodeproj` and run. An Xcode build phase re-runs
`npm run build`, so `npm install` only has to be done once.

To iterate on the viewer without rebuilding the app, `npm run dev` serves it in
a desktop browser; the native bridge degrades to no-ops there and the viewer can
be driven from the devtools console (`niivueBridge.setSliceType(0)`).