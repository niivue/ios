import { describe, expect, it, vi } from "vitest";
import { loadDicomSeriesFromManifest } from "./dicomBridge";

describe("loadDicomSeriesFromManifest", () => {
  it("calls Niivue loadDicoms with isManifest=true", async () => {
    const nv: any = { loadDicoms: vi.fn(async () => nv) };
    await loadDicomSeriesFromManifest(nv, "niivue://app/dicom/series1/niivue-manifest.txt");
    expect(nv.loadDicoms).toHaveBeenCalledWith([{ url: "niivue://app/dicom/series1/niivue-manifest.txt", isManifest: true }]);
  });
});
