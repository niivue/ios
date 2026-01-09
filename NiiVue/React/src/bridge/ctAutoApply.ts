export function maybeAutoApplyAdaptiveCTUrinaryPreset(volumeIndex: number = 0): void {
  const anyWindow = window as any
  if (!anyWindow.autoApplyCTPreset) {
    return
  }

  const apply = anyWindow.applyAdaptiveCTUrinaryPreset
  if (typeof apply !== 'function') {
    return
  }

  apply(volumeIndex)
}

