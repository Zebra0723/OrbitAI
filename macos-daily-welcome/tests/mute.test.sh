#!/bin/bash
# Muted means silent. Not "quieter", not "except for timers" - nothing.
#
# Every way Orbit can make a sound is tried here with the mute on, against
# stand-ins for `say`, `afplay` and `osascript` that write down whatever
# they were asked to play. A single line in that record is a failure.

test_sandbox
load_orbit
# Other test files define shell functions with these names, and a function
# outranks anything on PATH. Clear them so the stand-ins below are what runs.
unset -f say afplay osascript 2>/dev/null
saved_path="$PATH"

fakes="$WELCOME_STATE_DIR/fakes"
sounds="$WELCOME_STATE_DIR/sounds.log"
mkdir -p "$fakes"
for tool in say afplay; do
  printf '#!/bin/bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$tool" "$sounds" > "$fakes/$tool"
  chmod +x "$fakes/$tool"
done
printf '#!/bin/bash\nprintf "osascript %%s\\n" "$*" >> "%s"\n' "$sounds" > "$fakes/osascript"
chmod +x "$fakes/osascript"
export PATH="$fakes:$PATH"
export WELCOME_SPEAK=1 WELCOME_TTS=say

audio="$WELCOME_STATE_DIR/reply.mp3"
printf 'not really audio' > "$audio"
heard() { cat "$sounds" 2>/dev/null; }
quiet_now() { : > "$sounds"; }

# ------------------------------------------------------ the stand-ins work
quiet_now
say_speak "hello"
contains "unmuted, say really is called" "say" "$(heard)"
quiet_now
play_file "$audio"
contains "unmuted, afplay really is called" "afplay" "$(heard)"

# ------------------------------------------------------ muted: not a sound
printf 'never\n' > "$(orbit_mute_file)"
succeeds "a mute with no end is in force" orbit_muted

quiet_now
say_speak "hello"
play_file "$audio"
speak_async "hello"; [ -n "${WELCOME_SPEAK_PID:-}" ] && wait "$WELCOME_SPEAK_PID" 2>/dev/null
eleven_speak "hello"
openai_speak "hello"
piper_speak "hello"
ok "muted: nothing at all reaches the speaker" "" "$(heard)"
fails "muted: there is no audio to hand the menu bar app" speak_to_file "hello"

# A mute that has gone wrong fails silent, never talking.
printf 'garbage\n' > "$(orbit_mute_file)"
succeeds "an unreadable mute still counts as muted" orbit_muted
printf '\n' > "$(orbit_mute_file)"
succeeds "and so does an empty one" orbit_muted

# One that has run out ends by itself.
printf '%s\n' "$(( $(date +%s) - 5 ))" > "$(orbit_mute_file)"
fails "a mute whose time is up is over" orbit_muted
ok "and its file is cleared" "no" "$([ -f "$(orbit_mute_file)" ] && echo yes || echo no)"
printf '%s\n' "$(( $(date +%s) + 600 ))" > "$(orbit_mute_file)"
succeeds "one with time left is still on" orbit_muted
orbit_unmute

# ------------------------------------------------------ how long
now="$(date +%s)"
near() { # near DESCRIPTION EXPECTED ACTUAL - within a few seconds
  local d=$(( ${3:-0} - $2 )); [ "$d" -lt 0 ] && d=$(( -d ))
  ok "$1" "yes" "$([ "$d" -le 5 ] && echo yes || echo no)"
}
ok "nothing means until unmuted"       "never" "$(orbit_mute_until "")"
ok "so does 'until I unmute you'"      "never" "$(orbit_mute_until "until I unmute you")"
ok "and 'indefinitely'"                "never" "$(orbit_mute_until "indefinitely")"
near "45m"                  $((now + 2700))   "$(orbit_mute_until 45m)"
near "2h"                   $((now + 7200))   "$(orbit_mute_until 2h)"
near "1h30m"                $((now + 5400))   "$(orbit_mute_until 1h30m)"
near "a bare 90 is minutes" $((now + 5400))   "$(orbit_mute_until 90)"
near "1d"                   $((now + 86400))  "$(orbit_mute_until 1d)"
near "'for two hours'"      $((now + 7200))   "$(orbit_mute_until "for two hours")"
near "'half an hour'"       $((now + 1800))   "$(orbit_mute_until "half an hour")"
near "'3 days'"             $((now + 259200)) "$(orbit_mute_until "3 days")"
until="$(orbit_mute_until "until 7:30")"
ok "'until 7:30' is within the next day" "yes" \
   "$([ "$until" -gt "$now" ] && [ "$until" -le $((now + 86400)) ] && echo yes || echo no)"
