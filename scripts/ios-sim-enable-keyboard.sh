#!/bin/bash
# Makes the Clipbara keyboard the first keyboard on a Simulator, for UI tests and screenshots.
# Usage: scripts/ios-sim-enable-keyboard.sh <simulator-udid>
set -euo pipefail
SIM="${1:?simulator udid}"
xcrun simctl spawn "$SIM" defaults write .GlobalPreferences AppleKeyboards -array \
  "com.minsang.Clipbara.keyboard" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji"
echo "Clipbara keyboard enabled on $SIM"
