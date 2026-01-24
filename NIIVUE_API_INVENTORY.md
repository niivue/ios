# Complete NiiVue API Inventory

**Generated:** January 4, 2026
**Source:** Phase 2 Report - Appendix A (Complete Niivue API Reference)
**Purpose:** Drive Phase 3+ implementation roadmap for NiiVue iOS Foundation

---

## Summary Statistics

### Total APIs
- **Total Methods:** 202
- **Total Callbacks:** 25
- **Total Configuration Options:** 100+
- **Grand Total:** 327+

### Swift Wrapper Status
- **Methods Needing Wrappers:** 178 (88%)
- **Methods with Wrappers:** 24 (12%)
- **Callbacks Needing Wrappers:** 23 (92%)
- **Callbacks with Wrappers:** 2 (8%)

### Priority Breakdown
- **P0 (Critical):** 37 methods (18%)
- **P1 (Important):** 89 methods (44%)
- **P2 (Nice-to-Have):** 76 methods (38%)

### Complexity Breakdown
- **Low (Simple Pass-Through):** 94 methods (47%)
- **Medium (Data Transformation):** 82 methods (41%)
- **High (State Management):** 26 methods (12%)

---

## Detailed API Inventory

### Category 1: Initialization & Lifecycle (8 methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| Initialization | `constructor(options?: NVConfigOptions)` | No (Via React) | High | P0 |
| Initialization | `attachTo(id: string)` | No (Via React) | High | P0 |
| Initialization | `attachToCanvas(canvas: HTMLCanvasElement)` | No (Via React) | High | P0 |
| Initialization | `setOpts(options: Partial<NVConfigOptions>)` | Yes | Medium | P0 |
| Initialization | `getOpts()` | Yes | Medium | P1 |
| Initialization | `resize()` | No (Automatic) | Low | P1 |
| Initialization | `dispose()` | Yes | Medium | P2 |
| Initialization | `drawScene()` | Yes | Low | P1 |

---

### Category 2: Volume Loading (20+ methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| Volume Loading | `loadVolumes(volumeList: NVImage[])` | Partial | Medium | P0 |
| Volume Loading | `loadFromUrl(url: string, ...)` | Partial | Medium | P0 |
| Volume Loading | `loadFromFile(file: File, ...)` | Partial | Medium | P0 |
| Volume Loading | `loadFromBase64(base64: string, ...)` | Partial | Medium | P0 |
| Volume Loading | `addVolumesFromUrl(urls: string[])` | Partial | Medium | P0 |
| Volume Loading | `loadDicoms(files: ...)` | Partial | Medium | P0 |
| Volume Loading | `removeVolume(volume: NVImage)` | Yes | Low | P0 |
| Volume Loading | `removeVolumeByIndex(index: number)` | Yes | Low | P0 |
| Volume Loading | `removeVolumeByUrl(url: string)` | Yes | Low | P1 |
| Volume Loading | `setVolume(volume: NVImage, toIndex: number)` | Yes | Low | P1 |
| Volume Loading | `moveVolumeToTop(volume: NVImage)` | Yes | Low | P1 |
| Volume Loading | `moveVolumeToBottom(volume: NVImage)` | Yes | Low | P2 |
| Volume Loading | `moveVolumeUp(volume: NVImage)` | Yes | Low | P1 |
| Volume Loading | `moveVolumeDown(volume: NVImage)` | Yes | Low | P1 |
| Volume Loading | `cloneVolume(index: number)` | Yes | Medium | P2 |
| Volume Loading | `getVolumeIndexByID(id: string)` | Yes | Low | P1 |
| Volume Loading | `updateGLVolume()` | No (Internal) | Low | N/A |
| Volume Loading | `refreshVolumes()` | Yes | Low | P1 |

---

