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

# ---------------------------------------------------- the one-line install
#
# install.sh builds a Swift app out of the files sitting next to it, so
# it cannot be piped into bash from a URL - there would be nothing next
# to it. bootstrap.sh is the part before: fetch the repository, then hand
# over. It is the only terminal left in the whole product, so the things
# that would make it fail silently are worth pinning down.
boot="$TEST_ROOT/bootstrap.sh"
succeeds "the bootstrap parses" bash -n "$boot"
ok "and is executable" "yes" "$([ -x "$boot" ] && echo yes || echo no)"
body="$(cat "$boot")"

# Piped into bash, stdin IS the script. Anything that stops to ask a
# question is asking the script, gets whatever is left of itself, and
# hangs or does something surprising.
ok "it never asks a question" "" \
   "$(grep -n 'read -[rp]' "$boot" | head -3)"
contains "it says so, so the next person does not add one" "nobody to answer" "$body"

# A second run has to update rather than install a second copy.
contains "running it again updates what is there" "reset --quiet --hard" "$body"
contains "it says why a merge would be wrong" "half-merged" "$body"

# Nothing to build with is the commonest way this fails, and both tools
# come from the same Apple download.
contains "it checks for git" "command -v git" "$body"
contains "and names the fix" "xcode-select --install" "$body"
contains "it notices swiftc is missing" "command -v swiftc" "$body"
contains "and does not stop for it" "no menu bar app" "$body"
contains "it refuses to run anywhere but a Mac" "Darwin" "$body"

# The line printed on the website has to point at a file that is really
# there, at really that path. Move the file and this is the check that
# notices, rather than a stranger's first minute with the product.
line="$(grep -o 'curl -fsSL [^"<]*bootstrap.sh[^"<]*' "$TEST_ROOT/web/orbitai/setup.html" | head -1)"
ok "the website has an install line" "yes" "$([ -n "$line" ] && echo yes || echo no)"
path="$(printf '%s' "$line" | sed -E 's#.*/main/##; s/ .*//')"
ok "and it points at a file that exists" "yes" \
   "$([ -f "$TEST_ROOT/../$path" ] && echo yes || echo no)"
