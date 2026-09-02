#!/bin/bash
# The installer, as far as it can be checked without a Mac.
#
# This is the command run at the start of every session - `git pull &&
# ./install.sh` - so a mistake in it is the first thing anybody meets. It
# used to delete the app bundle before compiling, which meant a Swift
# file that did not build left the Mac with no menu bar app, no
# listening, and a script that had already stopped.

test_sandbox

src="$TEST_ROOT/install.sh"

succeeds "the installer parses" bash -n "$src"

# Build first, replace second.
body="$(cat "$src")"
lacks "the app is not deleted before it is rebuilt" 'rm -rf "$APP_DIR"
    mkdir' "$body"
contains "it builds beside the app"      'BUILD_DIR="$APP_DIR.building"' "$body"
contains "compiles into there"           'swiftc -O -o "$BUILD_DIR' "$body"
contains "and only then replaces it"     'mv "$BUILD_DIR" "$APP_DIR"'   "$body"

# A failed compile has to be noticed, not walked past.
contains "a compile failure stops the install" 'if ! swiftc' "$body"
contains "and says so"    "did not compile"                 "$body"
contains "and puts back what it stopped" "launchctl kickstart" "$body"

# Half a bundle is never left lying around.
contains "the part-built bundle is cleaned up on the way out" \
  "trap 'rm -rf \"\$BUILD_DIR\"' EXIT" "$body"

# Every Swift file in menubar/ is handed to the compiler. One added and
# not listed here builds fine and does nothing.
for f in "$TEST_ROOT"/menubar/*.swift; do
  contains "$(basename "$f") is compiled into the app" "$(basename "$f")" "$body"
done

# The usage strings macOS shows when it asks. A missing one is not a
# prompt with no text - it is a permission that cannot be granted at all,
# and on newer systems a crash.
for key in NSMicrophoneUsageDescription NSSpeechRecognitionUsageDescription \
           NSAppleEventsUsageDescription NSRemindersFullAccessUsageDescription \
           NSCalendarsFullAccessUsageDescription NSContactsUsageDescription; do
  contains "the app asks for $key properly" "<key>$key</key>" "$body"
done

# Menu bar only.
contains "no Dock icon" "<key>LSUIElement</key><true/>" "$body"

# The uninstaller undoes what the installer does.
un="$(cat "$TEST_ROOT/uninstall.sh")"
succeeds "the uninstaller parses" bash -n "$TEST_ROOT/uninstall.sh"
for thing in "DailyWelcome.app" "LaunchAgents" ".local/bin"; do
  contains "uninstall knows about $thing" "$thing" "$un"
done
