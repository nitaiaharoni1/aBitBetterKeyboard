#!/bin/bash
# Puts the iPhone 17 Pro simulator into the one state where the stock keyboard can
# be photographed: Hebrew installed, software keyboard on screen, predictions on.
# Idempotent — run it as many times as you like.
#
#   Bar/typing/setup-simulator.sh
#
# The one non-obvious part is the software keyboard. During a UI test the runner
# looks like an attached hardware keyboard, so iOS minimises the on-screen one and
# every key lands off-screen at y≈959 on an 874pt display. Two switches undo that:
# the Simulator's I/O ▸ Keyboard ▸ Connect Hardware Keyboard menu item, and the
# device's own AutomaticMinimizationEnabled preference.

set -euo pipefail

DEVICE="${DEVICE:-iPhone 17 Pro}"

udid=$(xcrun simctl list devices available \
  | grep -F "$DEVICE (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
[ -n "$udid" ] || { echo "no simulator named '$DEVICE'" >&2; exit 1; }
echo "device: $DEVICE ($udid)"

xcrun simctl list devices | grep -q "$udid) (Booted)" || {
  echo "booting…"
  xcrun simctl boot "$udid"
  sleep 12
}
open -a Simulator --args -CurrentDeviceUDID "$udid"
sleep 3

# --- keyboards -------------------------------------------------------------
# Hebrew has to be an installed keyboard before anything can switch to it.
current=$(xcrun simctl spawn "$udid" defaults read .GlobalPreferences AppleKeyboards 2>/dev/null || echo "")
if ! grep -q "he_IL" <<<"$current"; then
  echo "adding the Hebrew keyboard…"
  xcrun simctl spawn "$udid" defaults write .GlobalPreferences AppleKeyboards -array \
    "en_US@sw=QWERTY;hw=Automatic" "he_IL@sw=Hebrew;hw=Automatic" "emoji@sw=Emoji"
  echo "  restart the device for it to take: xcrun simctl shutdown $udid && xcrun simctl boot $udid"
else
  echo "hebrew keyboard: present"
fi

# --- autocorrect and predictions -------------------------------------------
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences KeyboardAutocorrection -bool true
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences KeyboardPrediction -bool true
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences KeyboardShowPredictionBar -bool true

# --- keep the software keyboard on screen ----------------------------------
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false
xcrun simctl spawn "$udid" defaults write com.apple.keyboard.preferences HardwareKeyboardLastSeen -bool false
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false

# Unchecking the menu item is what actually detaches the keyboard from the running
# device. The mark character makes this safe to repeat.
osascript <<'APPLESCRIPT'
tell application "System Events"
  if not (exists process "Simulator") then return "Simulator not running"
  tell process "Simulator"
    set mi to menu item "Connect Hardware Keyboard" of menu 1 of ¬
      menu item "Keyboard" of menu 1 of menu bar item "I/O" of menu bar 1
    if (value of attribute "AXMenuItemMarkChar" of mi) is "✓" then
      click menu bar item "I/O" of menu bar 1
      delay 0.5
      click menu item "Keyboard" of menu 1 of menu bar item "I/O" of menu bar 1
      delay 0.5
      click mi
      delay 1
      return "hardware keyboard: disconnected"
    end if
    return "hardware keyboard: already disconnected"
  end tell
end tell
APPLESCRIPT

echo
echo "ready. If the capture still reports the keyboard off-screen, the device is"
echo "holding a minimised keyboard from an earlier session — reboot it:"
echo "  xcrun simctl shutdown $udid && xcrun simctl boot $udid"
