/**
 * DICOM bridge for iOS integration.
 * Provides manifest-based DICOM series loading through the custom niivue:// URL scheme.
 */

/**
 * Load a DICOM series from a manifest URL.
 * The manifest is a text file containing one DICOM filename per line.
 * Niivue will resolve each filename relative to the manifest URL.
 *
 * @param nv - Niivue instance
 * @param manifestUrl - URL to the manifest file (e.g., niivue://app/dicom/series1/niivue-manifest.txt)
 * @returns Promise that resolves when loading is complete
 */
export async function loadDicomSeriesFromManifest(nv: any, manifestUrl: string): Promise<any> {
  return nv.loadDicoms([{ url: manifestUrl, isManifest: true }]);
}
