import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // The build is served to WKWebView over the app's own niivue-app:// scheme
  // (BundleSchemeHandler). Relative asset references keep it origin-agnostic, so
  // the same bundle also works from the dev server.
  base: './',
  // Serve the app's bundled sample volume during `npm run dev` so the page has
  // something to show without a native host. See the dev fallback in bridge.ts.
  publicDir: '../NiiVue/samples',
  build: {
    // Matches the app's IPHONEOS_DEPLOYMENT_TARGET (16.4).
    target: 'safari16',
    // ...but keep it OUT of dist/: Xcode copies `NiiVue/samples` into the app
    // bundle separately, and duplicating a 4 MB volume would bloat the app.
    copyPublicDir: false,
    rollupOptions: {
      // Two entries, one build. The app page and the Quick Look preview page are
      // separate documents but share NiiVue, so a multi-page build emits the
      // library once as a common chunk instead of duplicating ~1.3 MB of it into
      // both the app bundle and the extension bundle.
      input: {
        index: 'index.html',
        quicklook: 'quicklook.html',
      },
    },
  },
})
