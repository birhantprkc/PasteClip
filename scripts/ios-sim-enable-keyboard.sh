#!/bin/bash
# Simulator setup for the keyboard UI tests.
# - Adds the Clipbara keyboard to the keyboard list.
# - Keeps the software keyboard on screen even though the Mac keyboard counts as a
#   hardware keyboard (otherwise no keyboard, custom or not, is shown).
# The UI test testEnableKeyboardInSettings still has to switch it on in Settings in the
# same xcodebuild run, because reinstalling the app turns it off again.
# Usage: scripts/ios-sim-enable-keyboard.sh <simulator-udid>
set -euo pipefail
SIM="${1:?simulator udid}"
xcrun simctl spawn "$SIM" defaults write .GlobalPreferences AppleKeyboards -array \
  "ko_KR@sw=Korean;hw=Automatic" "en_US@sw=QWERTY;hw=Automatic" "emoji@sw=Emoji" "com.minsang.Clipbara.keyboard"
xcrun simctl spawn "$SIM" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false
echo "Clipbara keyboard test setup done on $SIM"
