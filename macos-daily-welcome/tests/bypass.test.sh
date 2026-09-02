#!/bin/bash
# Letting somebody in for one conversation, and the greeting that gives
# the game away.
#
# "Hi Arjun, what can I do for you" said to whoever happens to be
# standing there is both wrong and a way of telling a stranger your name.
# And when a voice is turned away, the person whose Mac it is has to be
# able to say "yes, I know, let them in" without the person being let in
# being able to say it for themselves.

test_sandbox
load_orbit

# ------------------------------------------------------------- the code

says_it() { if bypass_code_said "$1"; then ok "\"$1\" is the code" y y
            else ok "\"$1\" is the code" y n; fi; }
does_not() { if bypass_code_said "$1"; then ok "\"$1\" is not" n y
             else ok "\"$1\" is not" n n; fi; }

says_it "bypass 727590"
# A recogniser writes spoken digits as words as often as figures, and
# puts commas through the middle of a long number.
says_it "bypass seven two seven five nine zero"
says_it "bypass 727,590"
says_it "Bypass 727590."
says_it "orbit bypass seven two seven five nine oh"
does_not "bypass 727591"
does_not "bypass"
does_not "what time is it"
does_not "set a timer for seven minutes"

# The code is a setting, not a constant.
ok "a different code is a different code" "y" \
   "$(ORBIT_BYPASS_CODE=1234 bypass_code_said "bypass 1234" && echo y || echo n)"
ok "and the old one stops working" "n" \
   "$(ORBIT_BYPASS_CODE=1234 bypass_code_said "bypass 727590" && echo y || echo n)"

# ---------------------------------------------------------- the door itself

ok "closed to begin with" "1" "$(bypass_active; echo $?)"
bypass_grant Arjun
ok "open once granted" "0" "$(bypass_active; echo $?)"
ok "and says how long is left" "$ORBIT_BYPASS_MINUTES" "$(bypass_minutes_left)"

# A door propped open and forgotten is not a door.
touch -d "$((ORBIT_BYPASS_MINUTES + 5)) minutes ago" "$WELCOME_STATE_DIR/bypass"
ok "it expires" "1" "$(bypass_active; echo $?)"
ok "and cleans up after itself" "" \
   "$(ls "$WELCOME_STATE_DIR/bypass" 2>/dev/null)"

bypass_grant Arjun
bypass_end
ok "and can be closed by hand" "1" "$(bypass_active; echo $?)"

# ----------------------------------------------------------- who may grant it

body="$(sed -n '/bypass_code_said "\$transcript"/,/^    fi$/p' "$TEST_ROOT/bin/orbit")"
contains "granting needs a voice it recognises" 'bypass_speaker' "$body"
contains "an unknown voice saying it is refused"  "I do not know your voice" "$body"
contains "and that refusal is recorded"           "memory_log_event refused" "$body"
contains "the phrase is heard before the gate can refuse it" "bypass_code_said" \
  "$(sed -n '/plan)/,/speaker_check || exit 0/p' "$TEST_ROOT/bin/orbit")"

# The bypass is consulted before anything else, ban included. It used to
# apply only to a voice with no name, which meant it never applied to the
# voices most worth waving through - see tests/gate.test.sh, which drives
# the whole thing for real rather than reading it.
# speaker_check lives in bin/orbit, not a library, so it is read rather
# than called.
gate="$(sed -n '/^speaker_check() {/,/^}/p' "$TEST_ROOT/bin/orbit")"
before_ban="$(printf '%s' "$gate" | sed -n '1,/= "banned"/p')"
contains "the bypass is checked first" "bypass_active" "$before_ban"
lacks "and not only for a nameless voice" '[ -z "$SPEAKER" ] && bypass_active' "$gate"
ok "the ban check still runs after it" "yes" \
   "$(printf '%s' "$gate" | grep -q 'banned' && echo yes || echo no)"

