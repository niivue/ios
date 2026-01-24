# NiiVue API Inventory - Document Index

**Generated:** January 4, 2026
**Purpose:** Complete API mapping and implementation roadmap for NiiVue iOS Foundation

---

## Documents in This Inventory

### 1. **NIIVUE_API_INVENTORY.md** (24 KB)
**Comprehensive implementation guide**

- Complete listing of all 202 methods + 25 callbacks + 100+ configuration options
- Organized by 11 categories (Volume Loading, Mesh Loading, Drawing, View Control, etc.)
- For EACH API:
  - Category, method name, Swift wrapper status, complexity, priority
  - Implementation phase assignment
  - Estimated effort in days
  - Estimated test count
- Implementation roadmap by phase (Phase 3-8+)
- Complexity analysis (Low/Medium/High)
- Priority justification (P0/P1/P2)
- Testing strategy
- Implementation templates
- Success criteria
- Full timeline: 25-30 days to ~100% feature parity

**Use Case:** Detailed reference during implementation; guides every method

---

### 2. **API_INVENTORY.csv** (10 KB)
**Machine-readable implementation tracking**

- 202 rows (one per method)
- 8 columns: Category, Method, Swift Wrapper Needed, Complexity, Priority, Phase, Phase Name, Effort, Estimated Tests
- Sortable by phase, priority, complexity, effort
- Import into spreadsheet for tracking progress

**Use Case:** Track progress; generate burn-down charts; filter by priority

---

### 3. **API_INVENTORY_SUMMARY.txt** (14 KB)
**Executive summary and critical insights**

- Quick stats: 202 methods, 12% wrapped, 88% pending
- All 37 P0 (critical) methods listed
- Phase 3 roadmap (3-5 days)
- High-value quick wins (8 methods, 2-3 days)
- Complexity breakdown (Low 47%, Medium 41%, High 12%)
- Critical insights:
  - Intensity windowing is missing from Niivue (needs custom bridge)
  - Callback integration is 90% missing (Phase 7 task)
  - Coordinate transforms essential for measurements (Phase 4 task)
  - Configuration via setOpts() critical for UX
  - Quick wins available for momentum building
- Next steps and success criteria

**Use Case:** Executive briefing; project planning; decision-making

---

## Implementation Phases at a Glance

### Phase 1: Basic Foundation ✓
- 12 methods (6%)
- Status: **COMPLETE**

### Phase 2: DICOM Import ✓
- 12 methods (6%)
- Status: **COMPLETE** (3 commits, 77 tests)

### Phase 3: Core Volume Control (NEXT)
- **37 P0 methods** (18%)
- **Timeline: 3-5 days**
- **Methods:**
  - Volume removal (2)
  - 3D rendering (3)
  - View configuration (12)
  - Colormap & opacity (4)
  - Drawing basics (3)
  - Initialization (3)
  - Callbacks (2)

### Phase 4: Navigation & Measurement
- 19 methods (9%)
- Timeline: 3-4 days
- Focus: Coordinate transforms, distance/angle tools, measurement UI

### Phase 5: Drawing & Segmentation
- 15 methods (7%)
- Timeline: 2-3 days
- Focus: Advanced segmentation algorithms, undo/redo

### Phase 6: Advanced Features
- 15 methods (7%)
- Timeline: 4-6 days
- Focus: Mesh, export, settings persistence

### Phase 7: Event System Integration
- 12 methods (6%)
- Timeline: 2-3 days
- Focus: Callback wiring, configuration batching

### Phase 8+: Remaining Methods
- 130+ methods (64%)
- Timeline: 10+ days
- Focus: P2 nice-to-have features

---

## API Categories Summary

| Category | Methods | Wrapped | P0 | P1 | P2 | Phase |
|----------|---------|---------|----|----|----|----|
| Initialization | 8 | 3 | 3 | 1 | 4 | 3 |
| Volume Loading | 18 | 6 | 6 | 8 | 4 | 3 |
| Mesh Loading | 15 | 1 | 0 | 0 | 15 | 6 |
| Drawing | 21 | 4 | 3 | 2 | 16 | 5 |
| View Control | 30 | 12 | 12 | 10 | 8 | 3-4 |
| Colormap | 11 | 3 | 4 | 3 | 4 | 3 |
| Measurement | 10 | 0 | 0 | 4 | 6 | 4 |
| Export | 8 | 1 | 0 | 1 | 7 | 6 |
| Events | 25 | 2 | 2 | 8 | 15 | 7 |
| Coordinates | 12 | 0 | 0 | 8 | 4 | 4 |
| Configuration | 100+ | 0 | 0 | 20+ | 80+ | 7 |
| **TOTAL** | **202+** | **24** | **37** | **89** | **76** | Mixed |

---

## Priority Distribution

### P0: Critical for MVP (37 methods - 18%)
**Cannot ship without these**

Breakdown:
- Volume Control: 6 methods
- 3D Rendering: 3 methods
- View Configuration: 12 methods
- Colormap & Opacity: 4 methods
- Drawing: 3 methods
- Initialization: 3 methods
- Callbacks: 2 methods

**All must be implemented in Phase 3.**

### P1: Important for Complete Experience (89 methods - 44%)
**Significantly enhances user experience**

Breakdown:
- Coordinate Transforms: 8 methods (essential for measurements)
- Measurement Tools: 4 methods
- View Enhancements: 10 methods
- Volume Management: 8 methods
- Settings/Config: 20+ methods
- Event Callbacks: 8 methods
- Export/Import: 1 method

**Target: 70% implementation across Phases 4-7**

### P2: Nice-to-Have Features (76 methods - 38%)
**Power user features, specialized workflows**