### Category 3: Mesh Loading (18+ methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| Mesh Loading | `loadMeshes(meshList: NVMesh[])` | Yes | Medium | P2 |
| Mesh Loading | `addMesh(mesh: NVMesh)` | Yes | Medium | P2 |
| Mesh Loading | `addMeshFromUrl(url: string, ...)` | Yes | Medium | P2 |
| Mesh Loading | `removeMesh(mesh: NVMesh)` | Yes | Low | P2 |
| Mesh Loading | `removeMeshByUrl(url: string)` | Yes | Low | P2 |
| Mesh Loading | `setMesh(mesh: NVMesh, toIndex: number)` | Yes | Low | P2 |
| Mesh Loading | `getMeshIndexByID(id: string)` | Yes | Low | P2 |
| Mesh Loading | `setMeshProperty(id: string, key: string, val: any)` | Yes | Medium | P2 |
| Mesh Loading | `setMeshLayerProperty(...)` | Yes | Medium | P2 |
| Mesh Loading | `setMeshShader(id: string, shaderName: string)` | Yes | Low | P2 |
| Mesh Loading | `meshShaderNames()` | Yes | Low | P2 |
| Mesh Loading | `reverseFaces(mesh: NVMesh)` | Yes | Low | P2 |
| Mesh Loading | `loadConnectome(json: object)` | Yes | High | P2 |
| Mesh Loading | `loadConnectomeFromUrl(url: string)` | Yes | High | P2 |
| Mesh Loading | `loadFreeSurferConnectome(json: object)` | Yes | High | P2 |

---

### Category 4: Drawing & Segmentation (25+ methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| Drawing | `setPenValue(value: number, isFilled?: boolean)` | Partial | Low | P0 |
| Drawing | `setDrawOpacity(opacity: number)` | Partial | Low | P0 |
| Drawing | `setDrawColormap(name: string)` | Partial | Low | P0 |
| Drawing | `createEmptyDrawing()` | Yes | Low | P1 |
| Drawing | `closeDrawing()` | Yes | Low | P1 |
| Drawing | `loadDrawing(bitmap: Uint8Array)` | Yes | Medium | P2 |
| Drawing | `loadDrawingFromUrl(url: string)` | Yes | Medium | P2 |
| Drawing | `saveDrawing()` | Partial | Medium | P0 |
| Drawing | `drawUndo()` | Partial | Low | P0 |
| Drawing | `drawPt(x: number, y: number, z: number, value: number)` | No (Internal) | Low | N/A |
| Drawing | `drawPenLine(...)` | No (Internal) | Low | N/A |
| Drawing | `drawRectangleMask(...)` | No (Internal) | Low | N/A |
| Drawing | `drawEllipseMask(...)` | No (Internal) | Low | N/A |
| Drawing | `drawFloodFill(...)` | No (Internal) | Low | N/A |
| Drawing | `drawOtsu(levels: number)` | Yes | High | P2 |
| Drawing | `drawGrowCut()` | Yes | High | P2 |
| Drawing | `findOtsu(mlevel: number)` | Yes | Medium | P2 |
| Drawing | `removeHaze(level: number)` | Yes | Medium | P2 |
| Drawing | `binarize(volume: NVImage)` | Yes | Medium | P2 |
| Drawing | `drawClearAllUndoBitmaps()` | Yes | Low | P2 |
| Drawing | `setClickToSegmentEnabled(enabled: boolean)` | Partial | Low | P0 |

---

