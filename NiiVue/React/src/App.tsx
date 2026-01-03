import React from 'react'
import { Niivue, NVImage } from '@niivue/niivue';
import Container from '@mui/material/Container';
import Box from '@mui/material/Box';
import SpeedDial from '@mui/material/SpeedDial';
import DragModeIcon from '@mui/icons-material/AdsClick'; // speed dial icon
import ViewModeIcon from '@mui/icons-material/GridView'; // view mode speed dial icon
import './App.css'
// Task 7 & 7.5: iOS messaging bridge
import { postToIOS } from './bridge/iosMessaging'
// Phase 2 Task 3: Volume colormap/opacity commands
import { setColormap as nvSetColormap, setOpacity as nvSetOpacity, listColormaps as nvListColormaps } from './bridge/volumeCommands'

declare global {
  interface Window {
    loadBase64Image: (base64: string, fileName: string) => Promise<void>,
    // Task 10: URL-based loading (no base64)
    loadImageFromUrl: (url: string, fileName: string) => Promise<void>,
    // Phase 2 Task 2: Multi-volume loading
    loadVolumesFromUrls: (volumes: Array<{ url: string; name: string }>) => Promise<void>,
    // Phase 2 Task 2: Get current volume count
    getVolumeCount: () => number,
    // Phase 2 Task 2: Get volume info list
    getVolumeInfoList: () => string,
    // Phase 2 Task 3: Colormap and opacity controls
    setColormap: (volumeIndex: number, colormap: string) => void,
    setOpacity: (volumeIndex: number, opacity: number) => void,
    listColormaps: () => string[],
    // eslint-disable-next-line @typescript-eslint/ban-types
    setCrosshairColor: Function,
    // Task 5: saveDrawing is now async
    saveDrawing: () => Promise<string>,
    // eslint-disable-next-line @typescript-eslint/ban-types
    setSliceType: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    set3dCrosshairVisible: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    setLayout: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    setDragMode: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    setPenValue: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    set2dCrosshairVisible: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    setCornerText: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    setOrientationCube: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    setRadiological: Function,
    // eslint-disable-next-line @typescript-eslint/ban-types
    moveCrosshairInVox: Function,
    webkit: {
      messageHandlers: {
        updateUI: {
          postMessage: (message: string) => void
        },
        logMessage: {
          postMessage: (message: string) => void
        },
        locationChange: {
          postMessage: (message: string) => void
        }
      }
    }
  }
}

