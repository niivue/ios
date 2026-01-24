#!/usr/bin/env bash
set -euo pipefail

DEVICE_ID="${1:-00008140-001664420413C01C}"
BUNDLE_ID="${BUNDLE_ID:-com.niivue.mobile}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="${ROOT_DIR}/Test_CT_DICOM_volumes"
DEST_DIR="Documents/Test_CT_DICOM_volumes"

if [[ ! -d "${SRC_DIR}" ]]; then
  echo "Missing source directory: ${SRC_DIR}" >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "Missing xcrun (Xcode command line tools)." >&2
  exit 1
fi

echo "Copying fixtures to device:"
echo "  device: ${DEVICE_ID}"
echo "  bundle: ${BUNDLE_ID}"
echo "  source: ${SRC_DIR}"
echo "  dest:   ${DEST_DIR}"

xcrun devicectl device copy to \
  --device "${DEVICE_ID}" \
  --domain-type appDataContainer \
  --domain-identifier "${BUNDLE_ID}" \
  --source "${SRC_DIR}" \
  --destination "${DEST_DIR}" \
  --remove-existing-content true \
  --timeout 1200

echo "Done."
