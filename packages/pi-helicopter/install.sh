#!/bin/bash
set -euo pipefail

TAP="duarteocarmo/pi-tools"
TAP_URL="https://github.com/duarteocarmo/pi-tools"
CASK="$TAP/pi-helicopter"
APP="/Applications/Pi Helicopter.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Pi Helicopter requires macOS." >&2
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Install it from https://brew.sh and run this installer again." >&2
    exit 1
fi

export HOMEBREW_NO_ASK=1
brew tap "$TAP" "$TAP_URL"
if brew tap | grep -qx "duarteocarmo/tap"; then
    if brew list --cask pi-helicopter >/dev/null 2>&1; then
        brew uninstall --cask pi-helicopter
    fi
    brew untap duarteocarmo/tap
fi

if brew list --cask pi-helicopter >/dev/null 2>&1; then
    brew upgrade --cask "$CASK"
else
    brew install --cask "$CASK"
fi

echo "Pi Helicopter is installed."
open "$APP" >/dev/null 2>&1 || true
sleep 2

if ! pgrep -f "$APP/Contents/MacOS/pi-helicopter" >/dev/null 2>&1; then
    echo "macOS blocked the first launch. In Privacy & Security, click Open Anyway for Pi Helicopter."
    open "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension" >/dev/null 2>&1 || true
else
    echo "Pi Helicopter is running."
fi