function App() {
  // canvas ref
  const canvasRef = React.useRef<HTMLCanvasElement>(null);
  const nvRef = React.useRef<Niivue>(new Niivue(
    {
      logLevel: 'debug',
      loadingText: 'Loading...',
    }
  ));
  const nv = nvRef.current;
  const backgroundColor = 'black'

  function setSliceType(sliceType: number) {
    nv.opts.multiplanarForceRender = true
    nv.setMultiplanarLayout(2) // 2x2
    nv.setSliceType(sliceType)
  }

  function setLayout(layout: number) {
    nv.opts.multiplanarForceRender = true
    nv.setMultiplanarLayout(layout)
  }

  function set3dCrosshairVisible(visible: boolean) {
    nv.opts.show3Dcrosshair = visible
    nv.updateGLVolume();
    nv.drawScene();
  }

  function setPenValue(value: number, isFilled: boolean, drawingEnabled: boolean = true) {
    nv.setDrawingEnabled(drawingEnabled)
    nv.setPenValue(value, isFilled)
  }

  function setDragMode(dragMode: number) {
    nv.opts.dragMode = dragMode
  }

  function set2dCrosshairVisible(visible: boolean) {
    nv.opts.crosshairWidth = visible ? 1 : 0
    nv.updateGLVolume();
    nv.drawScene();
  }

  function setCornerText(isCorners: boolean) {
    nv.setCornerOrientationText(isCorners)
  }

  function setOrientationCube(visible: boolean) {
    nv.opts.isOrientCube = visible
    nv.updateGLVolume();
    nv.drawScene();
  }

  function setRadiological(isRadiological: boolean) {
    nv.setRadiologicalConvention(isRadiological)
  }

  function moveCrosshairInVox(x: number, y: number, z: number) {
    nv.moveCrosshairInVox(x, y, z)
  }

  function onLocationChange(location) {
    // Phase 2 Task 1: Send full location info for HUD display
    postToIOS('locationChange', { string: location.string, mm: location.mm, values: location.values })
  }

  const setup = async () => {
    if (!canvasRef.current) {
      return;
    }
    await nv.attachToCanvas(canvasRef.current);
    nv.onLocationChange = onLocationChange;
    // Task 7.5: Volume notifications - notify Swift when images are loaded
    nv.onImageLoaded = (volume) => {
      console.log('[NiiVue] onImageLoaded:', volume.id, volume.name)
      postToIOS('volumeLoaded', {
        id: volume.id,
        name: volume.name,
        nFrame4D: volume.nFrame4D ?? 1
      })
    }
    // Task 7: Notify Swift that the web view is ready for commands
    postToIOS('finishedLoading', { ready: true })
  };

  async function loadBase64Image(base64: string, fileName: string) {
    console.log(fileName)
    // name is required for the image to be loaded (file type inferred correctly),
    // but it is not used elsewhere
    // NVImage.loadFromBase64 is async in Niivue 0.66.0+
    const nvimage = await NVImage.loadFromBase64({base64:base64, name: fileName})
    nv.closeDrawing()
    nv.volumes = []
    nv.updateGLVolume()
    nv.addVolume(nvimage)
  }

  // Task 10: URL-based loading (no base64 encoding needed)
  async function loadImageFromUrl(url: string, fileName: string) {
    console.log(`Loading from URL: ${url}, fileName: ${fileName}`)
    nv.closeDrawing()
    await nv.loadVolumes([{ url, name: fileName }])
  }

  // Phase 2 Task 2: Multi-volume loading
  async function loadVolumesFromUrls(volumes: Array<{ url: string; name: string }>) {
    console.log(`Loading ${volumes.length} volumes`)
    nv.closeDrawing()
    await nv.loadVolumes(volumes)
    console.log(`Loaded, now have ${nv.volumes.length} volumes`)
  }

  // Phase 2 Task 2: Get current volume count
  function getVolumeCount(): number {
    return nv.volumes.length
  }

  // Phase 2 Task 2: Get volume info list (for sync when callbacks don't work)
  function getVolumeInfoList(): string {
    const info = nv.volumes.map((v) => ({
      id: v.id,
      name: v.name,
      nFrame4D: v.nFrame4D ?? 1
    }))
    return JSON.stringify(info)
  }

  // Phase 2 Task 3: Colormap and opacity controls
  function setColormap(volumeIndex: number, colormap: string): void {
    nvSetColormap(nv, volumeIndex, colormap)
  }

  function setOpacity(volumeIndex: number, opacity: number): void {
    nvSetOpacity(nv, volumeIndex, opacity)
  }

  function listColormaps(): string[] {
    return nvListColormaps(nv)
  }

  function setCrosshairColor() {
    nv.setCrosshairColor([0,1,0,0.5])
  }

  // Task 5: Truly async saveDrawing
  async function saveDrawing(): Promise<string> {
    function uint8ArrayToBase64(buffer: Uint8Array): string {
      let binary = '';
      const bytes = buffer;
      const len = bytes.byteLength;

      for (let i = 0; i < len; i++) {
        binary += String.fromCharCode(bytes[i]);
      }

      return btoa(binary);
    }

    // Use await to properly handle the async saveImage call
    const img = await nv.saveImage({ filename: 'niivue_drawing.nii.gz', isSaveDrawing: true, volumeByIndex: 0 });

    // If img is a Uint8Array, convert to base64
    if (img instanceof Uint8Array) {
      return uint8ArrayToBase64(img);
    }

    // If no drawing exists, throw an error so Swift gets a deterministic failure
    throw new Error('No drawing to save');
  }

  React.useEffect(() => {
    setup();
    window.loadBase64Image = loadBase64Image
    window.loadImageFromUrl = loadImageFromUrl  // Task 10: URL-based loading
    window.loadVolumesFromUrls = loadVolumesFromUrls  // Phase 2 Task 2: Multi-volume
    window.getVolumeCount = getVolumeCount  // Phase 2 Task 2: Get volume count
    window.getVolumeInfoList = getVolumeInfoList  // Phase 2 Task 2: Get volume info
    window.setColormap = setColormap  // Phase 2 Task 3: Colormap control
    window.setOpacity = setOpacity  // Phase 2 Task 3: Opacity control
    window.listColormaps = listColormaps  // Phase 2 Task 3: List available colormaps
    window.setCrosshairColor = setCrosshairColor
    window.saveDrawing = saveDrawing
    window.setSliceType = setSliceType
    window.setLayout = setLayout
    window.set3dCrosshairVisible = set3dCrosshairVisible
    window.setDragMode = setDragMode
    window.setPenValue = setPenValue
    window.set2dCrosshairVisible = set2dCrosshairVisible
    window.setCornerText = setCornerText
    window.setOrientationCube = setOrientationCube
    window.setRadiological = setRadiological
    window.moveCrosshairInVox = moveCrosshairInVox
    // Note: finishedLoading is now called in setup() after canvas attachment
  }, []);

  return (
    <Container
      maxWidth={false}
      component='main'
      style={{
        display: 'flex',
        padding: '0',
        margin: '0',
        flexDirection: 'row',
        height: '100%',
        width: '100%',
        backgroundColor: backgroundColor
      }}

    >
      {/* canvas */}
      <Box
        style={{
          margin: '0',
          padding: '0',
          display: 'flex',
          flexDirection: 'column',
          height: '100%',
          width: '100%',
          backgroundColor: backgroundColor
        }}
      >
        {/* no focus ring on canvas */}
        <canvas ref={canvasRef} className='no-focus' />
      </Box>
      {/* vertical tool buttons */}
      {/* THIS IS HIDDEN IN FAVOUR OF iOS UI ELEMENTS */}
      <Box
        style={{
          margin: '0',
          padding: '0',
          display: 'none', // HIDDEN
          flexDirection: 'column',
          height: '100%',
          width: '72px',
          backgroundColor: backgroundColor,
        }}
      >
        {/* speed dial bottom */}
        <SpeedDial
          sx={{
            position: 'absolute',
            bottom: 16,
            right: 14
          }}
          FabProps={{
            size: 'small',
          }}
          ariaLabel="view modes"
          icon={<ViewModeIcon/>}
          direction="left" // open left
        >
        {/* {viewModeActions.map((action) => (
          <SpeedDialAction
            key={action.name}
            FabProps={{'variant': 'extended'}}
            icon={
              <Box
                style={{
                  display: 'flex',
                  flexDirection: 'row',
                  alignItems: 'center',
                }}
                onTouchEnd={action.action}
                onClick={action.action}
              >
                {action.icon}
                <Typography variant='body1' textTransform={'none'}>
                  {action.name}
                </Typography>
              </Box>
            }
            tooltipTitle={action.name}
          />
        ))} */}
      </SpeedDial>

      {/* speed dial drag modes */}
      <SpeedDial
          sx={{
            position: 'absolute',
            bottom: 84,
            right: 14
          }}
          FabProps={{
            size: 'small',
          }}
          ariaLabel="view modes"
          icon={<DragModeIcon/>}
          direction="left" // open left
        >
        {/* {dragModeActions.map((action) => (
          <SpeedDialAction
            key={action.name}
            FabProps={{'variant': 'extended'}}
            icon={
              <Box
                style={{
                  display: 'flex',
                  flexDirection: 'row',
                  alignItems: 'center',
                }}
                onTouchEnd={action.action}
                onClick={action.action}
              >
                {action.icon}

              </Box>
            }
            tooltipTitle={action.name}
          />
        ))} */}
      </SpeedDial>

      {/* speed dial draw modes */}
      <SpeedDial
          sx={{
            position: 'absolute',
            bottom: 152,
            right: 8
          }}
          FabProps={{
            size: 'small',
          }}
          ariaLabel="draw modes"
          // icon={<PencilIcon/>}
          // direction="left" // open left
        >
        {/* {drawActions.map((action) => (
          <SpeedDialAction
            key={action.name}
            FabProps={{'variant': 'extended'}}
            icon={
              <Box
                style={{
                  display: 'flex',
                  flexDirection: 'row',
                  alignItems: 'center',
                }}
                onTouchEnd={action.action}
                onClick={action.action}
              >
                {action.icon !== null ? action.icon : <Typography variant='body1' textTransform={'none'}>{action.name}</Typography>}
              </Box>
            }
            tooltipTitle={action.name}
          />
        ))} */}
      </SpeedDial>
      </Box>
    </Container>   
  )
}

export default App
