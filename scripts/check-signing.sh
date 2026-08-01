#!/usr/bin/env bash
#
# Report which code-signing identities this Mac holds, which Apple team they
# belong to, and therefore which build targets will actually succeed.
#
# Usage:
#   ./scripts/check-signing.sh              # uses $APPLE_TEAM_ID, else the project's
#   ./scripts/check-signing.sh 68BQDQS28R   # or name a team explicitly
#
# Exit status: 0 if the wanted team can build for local development,
#              1 if it cannot (no development certificate).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO/NiiVue/NiiVue.xcodeproj/project.pbxproj"
APPLE_ID="${APPLE_ID:-}"

if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; R=$'\033[31m'; G=$'\033[32m'; Y=$'\033[33m'; N=$'\033[0m'
else
  B=""; DIM=""; R=""; G=""; Y=""; N=""
fi
ok()   { printf '  %s✓%s %s\n' "$G" "$N" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$R" "$N" "$1"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$1"; }

# --- What the project asks for -----------------------------------------------
# A team ID is always 10 uppercase alphanumerics; anything else is rejected so a
# stray value cannot reach the shell snippet printed at the end.
valid_team() { [[ "$1" =~ ^[A-Z0-9]{10}$ ]]; }

PROJECT_TEAM=""
if [ -f "$PROJECT" ]; then
  PROJECT_TEAM=$(grep -m1 -oE 'DEVELOPMENT_TEAM = [A-Z0-9]{10}' "$PROJECT" | awk '{print $3}')
fi

# Fall back to the team the project actually builds as — otherwise the script
# happily reports "you can build" using some unrelated team's certificate.
WANT_TEAM="${1:-${APPLE_TEAM_ID:-$PROJECT_TEAM}}"
if [ -n "$WANT_TEAM" ] && ! valid_team "$WANT_TEAM"; then
  printf '%sNot a team ID: %s (expected 10 uppercase alphanumerics)%s\n' "$R" "$WANT_TEAM" "$N"
  exit 2
fi

printf '%sCode-signing check%s\n' "$B" "$N"
[ -n "$APPLE_ID" ]     && printf '  Apple ID       %s\n' "$APPLE_ID"
[ -n "$WANT_TEAM" ]    && printf '  Wanted team    %s\n' "$WANT_TEAM"
[ -n "$PROJECT_TEAM" ] && printf '  Project team   %s %s(DEVELOPMENT_TEAM in project.pbxproj)%s\n' \
                            "$PROJECT_TEAM" "$DIM" "$N"
echo

# --- What the keychain holds --------------------------------------------------
# `find-identity -v` lists only identities with a private key that already pass
# the codesigning policy, so expiry is pre-filtered. Certificates are correlated
# by SHA-1: looking them up by common name matches on a prefix and can return an
# intermediate CA or a stale duplicate instead of the identity.
IDENTITIES=$(security find-identity -v -p codesigning 2>/dev/null | grep -E '^[[:space:]]+[0-9]+\)' || true)
ALL_CERTS=$(security find-certificate -a -Z -p 2>/dev/null || true)

pem_for_hash() {
  printf '%s\n' "$ALL_CERTS" | awk -v h="$1" '
    $0 == "SHA-1 hash: " h { found = 1; next }
    found && /^-----BEGIN CERTIFICATE-----/ { p = 1 }
    p { print }
    p && /^-----END CERTIFICATE-----/ { exit }
  '
}

if [ -z "$IDENTITIES" ]; then
  printf '%sNo code-signing identities in the keychain.%s\n\n' "$R" "$N"
else
  printf '%sIdentities%s\n' "$B" "$N"
fi

have_dev=0 have_devid=0 have_dist=0 found_teams=""

