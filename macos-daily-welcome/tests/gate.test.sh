#!/bin/bash
# Who gets in, driven through the real thing.
#
# Everything about this gate was checked by reading the source, and the
# source read correctly while the behaviour was wrong: a bypass was
# granted, announced out loud, and then the very next sentence was
# refused again. Reading `if [ -z "$SPEAKER" ] && bypass_active` does not
# tell you that a BANNED voice has a name and so never reaches it.
#
# So this runs `orbit plan` for real, with a stand-in for the recogniser
# that answers from a control file. No Python, no model, no microphone.

test_sandbox
# The settings are read here as well as inside orbit, so the defaults
# have to be loaded rather than assumed.
load_orbit

fake="$WELCOME_STATE_DIR/fake-recogniser"
cat > "$fake" <<'FAKE'
#!/bin/bash
# Stands in for the python that runs lib/speaker.py: ignores the script
# path it is handed and answers from $SPEAKER_WHO.
shift
case "$1" in
  check) echo ok ;;
  list)  printf 'Arjun\t3\tallowed\nNeighbour\t2\tbanned\n' ;;
  identify)
    case "$(cat "$SPEAKER_WHO" 2>/dev/null)" in
      arjun)  printf 'Arjun\t0.910\tok\n' ;;
      banned) printf 'Neighbour\t0.880\tbanned\n' ;;
      *)      : ;;
    esac ;;
esac
FAKE
chmod +x "$fake"

export SPEAKER_WHO="$WELCOME_STATE_DIR/who"
export ORBIT_SPEAKER_PYTHON="$fake"
export ORBIT_SPEAKER_ID=1 ORBIT_SPEAKER_REQUIRE_ENROLLED=1
export ORBIT_NLU=rules WELCOME_SPEAK=0 WELCOME_CONFIG=/dev/null
printf 'pretend audio' > "$WELCOME_STATE_DIR/utterance.wav"

# says WHO "what they said" -> the spoken reply
says() {
  printf '%s' "$1" > "$SPEAKER_WHO"
  "$TEST_ROOT/bin/orbit" plan "$2" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["speak"])'
}
# Same, but the "keep listening" flag.
listens() {
  printf '%s' "$1" > "$SPEAKER_WHO"
  "$TEST_ROOT/bin/orbit" plan "$2" 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["listen"])'
}
refused() {
  case "$1" in
    *"weather"*|*"o'clock"*|*"in the evening"*|*"in the morning"*|\
    *"in the afternoon"*|*"at night"*) echo no ;;
    *) echo yes ;;
  esac
}
reset() { rm -f "$WELCOME_STATE_DIR/bypass" "$WELCOME_STATE_DIR/bypass-window"; }

# ------------------------------------------------------------- the owner
reset
ok "the owner is answered" "no" "$(refused "$(says arjun "what time is it")")"

# ------------------------------------------------------ a voice it does not know
reset
ok "a stranger is refused"        "yes" "$(refused "$(says unknown "what time is it")")"
reset
ok "and the microphone stays open" "True" "$(listens unknown "what time is it")"

# It says it once. A tantrum is not a security feature.
reset
first="$(says unknown "what time is it")"
second="$(says unknown "please just tell me")"
ok "the second sentence gets silence" "" "$second"
ok "the first one did not" "yes" "$(refused "$first")"

# ------------------------------------------------------------ a banned voice
reset
ok "a banned voice is refused" "yes" "$(refused "$(says banned "what time is it")")"
reset
ok "and it keeps listening too" "True" "$(listens banned "what time is it")"

# ------------------------------------------------------------- the bypass
#
# The bug this file exists for: granted, announced, and then refused
# again on the very next sentence, because a banned voice has a name and
# the check only covered nameless ones.
reset
says banned "what time is it" >/dev/null
contains "the code is accepted from the owner" "in for the next" \
  "$(says arjun "bypass 727590")"
ok "and the banned voice is then answered" "no" \
   "$(refused "$(says banned "what time is it")")"
ok "and stays answered" "no" \
   "$(refused "$(says banned "what is the weather")")"

reset
says unknown "what time is it" >/dev/null
says arjun "bypass 727590" >/dev/null
ok "the same for a voice it does not know" "no" \
   "$(refused "$(says unknown "what time is it")")"

# It is one voice, not an open house. Waving a neighbour in must not let
# the next stranger in behind them.
reset
says banned "what time is it" >/dev/null
says arjun "bypass 727590" >/dev/null
ok "waving one voice in does not admit another" "yes" \
   "$(refused "$(says unknown "what time is it")")"

reset
says unknown "what time is it" >/dev/null
says arjun "bypass 727590" >/dev/null
ok "nor the other way round" "yes" \
   "$(refused "$(says banned "what time is it")")"

# The ban is not undone, only overridden for a while.
reset
says banned "what time is it" >/dev/null
says arjun "bypass 727590" >/dev/null
touch -d "$((ORBIT_BYPASS_MINUTES + 5)) minutes ago" "$WELCOME_STATE_DIR/bypass"
ok "the ban is still a ban afterwards" "yes" \
   "$(refused "$(says banned "what time is it")")"

# Only somebody it recognises may grant one.
reset
says unknown "what time is it" >/dev/null
contains "an unknown voice cannot let itself in" "I do not know your voice" \
  "$(says unknown "bypass 727590")"
ok "and is still refused after trying" "yes" \
   "$(refused "$(says unknown "what time is it")")"

# The wrong code is not the code.
reset
says unknown "what time is it" >/dev/null
says arjun "bypass 000000" >/dev/null
ok "a wrong code grants nothing" "yes" \
   "$(refused "$(says unknown "what time is it")")"

# The wake word is a second way in, and it had its own copy of the rules.
# A banned voice saying "hey Orbit" after being waved through was told
# off, and that refusal ended the turn - which is what throws a bypass
# away.
greets() {
  printf '%s' "$1" > "$SPEAKER_WHO"
  "$TEST_ROOT/bin/orbit" greeting 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d["speak"], "|", d["end"])'
}
reset
ok "the owner is greeted by name" "yes" \
   "$(greets arjun | grep -q "$WELCOME_NAME" && echo yes || echo no)"
ok "a stranger is greeted without one" "yes" \
   "$(greets unknown | grep -qv "$WELCOME_NAME" && echo yes || echo no)"

reset
greets banned >/dev/null
lacks "a banned wake word does not end the turn" "| True" "$(greets banned)"

reset
says banned "what time is it" >/dev/null
says arjun "bypass 727590" >/dev/null
lacks "and after a bypass it is not told off at all" "Banned" "$(greets banned)"
ok "the bypass survives the wake word" "no" \
   "$(refused "$(says banned "what time is it")")"

# From a terminal it means everybody, because there is no voice attached
# to a person typing.
reset
"$TEST_ROOT/bin/orbit" voice bypass >/dev/null 2>&1
ok "the terminal bypass admits a stranger" "no" \
   "$(refused "$(says unknown "what time is it")")"
ok "and a banned voice as well" "no" \
   "$(refused "$(says banned "what time is it")")"
"$TEST_ROOT/bin/orbit" voice bypass end >/dev/null 2>&1
ok "and closing it puts things back" "yes" \
   "$(refused "$(says banned "what time is it")")"