### Category 5: View Manipulation (30+ methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| View Control | `setSliceType(st: SLICE_TYPE)` | Partial | Low | P0 |
| View Control | `setRenderAzimuthElevation(a: number, e: number)` | Yes | Low | P0 |
| View Control | `setClipPlane(depthAziElev: number[])` | Yes | Low | P1 |
| View Control | `setClipPlanes(planes: number[][])` | Yes | Low | P1 |
| View Control | `setClipPlaneColor(color: number[])` | Yes | Low | P2 |
| View Control | `setPan2Dxyzmm(xyzmmZoom: vec4)` | Yes | Medium | P1 |
| View Control | `setZoom(volScaleMultiplier: number)` | Yes | Low | P0 |
| View Control | `moveCrosshairInVox(i: number, j: number, k: number)` | Partial | Low | P0 |
| View Control | `setCrosshairColor(color: number[])` | Partial | Low | P0 |
| View Control | `setCrosshairWidth(width: number)` | Yes | Low | P1 |
| View Control | `setInterpolation(isNearest: boolean)` | Yes | Low | P0 |
| View Control | `setAtlasOutline(isOutline: boolean)` | Yes | Low | P1 |
| View Control | `setGamma(gamma: number)` | Yes | Low | P1 |
| View Control | `setScale(scale: number)` | Yes | Low | P2 |
| View Control | `setLayout(layout: number)` | Partial | Low | P0 |
| View Control | `setRadiologicalConvention(isRad: boolean)` | Partial | Low | P0 |
| View Control | `setCornerText(isCorners: boolean)` | Partial | Low | P0 |
| View Control | `setOrientationCube(isVisible: boolean)` | Partial | Low | P0 |
| View Control | `set3dCrosshairVisible(visible: boolean)` | Partial | Low | P0 |
| View Control | `set2dCrosshairVisible(visible: boolean)` | Partial | Low | P0 |
| View Control | `setDragMode(mode: DRAG_MODE)` | Partial | Low | P0 |
| View Control | `setVolumeRenderIllumination(amount: number)` | Yes | Low | P1 |
| View Control | `setGradientOpacity(opacity: number)` | Yes | Low | P1 |
| View Control | `setCustomLayout(layout: object)` | Yes | High | P2 |
| View Control | `clearCustomLayout()` | Yes | Low | P2 |
| View Control | `setSliceMM(isMM: boolean)` | Yes | Low | P2 |
| View Control | `setAdditiveBlend(isAdditive: boolean)` | Yes | Low | P1 |
| View Control | `setHeroImage(fraction: number)` | Yes | Medium | P2 |
| View Control | `setMultiplanarPadPixels(pixels: number)` | Yes | Low | P2 |
| View Control | `setSelectionBoxColor(color: number[])` | Yes | Low | P2 |

---

### Category 6: Colormap Methods (12 methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| Colormap | `setColormap(id: string, colormap: string)` | Partial | Low | P0 |
| Colormap | `setColormapNegative(id: string, colormap: string)` | Yes | Low | P1 |
| Colormap | `setColormapLabel(id: string, cm: ColorMap)` | Yes | Medium | P2 |
| Colormap | `setOpacity(id: string, opacity: number)` | Partial | Low | P0 |
| Colormap | `listColormaps()` | Partial | Low | P0 |
| Colormap | `setModulationImage(idTarget: string, idMod: string)` | Yes | Medium | P2 |
| Colormap | `refreshColormaps()` | Yes | Low | P1 |
| Colormap | `colormapFromKey(key: string)` | Yes | Low | P1 |
| Colormap | `addColormap(key: string, cmap: ColorMap)` | Yes | Medium | P2 |
| Colormap | `removeColormap(key: string)` | Yes | Low | P2 |
| Colormap | `setColormapInvert(id: string, invert: boolean)` | Yes | Low | P1 |

---

### Category 7: Measurement Tools (10 methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| Measurement | `clearMeasurements()` | Yes | Low | P1 |
| Measurement | `clearAngles()` | Yes | Low | P1 |
| Measurement | `clearAllMeasurements()` | Yes | Low | P1 |
| Measurement | `getDescriptives(options: object)` | Yes | Medium | P1 |
| Measurement | `drawMeasurementTool(...)` | No (Internal) | Low | N/A |
| Measurement | `drawAngleMeasurementTool()` | No (Internal) | Low | N/A |
| Measurement | `calculateAngleBetweenLines(...)` | No (Internal) | Low | N/A |
| Measurement | `drawLine(...)` | No (Internal) | Low | N/A |
| Measurement | `drawText(...)` | No (Internal) | Low | N/A |
| Measurement | `drawTextBetween(...)` | No (Internal) | Low | N/A |

---

### Category 8: Export Methods (8 methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| Export | `json()` | Yes | Medium | P1 |
| Export | `loadDocument(doc: NVDocument)` | Yes | High | P2 |
| Export | `loadDocumentFromUrl(url: string)` | Yes | High | P2 |
| Export | `saveDocument(filename: string)` | Yes | Medium | P2 |
| Export | `saveScene(filename: string)` | Yes | Medium | P2 |
| Export | `saveImage(options: object)` | Yes | Medium | P2 |
| Export | `generateHTML()` | Yes | High | P2 |
| Export | `exportViewerState()` | Partial | Medium | P0 |