# The conversation it was scoped to ending should end it.
swift="$(cat "$TEST_ROOT/menubar/listener.swift")"
contains "the app clears it when a conversation ends" "bypassPath" "$swift"
contains "on the turn that ends one" "if ended, !bypassPath.isEmpty" "$swift"

# ------------------------------------------------------------- the greeting

greet="$(sed -n '/^  greeting)/,/^    ;;/p' "$TEST_ROOT/bin/orbit")"
contains "the greeting asks who is there"     "speaker_identify" "$greet"
contains "a banned voice gets refused at hello" "speaker_refusal_banned" "$greet"
contains "an unknown one is answered without a name" "ORBIT_GREETING_UNKNOWN" "$greet"
lacks "and never with the name by default" 'emit "$ORBIT_GREETING" false ""
    exit 0
    fi' "$greet"

# Two words is rarely enough voice to identify anybody, so not knowing
# is the ordinary case and must not be a refusal.
lacks "not knowing is not a refusal" "speaker_refusal_unknown" "$greet"
ok "the nameless greeting says nothing about anyone" "n" \
   "$(printf '%s' "$ORBIT_GREETING_UNKNOWN" | grep -qi "$WELCOME_NAME" && echo y || echo n)"

# With recognition off entirely, nothing changes for anybody.
contains "recognition off means the old greeting" "speaker_enabled" "$greet"


# ------------------------------------------- still listening after the refusal
#
# A refusal used to close the microphone, so letting somebody in meant
# saying the wake word again first. That is a lot to ask of somebody
# standing in their own kitchen watching a friend be told off.

ok "the window is shut to begin with" "1" "$(bypass_window_open; echo $?)"
bypass_window_start
ok "and opens when somebody is turned away" "0" "$(bypass_window_open; echo $?)"

touch -d "$((ORBIT_BYPASS_LISTEN_SECONDS + 10)) seconds ago" \
  "$WELCOME_STATE_DIR/bypass-window"
ok "it does not stay open" "1" "$(bypass_window_open; echo $?)"
ok "and tidies up after itself" "" "$(ls "$WELCOME_STATE_DIR/bypass-window" 2>/dev/null)"

bypass_window_start; bypass_window_end
ok "and closes on demand" "1" "$(bypass_window_open; echo $?)"

# The refusal keeps the microphone open: end false, listen true.
gate="$(sed -n '/^speaker_check() {/,/^}/p' "$TEST_ROOT/bin/orbit")"
unknown="$(printf '%s' "$gate" | sed -n '/Turned away a voice/,/return 1/p')"
contains "the refusal keeps listening" 'emit "$(speaker_refusal_unknown)" false "" false true' "$unknown"
contains "and opens the window as it does"  "bypass_window_start" "$unknown"

# But it says it ONCE. Repeating an insult at every sentence is a machine
# having a tantrum, and it would talk over the one person who could put
# it right.
quiet="$(printf '%s' "$gate" | sed -n '/bypass_window_open; then/,/return 1/p')"
contains "a second sentence gets silence" 'emit "" false "" false true' "$quiet"
lacks "not the insult again"              "speaker_refusal_unknown"   "$quiet"

# A ban is refused like anything else, and keeps listening like anything
# else: a code that cannot be said straight back may as well not exist.
banned="$(printf '%s' "$gate" | sed -n '/= "banned"/,/return 1/p')"
contains "a ban keeps listening too" 'emit "$(speaker_refusal_banned)" false "" false true' "$banned"
contains "and remembers who it refused" 'bypass_window_start "$SPEAKER"' "$banned"

# Somebody who belongs here talking means whatever that was is over.
contains "a recognised voice closes the window" "bypass_window_end" "$gate"

# Granting keeps the microphone open too - the person just let in was
# halfway through a sentence when they were interrupted.
grant="$(sed -n '/bypass_grant "\$bypass_speaker"/,/^      else$/p' "$TEST_ROOT/bin/orbit")"
contains "granting listens on"      'false true' "$grant"
contains "and closes the window"    "bypass_window_end" "$grant"
