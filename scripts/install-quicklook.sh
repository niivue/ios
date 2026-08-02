#!/usr/bin/env bash
#
# Build the Catalyst app and make Finder use THAT copy of the Quick Look
# extension — then prove which binary is registered.
#
# This exists because registration silently moves. Any second copy of the app —
# an `xcodebuild archive`, an old `-derivedDataPath` tree, a copy in
# /Applications — can win the registration, and Finder will happily preview with
# a binary from hours ago while you conclude your change did not work. That has
# cost this project real debugging time.
#
# Usage:  ./scripts/install-quicklook.sh [--no-build]

set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
ID=com.niivue.mobile.QuickLookPreview

if [ -t 1 ]; then B=$'\033[1m'; R=$'\033[31m'; G=$'\033[32m'; DIM=$'\033[2m'; N=$'\033[0m'
else B=''; R=''; G=''; DIM=''; N=''; fi

if [ "${1:-}" != "--no-build" ]; then
  echo "${B}Building${N} Mac Catalyst…"
  ( cd "$REPO/NiiVue" && xcodebuild -project NiiVue.xcodeproj -scheme NiiVue \
      -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
      CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build ) \
    2>&1 | grep -E "^\*\* BUILD|error:" || true
fi

APP=$(ls -dt "$HOME"/Library/Developer/Xcode/DerivedData/NiiVue-*/Build/Products/Debug-maccatalyst/NiiVue.app 2>/dev/null | head -1)
[ -d "$APP" ] || { echo "${R}No Debug-maccatalyst build found.${N}"; exit 1; }

# Evict every OTHER registration first, or the newest is not necessarily the one
# Finder picks.
echo "${B}Evicting${N} other copies…"
/usr/bin/pluginkit -m -v -A -D 2>/dev/null | grep -F "$ID" | sed 's/.*\t//' | while read -r other; do
  case "$other" in
    "$APP"/*) ;;
    *) echo "  ${DIM}drop $other${N}"; /usr/bin/pluginkit -r "$other" 2>/dev/null
       "$LSREG" -u "$(echo "$other" | sed 's#/Contents/PlugIns/.*##')" 2>/dev/null ;;
  esac
done

"$LSREG" -f -R "$APP"
/usr/bin/pluginkit -a "$APP/Contents/PlugIns/QuickLookPreview.appex"
/usr/bin/qlmanage -r >/dev/null 2>&1; /usr/bin/qlmanage -r cache >/dev/null 2>&1

echo
echo "${B}Registered${N}"
COUNT=$(/usr/bin/pluginkit -m -v -A -D 2>/dev/null | grep -cF "$ID")
/usr/bin/pluginkit -m -v -A -D 2>/dev/null | grep -F "$ID" | sed 's/.*\t/  /'
STAMP=$(stat -f '%Sm' -t '%b %d %H:%M:%S' "$APP/Contents/PlugIns/QuickLookPreview.appex/Contents/MacOS/QuickLookPreview")
echo "  ${B}built $STAMP${N}"
if [ "$COUNT" -ne 1 ]; then echo "${R}  $COUNT copies registered — Finder may pick either.${N}"; exit 1; fi
echo
echo "${G}Verify what Finder actually ran${N} — preview a file, then:"
echo "  log show --last 2m --style compact \\"
echo "    --predicate 'subsystem == \"com.niivue.mobile.QuickLookPreview\"' | grep built"
echo "${DIM}It logs its own build time on every preview. If that does not match${N}"
echo "${DIM}\"built $STAMP\" above, you are testing a different binary.${N}"