---

### Category 9: Event Callbacks (25 callbacks)

| Category | Callback | Swift Wrapper Needed | Complexity | Priority |
|----------|----------|---------------------|------------|----------|
| Events | `onLocationChange` | Partial | Medium | P1 |
| Events | `onImageLoaded` | Partial | Low | P0 |
| Events | `onMeshLoaded` | Yes | Low | P2 |
| Events | `onIntensityChange` | Yes | Medium | P1 |
| Events | `onFrameChange` | Yes | Medium | P1 |
| Events | `onAzimuthElevationChange` | Yes | Medium | P1 |
| Events | `onClipPlaneChange` | Yes | Medium | P1 |
| Events | `onClickToSegment` | Yes | Medium | P1 |
| Events | `onMouseUp` | Yes | Medium | P2 |
| Events | `onDragRelease` | Yes | Medium | P2 |
| Events | `onVolumeAddedFromUrl` | Yes | Medium | P1 |
| Events | `onMeshAddedFromUrl` | Yes | Medium | P2 |
| Events | `onVolumeWithUrlRemoved` | Yes | Low | P1 |
| Events | `onMeshWithUrlRemoved` | Yes | Low | P2 |
| Events | `onVolumeUpdated` | Yes | Low | P1 |
| Events | `onColormapChange` | Yes | Low | P1 |
| Events | `onDocumentLoaded` | Yes | Medium | P2 |
| Events | `onOptsChange` | Yes | High | P2 |
| Events | `onZoom3DChange` | Yes | Medium | P1 |
| Events | `onMeshShaderChanged` | Yes | Low | P2 |
| Events | `onMeshPropertyChanged` | Yes | Medium | P2 |
| Events | `onError` | Yes | Medium | P1 |
| Events | `onInfo` | Yes | Low | P2 |
| Events | `onWarn` | Yes | Low | P2 |
| Events | `onDebug` | Yes | Low | P2 |

---

### Category 10: Coordinate Transformation (12 methods)

| Category | Method | Swift Wrapper Needed | Complexity | Priority |
|----------|--------|---------------------|------------|----------|
| Coordinates | `mm2frac(mm: vec3, volIdx?: number)` | Yes | Low | P1 |
| Coordinates | `frac2mm(frac: vec3, volIdx?: number)` | Yes | Low | P1 |
| Coordinates | `vox2frac(vox: vec3, volIdx?: number)` | Yes | Low | P1 |
| Coordinates | `frac2vox(frac: vec3, volIdx?: number)` | Yes | Low | P1 |
| Coordinates | `canvasPos2frac(pos: number[])` | Yes | Low | P1 |
| Coordinates | `frac2canvasPos(frac: vec3)` | Yes | Low | P1 |
| Coordinates | `screenXY2mm(x: number, y: number)` | Yes | Low | P1 |
| Coordinates | `screenXY2TextureFrac(...)` | Yes | Low | P1 |
| Coordinates | `sph2cartDeg(azi: number, elev: number)` | No (Internal) | Low | N/A |
| Coordinates | `head2mm(head: mat4)` | No (Internal) | Low | N/A |
| Coordinates | `getMMfromSlice(slice: number, type: SLICE_TYPE)` | Yes | Low | P1 |
| Coordinates | `getSliceFromMM(mm: number, type: SLICE_TYPE)` | Yes | Low | P1 |

---

### Category 11: Configuration Options (100+ parameters)

**Sample High-Priority Options (representing all 100+):**

