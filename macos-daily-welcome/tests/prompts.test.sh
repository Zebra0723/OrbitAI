#!/bin/bash
# The prompts, in full.
#
# A prompt is a long string in a shell script, which means one stray
# quote closes it early and the rest of it silently never reaches the
# model. That is exactly what happened: an apostrophe in the middle of
# the drop-a-subject rule ended the string, and everything after it -
# the whole of "answer what they JUST said", and the instruction to
# answer in ONE sentence - was gone. Nothing failed. It just quietly
# asked for less, and the complaint arrived as "it rambles" and "it
# won't drop a subject".
#
# So: every prompt is checked to reach its own last line, and to carry
# the rules that were asked for.

test_sandbox
load_orbit

# ------------------------------------------------- the one-call turn prompt

p="$(ORBIT_SPEAKER_NAME="" _claude_turn_prompt "hello there" "" "" "" "" "")"

contains "it opens with the identity"    "You are Orbit" "$p"
contains "made by the right person"      "Arjun Jain"    "$p"
contains "the forms are all there"       "mail_reply"    "$p"
contains "drop a subject, in full"       "do not summarise what it was" "$p"
contains "answer what was JUST said"     "reference to an earlier turn" "$p"
contains "one sentence, said out loud"   "SPOKEN ALOUD"  "$p"
contains "and it reaches its own end"    "say so in a sentence." "$p"
contains "with what they said"           "hello there"   "$p"

# The words that go missing when a string closes early: two apostrophes
# in a row with nothing between them is what mangling looks like here.
lacks "nothing ran together"             "forgetthat"    "$p"
lacks "no stray escape characters"       '\"'            "$p"

# Whose voice it is gets said, when it is known.
p="$(ORBIT_SPEAKER_NAME="Priya" _claude_turn_prompt "hello" "" "" "" "" "")"
contains "a guest is named"      "Priya" "$p"
contains "and marked as a guest" "NOT"   "$p"
p="$(ORBIT_SPEAKER_NAME="Arjun" _claude_turn_prompt "hello" "" "" "" "" "")"
contains "the owner is named"    "Arjun" "$p"
lacks "and not called a guest"   "NOT $WELCOME_NAME" "$p"

# ------------------------------------------------------------- identity

id="$(orbit_identity)"
contains "it is Orbit"            "You are Orbit" "$id"
contains "made by Arjun Jain"     "Arjun Jain"    "$id"
contains "at DailyOS"             "DailyOS"       "$id"
contains "and not Claude"         "NOT Claude"    "$id"
contains "nor made by Anthropic"  "NOT made by Anthropic" "$id"

# Every prompt that answers as Orbit says who Orbit is - it used to
# depend on which path the question took to get there.
for fn in ask_claude ask_chat; do
  if declare -f "$fn" >/dev/null 2>&1; then
    body="$(declare -f "$fn")"
    contains "$fn asks orbit_identity, not its own version" "orbit_identity" "$body"
    lacks "$fn has no literal backslash-n" '\n"' "$body"
  fi
done
