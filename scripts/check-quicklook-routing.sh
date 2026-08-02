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

# Fixture bodies are REAL, not zero-byte placeholders: the exit gate is that
# advertised types route AND render, and a directory of empty files would make
# the manual sweep show nothing but fallback panels. The generator prints the
# expectation table it just wrote.
EXPECT="$FIXTURES/.expect"
if ! (cd "$REPO/NiiVue/React" && node tests/make-routing-fixtures.mjs "$FIXTURES") > "$EXPECT"; then
  echo "${R}Could not generate fixtures.${N}"
  exit 1
fi
chmod 444 "$FIXTURES/good/readonly.nii"

# Resolve each fixture's type exactly as PreviewViewController does, via
# URLResourceValues.contentType, rather than by parsing the filename.
cat > "$FIXTURES/uti.swift" <<'SWIFT'
import Foundation
import UniformTypeIdentifiers
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
for folder in ["good", "bad"] {
    let dir = root.appendingPathComponent(folder)
    let names = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
    for name in names.sorted() where !name.hasPrefix(".") && name != "README.txt" {
        let url = dir.appendingPathComponent(name)
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.identifier ?? "?"
        print("\(folder)/\(name)\t\(type)")
    }
}
SWIFT

FAILED=0
CHECKED=0
SKIPPED=0
printf "${DIM}%-35s %-32s %-7s %-8s %s${N}\n" FIXTURE RESOLVED-TYPE ROUTES SHOULD VERDICT
while IFS=$'\t' read -r name type; do
  # Tab-separated, and read with IFS set: a filename containing a space would
  # otherwise be split across the field variables. `with spaces.nii` exists in
  # this set precisely to keep that honest.
  IFS=$'\t' read -r _ expect render < <(grep -F "$(printf '%s\t' "$name")" "$EXPECT" | head -1)
  [ -z "${expect:-}" ] && continue
  CHECKED=$((CHECKED + 1))
  routes=no
  echo "$CLAIMED" | grep -qx "$type" && routes=yes
  short="$name"
  [ ${#short} -gt 34 ] && short="${short:0:16}…${short: -17}"
  case "$render" in
    yes) want="render" ;;
    skip) want="skipped"; SKIPPED=$((SKIPPED + 1)) ;;
    *)   want=$([ "$routes" = yes ] && echo "explain" || echo "not ours") ;;
  esac
  if [ "$routes" = "$expect" ]; then
    printf "%-35s %-32s %-7s %-8s ${G}ok${N}\n" "$short" "$type" "$routes" "$want"
  else
    printf "%-35s %-32s %-7s %-8s ${R}EXPECTED $expect${N}\n" "$short" "$type" "$routes" "$want"
    FAILED=$((FAILED + 1))
  fi
done < <(swift "$FIXTURES/uti.swift" "$FIXTURES")

echo
# A resolver that produced nothing must not read as a clean run — silence is the
# one result that looks identical to success. This script shipped with exactly
# that bug: its Swift probe failed to compile and it reported every fixture ok.
EXPECTED_COUNT=$(wc -l < "$EXPECT" | tr -d ' ')
if [ "$CHECKED" -ne "$EXPECTED_COUNT" ]; then
  echo "${R}Only $CHECKED of $EXPECTED_COUNT fixtures were resolved — the UTI probe failed.${N}"
  exit 1
fi
if [ "$FAILED" -eq 0 ]; then
  echo "${G}All $CHECKED fixtures route as expected.${N}"
else
  echo "${R}$FAILED of $CHECKED fixture(s) routed unexpectedly.${N}"
fi
[ "$SKIPPED" -gt 0 ] && echo "${DIM}$SKIPPED fixture(s) borrowed from the private dev-images package, which is absent.${N}"
echo
echo "${B}Manual half${N} — Finder cannot be driven from a shell. Two folders,"
echo "one rule each; each carries a README.txt spelling out what to look for."
echo
echo "  ${G}open '$FIXTURES/good'${N}   every file must DRAW AN IMAGE"
echo "  ${R}open '$FIXTURES/bad'${N}    no file may draw an image"
echo
echo "${DIM}Inside bad/, the split that matters: truncated/corrupt/layer-only must show"
echo "OUR panel with a reason, while archive.tar.gz and the unclaimed types must"
echo "keep whatever macOS shows. An archive wearing our panel is a regression.${N}"
exit $((FAILED > 0))
