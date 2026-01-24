import { describe, expect, test, vi } from 'vitest'

import { maybeAutoApplyAdaptiveCTUrinaryPreset } from './ctAutoApply'

describe('maybeAutoApplyAdaptiveCTUrinaryPreset', () => {
  test('calls window.applyAdaptiveCTUrinaryPreset(0) when window.autoApplyCTPreset is true', () => {
    const anyWindow = window as any
    anyWindow.autoApplyCTPreset = true
    anyWindow.applyAdaptiveCTUrinaryPreset = vi.fn()

    maybeAutoApplyAdaptiveCTUrinaryPreset(0)

    expect(anyWindow.applyAdaptiveCTUrinaryPreset).toHaveBeenCalledWith(0)
  })

  test('does nothing when window.autoApplyCTPreset is false', () => {
    const anyWindow = window as any
    anyWindow.autoApplyCTPreset = false
    anyWindow.applyAdaptiveCTUrinaryPreset = vi.fn()

    maybeAutoApplyAdaptiveCTUrinaryPreset(0)

    expect(anyWindow.applyAdaptiveCTUrinaryPreset).not.toHaveBeenCalled()
  })
})