while IFS= read -r line; do
  [ -z "$line" ] && continue
  hash=$(printf '%s' "$line" | awk '{print $2}')
  cn=$(printf '%s' "$line" | sed -n 's/.*"\(.*\)"$/\1/p')
  [ -z "$cn" ] && continue

  pem=$(pem_for_hash "$hash")
  team="" expiry="" soon=""
  if [ -n "$pem" ]; then
    team=$(printf '%s' "$pem" | openssl x509 -noout -subject 2>/dev/null \
             | grep -oE 'OU *= *[A-Z0-9]+' | head -1 | sed 's/.*= *//')
    expiry=$(printf '%s' "$pem" | openssl x509 -noout -enddate 2>/dev/null | sed 's/notAfter=//')
    printf '%s' "$pem" | openssl x509 -checkend 2592000 -noout >/dev/null 2>&1 || soon=" ${Y}[expires <30d]${N}"
  fi
  [ -n "$team" ] && found_teams="$found_teams $team"

  printf '  %-58s team %-12s%s\n' "$cn" "${team:-?}" "$soon"
  [ -n "$expiry" ] && printf '    %sexpires %s%s\n' "$DIM" "$expiry" "$N"

  # An identity whose certificate could not be resolved has an unknown team and
  # must not count toward "you can build".
  [ -z "$team" ] && { warn "could not resolve this certificate; ignoring it"; continue; }
  [ -n "$WANT_TEAM" ] && [ "$team" != "$WANT_TEAM" ] && continue

  case "$cn" in
    "Apple Development:"*|"Mac Developer:"*|"Mac Development:"*|"iPhone Developer:"*) have_dev=1 ;;
    "Apple Distribution:"*|"iPhone Distribution:"*|"3rd Party Mac Developer Application:"*) have_dist=1 ;;
    "Developer ID Application:"*) have_devid=1 ;;
  esac
done <<< "$IDENTITIES"
echo

# --- Team match ---------------------------------------------------------------
if [ -n "$WANT_TEAM" ]; then
  printf '%sTeam%s\n' "$B" "$N"
  case " $found_teams " in
    *" $WANT_TEAM "*) ok "keychain holds a certificate for $WANT_TEAM" ;;
    *)                bad "no certificate for $WANT_TEAM in the keychain" ;;
  esac
  if [ -n "$PROJECT_TEAM" ] && [ "$PROJECT_TEAM" != "$WANT_TEAM" ]; then
    warn "the project builds as $PROJECT_TEAM, not $WANT_TEAM — signed builds will fail"
    printf '      %sfix: open the target > Signing & Capabilities and pick your team, or:%s\n' "$DIM" "$N"
    printf '      %ssed -i "" "s/DEVELOPMENT_TEAM = %s/DEVELOPMENT_TEAM = %s/g" \\%s\n' \
      "$DIM" "$PROJECT_TEAM" "$WANT_TEAM" "$N"
    printf '        %s%s%s\n' "$DIM" "${PROJECT/#$HOME/~}" "$N"
  fi
  echo
fi

# --- What you can actually build ---------------------------------------------
printf '%sWhat will build%s\n' "$B" "$N"
ok "iOS Simulator — never needs a certificate (signs to run locally)"
ok "Mac Catalyst, run locally — add: CODE_SIGN_IDENTITY=\"-\" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=\"\""

if [ "$have_dev" = 1 ]; then
  ok "iOS device / Xcode Run button — development certificate present"
  ok "Mac Catalyst via Xcode Run button"
else
  bad "iOS device / Xcode Run button — no development certificate"
  printf '      %sfix: Xcode > Settings > Accounts, add %s, then%s\n' \
    "$DIM" "${APPLE_ID:-your Apple ID}" "$N"
  printf '      %sSigning & Capabilities > Team. Xcode issues the certificate itself.%s\n' "$DIM" "$N"
fi

[ "$have_devid" = 1 ] && ok "notarized distribution outside the App Store (Developer ID)"
[ "$have_dist"  = 1 ] && ok "App Store submission (distribution certificate)"
[ "$have_devid" = 1 ] && [ "$have_dev" = 0 ] && \
  warn "Developer ID signs *shipping* apps; it cannot sign day-to-day development builds"

echo
[ "$have_dev" = 1 ] && exit 0 || exit 1
