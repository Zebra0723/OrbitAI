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
      # A short sentence, a bit of noise, and it declines to name
      # anybody. The ordinary case, not an exotic one.
      hazy)   : ;;
      *)      : ;;
    esac ;;
esac
FAKE
chmod +x "$fake"

export SPEAKER_WHO="$WELCOME_STATE_DIR/who"
export ORBIT_SPEAKER_PYTHON="$fake"
# Turned on deliberately: refusing people is off by default, because a
# recogniser that is wrong once stops the assistant working for the
# person who owns it.
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

# A live bypass is live for anybody, and that is on purpose.
#
# It used to insist the voice match the one it was granted for, which
# sounds careful and is not: the recogniser names somebody on one
# sentence and shrugs on the next, so the person just waved through was
# refused again the moment it lost confidence in them. This is that
# exact sequence - the same person, identified, then not.
reset
says banned "what time is it" >/dev/null
says arjun "bypass 727590" >/dev/null
ok "still in when the recogniser goes quiet on them" "no" \
   "$(refused "$(says hazy "what time is it")")"
ok "and in again when it picks them back up" "no" \
   "$(refused "$(says banned "what time is it")")"

reset
says unknown "what time is it" >/dev/null
says arjun "bypass 727590" >/dev/null
ok "and the other way round" "no" \
   "$(refused "$(says banned "what time is it")")"

# What keeps it narrow is time and intent, not identity.

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

# ------------------------------------------------------------- the gate itself
#
# Off by default. Recognising a voice is a guess with a confidence
# attached, and a guess used as a gate stops the assistant working for
# its owner every time the guess is wrong.
reset
ok "refusing is off unless asked for" "0" \
   "$(ORBIT_SPEAKER_REQUIRE_ENROLLED= bash -c '
      . "'"$TEST_ROOT"'/lib/config.sh" >/dev/null 2>&1
      printf "%s" "$ORBIT_SPEAKER_REQUIRE_ENROLLED"')"
ok "and with it off a stranger is answered" "no" \
   "$(refused "$(ORBIT_SPEAKER_REQUIRE_ENROLLED=0 says unknown "what time is it")")"
# A ban is a decision somebody made, so it still holds.
ok "but a banned voice is still refused" "yes" \
   "$(refused "$(ORBIT_SPEAKER_REQUIRE_ENROLLED=0 says banned "what time is it")")"

# Banning yourself is the one-word lockout. It is not allowed.
out="$("$TEST_ROOT/bin/orbit" voice ban "$WELCOME_NAME" 2>&1)" && rc=0 || rc=1
ok "you cannot ban yourself" "1" "$rc"
contains "and it says why" "locks you out" "$out"

# ------------------------------------------------- what the console reads
#
# The People page draws a button per person, which it cannot do from the
# paragraph the terminal prints. Both come out of the same command: a
# page that re-read the enrolment files itself would eventually disagree
# with the assistant about who is enrolled, and the disagreement would
# show up as a ban that appears not to have worked.
reset
raw="$("$TEST_ROOT/bin/orbit" voice list --raw 2>/dev/null)"
ok "the raw list has a row per person" "2" "$(printf '%s\n' "$raw" | grep -c .)"
ok "a name, a count and nothing else for somebody allowed" \
   "Arjun	3	" "$(printf '%s\n' "$raw" | sed -n 1p)"
ok "and the word banned for somebody who is" \
   "Neighbour	2	banned" "$(printf '%s\n' "$raw" | sed -n 2p)"
# Tabs, not spaces: "Unwelcome 2 Sep" is the label an unnamed voice gets
# when you ban it, and splitting on whitespace turns that into three
# people.
ok "the columns are tabs" "3" \
   "$(printf '%s\n' "$raw" | sed -n 1p | awk -F'\t' '{print NF}')"
# Captured, then searched. Piping into `grep -q` closes the pipe the
# moment it matches, orbit dies of SIGPIPE, and under pipefail the whole
# pipeline reports failure - so the check said "no" for a command that
# had just printed exactly what was being looked for.
human="$("$TEST_ROOT/bin/orbit" voice list 2>/dev/null)"
contains "the human list still reads as a sentence" "Voices it knows" "$human"
contains "with the count spelled out for a person" "3 samples" "$human"

facts="$("$TEST_ROOT/bin/orbit" voice status 2>/dev/null)"
field() { printf '%s\n' "$facts" | awk -F'\t' -v k="$1" '$1 == k { print $2 }'; }
ok "status knows recognition is installed" "1" "$(field installed)"
ok "and that the gate is on here" "1" "$(field gate)"
ok "and how many voices it knows" "2" "$(field enrolled)"
ok "and that no bypass is open" "" "$(field bypass)"
"$TEST_ROOT/bin/orbit" voice bypass >/dev/null 2>&1
ok "and reports one when there is" "yes" \
   "$("$TEST_ROOT/bin/orbit" voice status 2>/dev/null \
      | awk -F'\t' '$1 == "bypass" { print ($2 != "") ? "yes" : "no" }')"
"$TEST_ROOT/bin/orbit" voice bypass end >/dev/null 2>&1
