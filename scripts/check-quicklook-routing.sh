#!/usr/bin/env bash
#
# Verify that Launch Services routes exactly the files the Quick Look preview
# extension claims — and nothing else.
#
# This is the automatable half of Milestone 8's routing matrix. It builds the
# awkward filenames the plan calls for (uppercase, compound, Unicode, spaces,
# long, read-only) and resolves each one's UTI the same way the extension does,
# then compares against the appex's own QLSupportedContentTypes. What it cannot
# do is prove Finder *invokes* the extension: `qlmanage -p` emits nothing from a
# non-GUI shell, so the invocation half stays a manual spacebar sweep. The
# fixture directory is left in place for exactly that.
#
# Usage:
#   ./scripts/check-quicklook-routing.sh [path-to-NiiVue.app]
#
# Exit status: 0 if every fixture routes as expected, 1 otherwise.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
APP="${1:-$(ls -dt "$DERIVED"/NiiVue-*/Build/Products/Debug-maccatalyst/NiiVue.app 2>/dev/null | head -1)}"

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'; N=$'\033[0m'
else
  B=''; DIM=''; R=''; G=''; N=''
fi

if [ -z "$APP" ] || [ ! -d "$APP" ]; then
  echo "${R}No built NiiVue.app found.${N} Build the Catalyst target first, or pass a path."
  exit 1
fi
APPEX="$APP/Contents/PlugIns/QuickLookPreview.appex"
PLIST="$APPEX/Contents/Info.plist"
[ -f "$PLIST" ] || { echo "${R}No QuickLookPreview.appex inside $APP${N}"; exit 1; }

echo "${B}App${N}    $APP"

CLAIMED=$(/usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionAttributes:QLSupportedContentTypes" "$PLIST" \
  | sed -n 's/^ *\([a-z][a-zA-Z0-9._-]*\)$/\1/p')
echo "${B}Claims${N} $(echo "$CLAIMED" | tr '\n' ' ')"
echo

FIXTURES="${TMPDIR:-/tmp}/niivue-ql-routing"
rm -rf "$FIXTURES"; mkdir -p "$FIXTURES"

# name<TAB>should-route. The extension claims a *type*, so these exercise how a
# filename reaches that type: case, compound extensions, and characters that
# have to survive the scheme handler's percent-encoded token route.
LONG=$(printf 'l%.0s' {1..180})
while IFS=$'\t' read -r name expect; do
  [ -z "$name" ] && continue
  : > "$FIXTURES/$name"
  echo "$expect" > "$FIXTURES/.expect.$name"
done <<EOF
plain.nii	yes
UPPER.NII	yes
MiXeD.NiI	yes
compound.nii.gz	yes
double.NII.GZ	yes
with spaces.nii	yes
sujet-café-ø-日本.nii	yes
$LONG.nii	yes
readonly.nii	yes
volume.mgh	yes
volume.mgz	yes
volume.nrrd	yes
volume.mha	yes
surface.gii	yes
surface.mz3	yes
tracts.tck	yes
tracts.trk	yes
tracts.trx	yes
archive.tar.gz	yes
notours.zip	no
detached.mhd	no
detached.hdr	no
detached.img	no
afni.HEAD	no
afni.BRIK	no
detached.nhdr	no
surf.white	no
surf.pial	no
surf.inflated	no
surf.sphere	no
model.obj	no
model.stl	no
model.ply	no
notes.txt	no
EOF
chmod 444 "$FIXTURES/readonly.nii"

# Resolve each fixture's type exactly as PreviewViewController does, via
# URLResourceValues.contentType, rather than by parsing the filename.
cat > "$FIXTURES/uti.swift" <<'SWIFT'
import Foundation
import UniformTypeIdentifiers
let dir = CommandLine.arguments[1]
let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
for name in names.sorted() where !name.hasPrefix(".") && !name.hasSuffix(".swift") {
    let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? "?"
    print("\(name)\t\(type)")
}
SWIFT

FAILED=0
CHECKED=0
printf "${DIM}%-34s %-32s %-8s %s${N}\n" FIXTURE RESOLVED-TYPE ROUTES VERDICT
while IFS=$'\t' read -r name type; do
  CHECKED=$((CHECKED + 1))
  expect=$(cat "$FIXTURES/.expect.$name" 2>/dev/null || echo '?')
  routes=no
  echo "$CLAIMED" | grep -qx "$type" && routes=yes
  short="$name"
  [ ${#short} -gt 33 ] && short="${short:0:14}…${short: -18}"
  if [ "$routes" = "$expect" ]; then
    printf "%-34s %-32s %-8s ${G}ok${N}\n" "$short" "$type" "$routes"
  else
    printf "%-34s %-32s %-8s ${R}EXPECTED $expect${N}\n" "$short" "$type" "$routes"
    FAILED=$((FAILED + 1))
  fi
done < <(swift "$FIXTURES/uti.swift" "$FIXTURES")

echo
# A gzip claim means every .gz on the machine reaches us, so the content sniff
# is what keeps a tarball from being overpainted. That half is Swift-side and is
# covered by GzipPeek; here we only assert the routing reaches us at all.
echo "${DIM}archive.tar.gz routes by design — the extension claims generic gzip and"
echo "declines by content. Verify in Finder that it is NOT overpainted.${N}"
echo
# A resolver that produced nothing must not read as a clean run — silence is the
# one result that looks identical to success.
EXPECTED_COUNT=$(ls -1 "$FIXTURES"/.expect.* 2>/dev/null | wc -l | tr -d ' ')
if [ "$CHECKED" -ne "$EXPECTED_COUNT" ]; then
  echo "${R}Only $CHECKED of $EXPECTED_COUNT fixtures were resolved — the UTI probe failed.${N}"
  exit 1
fi
if [ "$FAILED" -eq 0 ]; then
  echo "${G}All $CHECKED fixtures route as expected.${N}"
else
  echo "${R}$FAILED of $CHECKED fixture(s) routed unexpectedly.${N}"
fi
echo
echo "${B}Manual half${N} — Finder cannot be driven from a shell. Sweep with spacebar:"
echo "  open '$FIXTURES'"
echo "Then check Space opens/closes, Escape dismisses, and the panel resizes."
exit $((FAILED > 0))
