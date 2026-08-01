# NiiVue web viewer

The rendering half of the NiiVue iOS app: a React + Vite + TypeScript page that
hosts [`@niivue/niivue`](https://www.npmjs.com/package/@niivue/niivue) on a
single canvas. The SwiftUI app loads the production build (`dist/index.html`)
into a `WKWebView` from a `file://` URL — there is no server and no network
access at runtime.

## Scripts

```bash
npm install
npm run dev      # Vite dev server (open in a desktop browser)
npm run build    # tsc -b && vite build -> ./dist, which Xcode copies into the app
npm run lint
```

`NiiVue.xcodeproj` runs `npm run build` in a build phase, so an Xcode build
picks up source changes automatically.

## The native bridge

[`src/bridge.ts`](src/bridge.ts) is the whole contract with the host app. It
installs `window.niivueBridge` — the functions `WebViewManager` (in
`../NiiVue/ContentView.swift`) calls — and posts events back through
`window.webkit.messageHandlers`:

| Channel | Meaning |
| --- | --- |
| `updateUI` | NiiVue is attached and `window.niivueBridge` exists. The app waits for this before sending anything. |
| `locationChange` | Crosshair moved; payload is the JSON mm coordinate array. |
| `logMessage` | Diagnostics for the Xcode console. |

Two calls are asynchronous and the Swift side invokes them with
`callAsyncJavaScript`: `loadBase64Image` and `saveDrawing` (which returns a
base64 `.nii.gz`).

Outside a `WKWebView` the `postToHost` calls are no-ops, so `npm run dev` works
in a normal browser; drive it from the devtools console, e.g.
`niivueBridge.setSliceType(0)`.

## Notes

- The canvas is created imperatively in [`src/App.tsx`](src/App.tsx) rather than
  rendered by React. When WebGPU is unavailable NiiVue falls back to WebGL2 by
  swapping in a fresh canvas element, which would strand a React-owned ref.
- `vite.config.ts` sets `base: './'` because the page is loaded over `file://`.
