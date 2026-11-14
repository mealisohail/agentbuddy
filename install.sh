#!/bin/sh
# AgentBuddy installer — downloads the latest release into ~/Applications and opens it.
#   curl -fsSL https://raw.githubusercontent.com/OWNER/agentbuddy/main/install.sh | sh
# Nothing here needs sudo. Read it first if you like; it's short.
set -e
REPO="${AGENTBUDDY_REPO:-OWNER/agentbuddy}"
DEST="$HOME/Applications"
URL="${AGENTBUDDY_URL:-https://github.com/$REPO/releases/latest/download/AgentBuddy.zip}"

fail() { echo "AgentBuddy install failed: $1" >&2; exit 1; }
[ "$(uname -s)" = "Darwin" ] || fail "AgentBuddy is a macOS app."
MAJOR=$(sw_vers -productVersion | cut -d. -f1)
[ "$MAJOR" -ge 14 ] || fail "needs macOS 14 (Sonoma) or newer; this Mac has $(sw_vers -productVersion)."

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
echo "Downloading AgentBuddy…"
curl -fL --progress-bar "$URL" -o "$TMP/AgentBuddy.zip" || fail "couldn't download $URL"
ditto -x -k "$TMP/AgentBuddy.zip" "$TMP" || fail "the download isn't a valid zip"
[ -d "$TMP/AgentBuddy.app" ] || fail "the zip doesn't contain AgentBuddy.app"

# replace a running copy cleanly
osascript -e 'tell application id "dev.agentbuddy.app" to quit' >/dev/null 2>&1 || true
sleep 1
pkill -x AgentBuddy 2>/dev/null || true

mkdir -p "$DEST"
rm -rf "$DEST/AgentBuddy.app"
mv "$TMP/AgentBuddy.app" "$DEST/"
# The app isn't notarized (that needs a paid Apple account), so make sure macOS doesn't block it as "downloaded".
xattr -dr com.apple.quarantine "$DEST/AgentBuddy.app" 2>/dev/null || true

open "$DEST/AgentBuddy.app"
echo "Installed $DEST/AgentBuddy.app — look for the robot by your notch / menu bar."