| Category | Config Option | Type | Default | Swift Wrapper Needed | Priority |
|----------|---------------|------|---------|---------------------|----------|
| Config | `crosshairColor` | RGBA | [1,0,0,1] | Yes | P1 |
| Config | `crosshairWidth` | number | 1 | Yes | P1 |
| Config | `show3Dcrosshair` | boolean | false | Yes | P1 |
| Config | `backColor` | RGBA | [0,0,0,1] | Yes | P1 |
| Config | `isColorbar` | boolean | true | Yes | P1 |
| Config | `isRuler` | boolean | false | Yes | P1 |
| Config | `isRadiologicalConvention` | boolean | false | Yes | P0 |
| Config | `isNearestInterpolation` | boolean | false | Yes | P0 |
| Config | `textHeight` | number | -1 | Yes | P2 |
| Config | `multiplanarLayout` | enum | 0 | Yes | P1 |
| Config | `showRender` | enum | 2 (AUTO) | Yes | P1 |
| Config | `isSliceBlackBackground` | boolean | false | Yes | P2 |
| Config | `isOrientationCube` | boolean | true | Yes | P0 |
| Config | `isCornerMarkers` | boolean | true | Yes | P0 |
| Config | `isGradientEditable` | boolean | true | Yes | P2 |
| Config | `isAdditiveBlend` | boolean | false | Yes | P1 |
| Config | `showColorbar` | boolean | true | Yes | P0 |

---

## Implementation Roadmap by Phase

### Phase 3: Core Volume Control (3-5 days)
**Priority: P0 - Critical for MVP**

| Task | Methods | Effort | Tests |
|------|---------|--------|-------|
| Intensity windowing (cal_min/max) | `setIntensityWindow()` (new) | 1 day | 3 |
| Volume removal | `removeVolume()`, `removeVolumeByIndex()` | 0.5 day | 2 |
| Volume reordering | `moveVolumeUp()`, `moveVolumeDown()`, `moveVolumeToTop()` | 0.5 day | 3 |
| 3D rotation controls | `setRenderAzimuthElevation()`, callbacks | 1 day | 3 |
| Zoom control | `setZoom()` | 0.5 day | 2 |
| Clip planes | `setClipPlane()`, `setClipPlanes()` | 1 day | 3 |

**Estimated Tests:** 16 total

---

### Phase 4: Navigation & Measurement (3-4 days)
**Priority: P1 - Important for UX**

| Task | Methods | Effort | Tests |
|------|---------|--------|-------|
| Crosshair position tracking | `onLocationChange` callback | 0.5 day | 2 |
| Coordinate transforms | `mm2frac()`, `frac2mm()`, `vox2frac()`, etc. | 1 day | 8 |
| Distance measurement tool | `setDragMode("measurement")` + UI | 1 day | 3 |
| Angle measurement tool | `setDragMode("angle")` + UI | 0.5 day | 2 |
| Measurement clearing | `clearMeasurements()`, `clearAngles()` | 0.25 day | 2 |
| HUD coordinate display | Custom UI integration | 0.5 day | 2 |

**Estimated Tests:** 19 total

---

### Phase 5: Drawing & Segmentation (2-3 days)
**Priority: P1 - Important**

| Task | Methods | Effort | Tests |
|------|---------|--------|-------|
| Create empty drawing | `createEmptyDrawing()` | 0.25 day | 1 |
| Close/save drawing | `closeDrawing()`, `saveDrawing()` enhancement | 0.5 day | 2 |
| Click-to-segment enhancements | `onClickToSegment` callback | 1 day | 3 |
| Advanced segmentation | `drawOtsu()`, `drawGrowCut()`, `binarize()` | 1 day | 6 |
| Undo/redo history | `drawClearAllUndoBitmaps()` + history UI | 0.5 day | 2 |

**Estimated Tests:** 14 total

---

### Phase 6: Advanced Features (4-6 days)
**Priority: P2 - Nice-to-Have**

| Task | Methods | Effort | Tests |
|------|---------|--------|-------|
| Mesh loading | `loadMeshes()`, `addMeshFromUrl()` | 1 day | 4 |
| Mesh controls | `setMeshProperty()`, `setMeshShader()` | 1 day | 4 |
| Tractography rendering | Same pipeline as meshes | 1 day | 3 |
| Settings persistence | `setOpts()` + UserDefaults | 1 day | 4 |
| Export scene as PNG | `saveScene()` | 0.5 day | 2 |
| Export volume | `saveImage()` | 0.5 day | 2 |
| Document save/load | `saveDocument()`, `loadDocument()` | 1 day | 3 |

