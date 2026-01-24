import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath } from 'node:url'

// https://vitejs.dev/config/
// DICOM loader config per Ultimate Plan section 5.4 and packages/dicom-loader/README.md
export default defineConfig({
  plugins: [react()],
  base: './',
  resolve: {
    alias: {
      // The `@niivue/dcm2niix` package uses an `exports` map that doesn't expose the Emscripten module entrypoint.
      // We alias it to a concrete file path so we can run dcm2niix on the main thread in WKWebView (no Worker).
      '@niivue/dcm2niix-module': fileURLToPath(
        new URL('./node_modules/@niivue/dcm2niix/dist/dcm2niix.jpeg.js', import.meta.url)
      ),
    },
  },
  optimizeDeps: {
    exclude: ['@niivue/dcm2niix']  // Required for WASM
  },
  worker: {
    format: 'es'  // Required for DICOM loader worker
  },
  build: {
    target: 'es2020'  // Match tsconfig.json target
  }
})
