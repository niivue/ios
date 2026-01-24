/// <reference types="vite/client" />

declare module '@niivue/dcm2niix-module' {
  const Module: (moduleArg?: unknown) => Promise<unknown>
  export default Module
}
