#!/bin/bash
# What doctor says, since it is what gets run when something is wrong.
#
# It cannot be run here - the first thing it does is establish that this
# is not a Mac and stop - so the sections that matter are exercised on
# their own, with the Mac's commands stubbed in.

test_sandbox
load_orbit

src="$TEST_ROOT/bin/doctor"
body="$(cat "$src")"

succeeds "doctor parses" bash -n "$src"

# It has to stop on anything that is not a Mac, and say why.
contains "it knows what it needs" 'uname -s' "$body"
contains "and says so plainly"    "not macOS"  "$body"

# The voice section is the one people read. It has to name the voice you
# will actually hear, not just list what is configured: three providers
# and a fallback, and the answer is whichever one wins.
contains "it asks which backend will speak" "tts_backend"          "$body"
contains "it checks ElevenLabs"             "eleven_available"     "$body"
contains "it checks OpenAI"                 "openai_tts_available" "$body"
contains "it checks piper"                  "piper_available"      "$body"
contains "and names what you will hear"     "It will speak with"   "$body"

# The setting the user is most likely to be halfway through.
contains "it reports voice recognition" "ORBIT_SPEAKER_ID"       "$body"
contains "including nobody enrolled yet" "speaker_enrolled_count" "$body"
contains "and nothing to identify from"  "speaker_have_audio"     "$body"

# Every fix line has to be something you can do: a command, or a place in
# System Settings to go. An explanation behind the same arrow means the
# arrows stop meaning anything - there is bad_note for those.
bad_fixes="$(printf '%s\n' "$body" \
  | sed -nE 's/^[[:space:]]*fix "([^"]+)".*/\1/p' \
  | grep -vE '^(daily-welcome|orbit|brew|cd|\./|xcode-select|open|npm|npx|echo|launchctl|sudo|Privacy & Security|System Settings|Set |Add )' \
  | head -5)"
ok "every suggested fix starts with something you can do" "" "$bad_fixes"

# The three commands doctor points at have to exist.
for cmd in "--setup-piper" "--setup-speaker" "--mac-voices" "--test-voice"; do
  contains "daily-welcome really has $cmd" "$cmd)" "$(cat "$TEST_ROOT/bin/daily-welcome")"
done
contains "orbit really has voice enroll" "enroll|enrol)" "$(cat "$TEST_ROOT/bin/orbit")"