**Estimated Tests:** 22 total

---

### Phase 7: Event System Integration (2-3 days)
**Priority: P1 - Important**

| Task | Callbacks | Effort | Tests |
|------|-----------|--------|-------|
| Image & mesh loaded events | `onImageLoaded`, `onMeshLoaded` | 0.5 day | 2 |
| Intensity changes | `onIntensityChange` | 0.25 day | 1 |
| Frame changes (4D volumes) | `onFrameChange` | 0.25 day | 1 |
| 3D rotation changes | `onAzimuthElevationChange` | 0.5 day | 1 |
| Clip plane changes | `onClipPlaneChange` | 0.5 day | 1 |
| Segmentation results | `onClickToSegment` | 0.5 day | 2 |
| Error/warning logs | `onError`, `onWarn`, `onInfo` | 0.5 day | 2 |
| URL-based load/remove | `onVolumeAddedFromUrl`, `onVolumeWithUrlRemoved` | 0.5 day | 2 |

**Estimated Tests:** 12 total

---

## Complexity Analysis

### Low Complexity Methods (94 total - 47%)
**Simple pass-through or direct property access**

Examples:
- `removeVolume()` - calls JS method
- `setZoom()` - sets property
- `setColormap()` - sets property
- `clearMeasurements()` - calls JS method
- Coordinate transforms - simple calculations

**Estimated Effort:** 0.25-0.5 days each
**Test Coverage:** 1-2 tests per method

---

### Medium Complexity Methods (82 total - 41%)
**Data transformation or state management**

Examples:
- `loadVolumes()` - requires URL scheme setup
- `moveVolumeUp()` - affects volume array state
- `onLocationChange` - callback with data parsing
- `setMesh()` - mesh state management
- `exportViewerState()` - object serialization

**Estimated Effort:** 0.5-1 day each
**Test Coverage:** 2-3 tests per method

---

### High Complexity Methods (26 total - 12%)
**Complex state management or multi-step workflows**

Examples:
- `loadDicoms()` - multi-file handling + WASM
- `loadConnectome()` - complex data structure
- `drawGrowCut()` - advanced algorithm
- `setCustomLayout()` - layout system management
- `onOptsChange` - configuration change cascading

**Estimated Effort:** 1-2 days each
**Test Coverage:** 3-5 tests per method

---

## Priority Justification

### P0 (Critical) - 37 methods - 18%
**Must have for MVP**

**Volume Control:**
- `removeVolume()`, `removeVolumeByIndex()` - Cannot manage multiple images without removal
- `setRenderAzimuthElevation()` - Essential for 3D viewing
- `setZoom()` - Essential for navigation
- `setInterpolation()` - Performance critical on iOS

**View Configuration:**
- `setSliceType()` - Switch between 2D/3D views
- `setLayout()` - Multiplanar viewing (requested feature)
- `setRadiologicalConvention()` - Neuroimaging standard
- `set3dCrosshairVisible()`, `set2dCrosshairVisible()` - Basic UI
- `setDragMode()` - Interaction modes

**Data Loading:**
- `loadVolumes()`, `loadFromUrl()`, etc. - Core functionality
- `setColormap()`, `setOpacity()` - Volume display
- `listColormaps()` - Colormap UI
- `setPenValue()`, `saveDrawing()` - Drawing support
- `onImageLoaded` - Required for async load confirmation

---

### P1 (Important) - 89 methods - 44%
**Enhance UX and complete core features**

**Volume Management:**
- `moveVolumeUp()`, `moveVolumeToTop()` - Volume ordering
- `getVolumeIndexByID()` - Volume lookup
- `cloneVolume()` - Duplication

**3D Rendering:**
- `setClipPlane()` - Cutaway visualization
- `setVolumeRenderIllumination()` - Quality enhancement
- `setAdditiveBlend()` - Blending modes

**Measurements:**
- Coordinate transforms (`mm2frac()`, etc.) - Essential for annotations
- `clearMeasurements()` - Measurement UI
- `onClickToSegment` - Segmentation feedback
- `onIntensityChange` - Windowing feedback

