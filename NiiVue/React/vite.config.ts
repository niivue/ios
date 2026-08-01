import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  // The build is loaded by WKWebView from a file:// URL, so every asset
  // reference has to be relative rather than server-absolute.
  base: './',
  build: {
    // Matches the app's IPHONEOS_DEPLOYMENT_TARGET (16.4).
    target: 'safari16',
  },
})
