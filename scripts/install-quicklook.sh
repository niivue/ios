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
  # PIPESTATUS, not $?: the pipe to grep would otherwise mask a failed build,
  # and the page-hash check below cannot catch that — the appex's CopyFiles
  # phase runs BEFORE Sources, so a Swift compile error leaves a freshly copied
  # page beside the previous build's binary. The hash matches, and the script
  # would certify a stale binary as fresh. That is the exact failure this script
  # exists to prevent.
  ( cd "$REPO/NiiVue" && xcodebuild -project NiiVue.xcodeproj -scheme NiiVue \
      -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
      CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM="" build ) \
    2>&1 | grep -E "^\*\* BUILD|error:"
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    echo "${R}Build failed — refusing to register. Nothing was changed.${N}"
    exit 1
  fi
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
# Verify the SHIPPED page is the one we just built. The bundle copy has gone
# stale before, and a binary date says nothing about the web assets inside it.
SRC="$REPO/NiiVue/React/dist/quicklook.html"
DST="$APP/Contents/PlugIns/QuickLookPreview.appex/Contents/Resources/dist/quicklook.html"
if [ -f "$SRC" ] && [ -f "$DST" ]; then
  if [ "$(shasum -a 256 <"$SRC" | cut -c1-12)" = "$(shasum -a 256 <"$DST" | cut -c1-12)" ]; then
    echo "  ${G}page matches the build${N} ($(shasum -a 256 <"$DST" | cut -c1-12))"
  else
    echo "  ${R}SHIPPED PAGE IS STALE — the appex does not contain the page you just built.${N}"
    exit 1
  fi
fi

LOG="$HOME/Library/Containers/$ID/Data/tmp/quicklook-preview.log"
rm -f "$LOG" 2>/dev/null
echo
echo "${B}Confirm it actually ran${N} — preview a file in Finder, then:"
echo "  tail -5 \"$LOG\""
echo "${DIM}Each preview appends a line with the build stamp. os_log from a Quick Look${N}"
echo "${DIM}appex does NOT reach \`log show\`, so this file is the only reliable signal.${N}"
echo "${DIM}An empty or missing file means the extension never ran at all.${N}"