ok "and lands on 7:30" "07:30" "$(_epoch_format "$until" '+%H:%M')"
ok "'until 7pm' lands on 19:00" "19:00" "$(_epoch_format "$(orbit_mute_until "until 7pm")" '+%H:%M')"
fails "a length it can't read is refused" orbit_mute_until "until the cows come home"

# ------------------------------------------------------ saying it
intent() { parse_intent "$1" | cut -f1,2 | tr '\t' ' '; }
ok "'mute yourself for two hours'" "quiet mute" "$(intent "mute yourself for two hours")"
ok "'be quiet'"                    "quiet mute" "$(intent "be quiet")"
ok "'go quiet until 7:30'"         "quiet mute" "$(intent "go quiet until 7:30")"
ok "'stop talking for an hour'"    "quiet mute" "$(intent "stop talking for an hour")"
ok "'unmute yourself'"             "quiet unmute" "$(intent "unmute yourself")"
ok "'you can talk again'"          "quiet unmute" "$(intent "you can talk again")"
ok "it keeps how long"             "for two hours" "$(parse_intent "mute yourself for two hours" | cut -f3)"
lacks "plain 'mute' is still the Mac's volume" "quiet" "$(intent "mute")"

# ------------------------------------------------------ the real thing
orbit() { "$TEST_ROOT/bin/orbit" "$@"; }

quiet_now
out="$(orbit plan "mute yourself for an hour")"
contains "muting answers in text"            "Muted until" "$out"
contains "with no audio to play"             '"audio":""' "$out"
succeeds "and the mute is on"                orbit_muted
orbit say "hello" >/dev/null
out="$(orbit plan "what time is it")"
contains "a command while muted is still answered in text" '"speak":"' "$out"
contains "but with no audio"                 '"audio":""' "$out"
ok "muted: orbit say and orbit plan made no sound" "" "$(heard)"

orbit unmute >/dev/null
fails "orbit unmute ends it" orbit_muted
orbit say "hello" >/dev/null
contains "and then it can speak again" "say" "$(heard)"

out="$(orbit mute 2h)"
contains "orbit mute 2h says until when" "Muted until" "$out"
contains "orbit mute status agrees" "Muted until" "$(orbit mute status)"
orbit mute off >/dev/null
ok "orbit mute off unmutes" "Not muted." "$(orbit mute status)"
fails "orbit mute refuses nonsense" orbit mute "until the cows come home"
fails "and nonsense leaves it unmuted" orbit_muted

# ------------------------------------------------------ never unprompted
# A timer fires minutes after anyone spoke. It must not speak, muted or not:
# a silent notification and nothing else.
quiet_now
orbit timer-fire 0
lacks "a timer going off does not speak"       "say "    "$(heard)"
lacks "or play anything"                       "afplay " "$(heard)"
contains "it posts a notification instead"     "display notification" "$(heard)"
lacks "and the notification makes no sound"    "sound name" "$(heard)"

# The menu bar app's periodic tick used to ask this to speak first.
quiet_now
orbit watch
ok "orbit watch says nothing, ever" "" "$(heard)"

# Leave the shell as it was found: the files after this one share it.
export PATH="$saved_path"
export WELCOME_SPEAK=0
unset -f orbit near heard quiet_now intent 2>/dev/null
test_sandbox_clean
