import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
// DICOM loader config per Ultimate Plan section 5.4 and packages/dicom-loader/README.md
export default defineConfig({
  plugins: [react()],
  base: './',
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
