import { useEffect, useRef } from 'react'
import { startNiiVue } from './bridge'
import './App.css'

export default function App() {
  const containerRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const container = containerRef.current
    if (!container) {
      return
    }
    // The canvas is created imperatively rather than rendered by React: when
    // WebGPU is unavailable NiiVue falls back to WebGL2 by swapping in a fresh
    // canvas element, which would strand a React-owned ref.
    const canvas = document.createElement('canvas')
    canvas.className = 'niivue-canvas'
    container.appendChild(canvas)

    let teardown: (() => void) | undefined
    let cancelled = false

    startNiiVue(canvas, () => cancelled)
      .then((dispose) => {
        if (cancelled) {
          dispose()
        } else {
          teardown = dispose
        }
      })
      .catch((err: unknown) => {
        console.error('NiiVue failed to start', err)
      })

    return () => {
      cancelled = true
      teardown?.()
      container.replaceChildren()
    }
  }, [])

  return <div ref={containerRef} className="niivue-container" />
}
