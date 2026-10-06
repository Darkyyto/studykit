#!/bin/sh
set -eu

REPOSITORY="Darkyyto/studykit"
URL="https://github.com/$REPOSITORY/releases/latest/download/FocusKit.dmg"
WORK="$(mktemp -d)"
trap 'hdiutil detach -quiet "$WORK/volume" 2>/dev/null || true; rm -rf "$WORK"' EXIT

echo "Downloading FocusKit…"
curl -fsSL "$URL" -o "$WORK/FocusKit.dmg"

hdiutil attach -quiet -nobrowse -readonly -mountpoint "$WORK/volume" "$WORK/FocusKit.dmg"

if pgrep -x FocusKit >/dev/null 2>&1; then
  echo "Closing FocusKit…"
  osascript -e 'tell application id "dev.focuskit.FocusKit" to quit' >/dev/null 2>&1 || true
  waited=0
  while pgrep -x FocusKit >/dev/null 2>&1; do
    sleep 0.5
    waited=$((waited + 1))
    if [ "$waited" -eq 10 ]; then
      echo "FocusKit is still open. Quit it with ⌘Q and the update continues."
    fi
  done
fi

echo "Installing in Applications…"
rm -rf /Applications/FocusKit.app
cp -R "$WORK/volume/FocusKit.app" /Applications/
xattr -dr com.apple.quarantine /Applications/FocusKit.app 2>/dev/null || true

open /Applications/FocusKit.app
echo "FocusKit is ready. Your sessions and lectures are where you left them."