**Settings:**
- `setOpts()` - Configuration management
- `crosshairColor`, `crosshairWidth`, etc. - Appearance customization

---

### P2 (Nice-to-Have) - 76 methods - 38%
**Advanced features for future phases**

**Advanced Segmentation:**
- `drawOtsu()`, `drawGrowCut()` - Advanced algorithms
- `binarize()`, `removeHaze()` - Filtering

**Mesh & Tractography:**
- All mesh methods (low iOS usage for neuroimaging in Phase 1)
- Connectome methods (specialized use case)

**Export:**
- `saveDocument()`, `saveImage()` - File I/O
- `generateHTML()` - Documentation

**Advanced UI:**
- `setCustomLayout()` - Custom multiplanar layouts
- `setHeroImage()` - Specialized rendering

---

## Testing Strategy by Category

### Unit Tests (React/TypeScript)
- **Location:** `packages/niivue/tests/bridge/`
- **Framework:** Vitest
- **Approach:** Mock Niivue instance, verify JavaScript calls
- **Estimated:** 120-150 total tests

### Integration Tests (Swift)
- **Location:** `NiiVue/NiiVueTests/`
- **Framework:** XCTest
- **Approach:** Mock WebViewManager, verify Swift method calls
- **Estimated:** 150-180 total tests

### E2E Tests (Playwright)
- **Location:** `packages/niivue/playwright/`
- **Framework:** Playwright with visual regression
- **Approach:** Full stack testing with device interaction
- **Estimated:** 50-70 total tests

**Total Test Coverage:** 320-400 tests across all phases

---

## API Implementation Template

### For Each Method, Create:

1. **React Bridge** (`src/bridge/*.ts`)
   ```typescript
   export function methodName(nv: any, param1: Type1, ...): ReturnType {
       // Direct call or event registration
   }
   ```

2. **React Test** (`src/bridge/*.test.ts`)
   ```typescript
   it('should call nv.methodName with correct params', () => {
       // Test implementation
   })
   ```

3. **Swift Wrapper** (`WebViewManager.swift`)
   ```swift
   func methodName(param1: Type1, ...) async throws -> ReturnType {
       let params = try JavaScriptQuote.jsonStringLiteral(...)
       return try await evaluator.evaluateCommand("...")
   }
   ```

4. **Swift Test** (`WebViewManagerCommandTests.swift`)
   ```swift
   func testMethodName() async throws {
       // Test implementation
   }
   ```

5. **UI Component** (if needed)
   ```swift
   struct MethodNameView: View {
       @ObservedRealmObject var session: SessionStore
       var body: some View {
           // SwiftUI implementation
       }
   }
   ```

---

## Implementation Success Criteria

For each category, success = 80%+ of methods implemented with:

✅ React bridge module
✅ React unit tests (2+ per method)
✅ Swift wrapper method
✅ Swift unit tests (2+ per method)
✅ iOS UI component (if user-facing)
✅ Documentation/comments
✅ All tests passing on iOS device

---

## Summary: Total Implementation Estimate

| Phase | Methods | Days | Tests | Priority |
|-------|---------|------|-------|----------|
| Phase 3 | 12 | 3-5 | 16 | P0 |
| Phase 4 | 19 | 3-4 | 19 | P1 |
| Phase 5 | 15 | 2-3 | 14 | P1 |
| Phase 6 | 15 | 4-6 | 22 | P2 |
| Phase 7 | 12 | 2-3 | 12 | P1 |
| Phase 8+ | 130+ | 10+ | 200+ | P2 |
| **Total** | **202+** | **25-30 days** | **320-400** | Mixed |

**Full Feature Parity Timeline:** 6-8 weeks (25-30 development days)

---

## Notes

- **Already Implemented (Phase 2):** 24 methods have some level of wrapper
- **High-Value Low-Effort (Phase 3):** Focus on P0 low-complexity methods first
- **Callback Integration:** Most callbacks can be added as methods become available
- **Configuration Options:** Batch implement via `setOpts()`/`getOpts()` pattern
- **Testing:** Strict TDD required - write tests before implementation

---

*Inventory Complete: 202 methods + 25 callbacks + 100+ options analyzed*