Breakdown:
- Mesh Operations: 15 methods (specialized, low demand)
- Advanced Drawing: 16 methods (Otsu, GrowCut, etc.)
- Advanced UI: 8 methods (custom layouts, etc.)
- Export/Document: 7 methods
- Event Callbacks: 15 methods
- Advanced Config: 80+ options

**Target: Implement as time permits in Phases 6+**

---

## Complexity Distribution

### Low Complexity: 94 methods (47%)
**Simple pass-through or direct property access**

Examples:
- `removeVolumeByIndex()` - 1-line method
- `setCrosshairWidth()` - simple setter
- `clearMeasurements()` - simple call
- Coordinate transforms - math functions

**Effort:** 0.25-0.5 days each
**Tests:** 1-2 per method
**Total:** 47 days to implement all

### Medium Complexity: 82 methods (41%)
**Data transformation or state management**

Examples:
- `loadVolumes()` - URL scheme setup
- `moveVolumeUp()` - array state
- `onLocationChange` - callback parsing
- `exportViewerState()` - serialization

**Effort:** 0.5-1 day each
**Tests:** 2-3 per method
**Total:** 82 days to implement all

### High Complexity: 26 methods (12%)
**Complex workflows, algorithms, state machines**

Examples:
- `loadDicoms()` - WASM + files
- `loadConnectome()` - complex parsing
- `drawGrowCut()` - algorithm
- `setCustomLayout()` - system design
- `onOptsChange` - cascading updates

**Effort:** 1-2 days each
**Tests:** 3-5 per method
**Total:** 26-52 days to implement all

---

## Quick Implementation Wins (Phase 3 Momentum)

These 8 methods can each be completed in <0.5 days:

1. **`removeVolumeByIndex()`** - Simple array access
2. **`getVolumeIndexByID()`** - Property lookup
3. **`setCrosshairWidth()`** - Simple setter
4. **`clearMeasurements()`** - Simple method call
5. **`clearAngles()`** - Simple method call
6. **`mm2frac()`** - Math function
7. **`frac2mm()`** - Math function
8. **`vox2frac()`** - Math function

**Total effort:** 2-3 days to implement all 8
**Tests needed:** 8-12
**Recommendation:** Implement these first to build momentum

---

## Critical Missing Features

### 1. Intensity Windowing (P0)
**Status:** Not exposed in Niivue public API
**Solution:** Create custom wrapper
```typescript
export function setIntensityWindow(nv, volumeIndex, min, max) {
    nv.volumes[volumeIndex].cal_min = min
    nv.volumes[volumeIndex].cal_max = max
    nv.updateGLVolume()
}
```
**Importance:** CRITICAL - Cannot diagnose medical images without this

### 2. Callback Integration (P1/P2)
**Status:** 23 of 25 callbacks not wired to Swift
**Solution:** Systematic bidirectional communication via `postToIOS()`
**Phase:** Phase 7 (2-3 days)

### 3. Configuration Persistence (P1)
**Status:** No way to persist user settings
**Solution:** `getOpts()` + `setOpts()` + UserDefaults
**Importance:** HIGH - Users expect settings to persist

---

## File Structure

```
/Users/leandroalmeida/niivue-ios-foundation/
├── NIIVUE_API_INVENTORY.md          (24 KB - Comprehensive guide)
├── API_INVENTORY.csv                (10 KB - Machine-readable)
├── API_INVENTORY_SUMMARY.txt        (14 KB - Executive summary)
└── API_INVENTORY_INDEX.md           (This file)
```

---

## How to Use These Documents

### For Project Managers / Leads
1. Read **API_INVENTORY_SUMMARY.txt**
2. Review Phase 3 roadmap
3. Use CSV for burn-down tracking
4. Success metric: 37 P0 methods in 3-5 days

### For Developers
1. Start with **API_INVENTORY.md** for your assigned phase
2. Reference CSV for sorting/filtering
3. Implement following templates provided
4. Update CSV to track progress

### For Testing / QA
1. Use CSV to understand test requirements
2. Reference NIIVUE_API_INVENTORY.md for test coverage details
3. Track tests per method (1-5 tests typical)
4. Success metric: 320-400 total tests across all phases

---

## Next Steps

1. **Review** these documents (30 minutes)
2. **Approve** Phase 3 roadmap and 37 P0 methods
3. **Schedule** Phase 3 sprint (3-5 days)
4. **Assign** developers to quick-win methods (parallel work)
5. **Begin** TDD: Write failing test → implement → verify
6. **Track** progress via CSV
7. **Celebrate** MVP parity after Phase 3!

---

## Statistics Summary

| Metric | Count |
|--------|-------|
| Total APIs | 327+ |
| Total Methods | 202 |
| Total Callbacks | 25 |
| Configuration Options | 100+ |
| Methods Wrapped (Phase 1-2) | 24 (12%) |
| Methods Pending | 178 (88%) |
| P0 Methods (MVP) | 37 (18%) |
| P1 Methods (Experience) | 89 (44%) |
| P2 Methods (Features) | 76 (38%) |
| Low Complexity | 94 (47%) |
| Medium Complexity | 82 (41%) |
| High Complexity | 26 (12%) |
| Estimated Total Dev Time | 25-30 days |
| Estimated Total Tests | 320-400 |
| Phase 3 Timeline | 3-5 days |
| Full Feature Parity | 8-10 weeks |

---

## Contact & Questions

For implementation questions, reference:
- **Detailed methods:** NIIVUE_API_INVENTORY.md
- **Quick lookup:** API_INVENTORY.csv
- **Strategic planning:** API_INVENTORY_SUMMARY.txt
- **Project status:** API_INVENTORY.csv (progress tracking)

---

*Inventory Generated: January 4, 2026*
*Source: Phase 2 Report - Appendix A*
*Total Lines Analyzed: 11,868+ (main Niivue class)*
