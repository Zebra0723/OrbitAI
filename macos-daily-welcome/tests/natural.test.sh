#!/bin/bash
# Sounding like a person rather than a machine reading.
#
# Every case here comes from the same complaint said several ways: "it is
# so robotic", "so expressionless", "the way it speaks". None of it is
# the voice - it is the words handed to the voice, and the shape of the
# pauses handed with them.

test_sandbox
load_orbit

# --------------------------------------------------------- contractions

nat() { ok "\"$1\"" "$2" "$(speech_natural "$1")"; }

nat "It is eight o clock."            "It's eight o clock."
nat "That is done."                   "That's done."
nat "There is nothing due."           "There's nothing due."
nat "You are all clear."              "You're all clear."
nat "I am on it."                     "I'm on it."
nat "I will send it."                 "I'll send it."
nat "We are done."                    "We're done."
nat "Let us see."                     "Let's see."
nat "That is not right."              "That isn't right."
nat "It does not answer."             "It doesn't answer."

# "I will not" is "I won't", never "I'll not" - the negation is the
# contraction that matters, and it comes second.
nat "I will not be able to."          "I won't be able to."
nat "It is not there."                "It isn't there."
nat "You are not late."               "You aren't late."

# Left alone. "You've three reminders" is British and dated, and a
# briefing is nothing but nouns.
nat "You have three reminders."       "You have three reminders."
nat "I have sent it."                 "I have sent it."

# Capitals and punctuation survive the swap.
nat "It is. That is."                 "It's. That's."
nat "Is it done? It is."              "Is it done? It's."
contains "a capital stays a capital"  "It's" "$(speech_natural "It is here")"
contains "and mid-sentence stays low" "it's" "$(speech_natural "I think it is here")"

# ------------------------------------------------------------- briefing

records="$(printf 'OVERDUE\tcall the bank\tHome
9:00 AM\tstandup\tWork
2:00 PM\tdentist\tHome')"
out="$(build_spoken_briefing "$records" "" "")"

# One greeting, not two. It used to open "Welcome back, Arjun - good
# evening, sir", which is a doorman and a butler talking over each other.
lacks "no doubled greeting" "Welcome back" "$out"
ok "one greeting only" "1" \
   "$(printf '%s' "$out" | grep -oE 'Good (morning|afternoon|evening)' | grep -c .)"

# The honorific replaces the name; it does not follow it.
out2="$(WELCOME_HONORIFIC=sir build_spoken_briefing "$records" "" "")"
contains "the honorific is used"    "sir"   "$out2"
lacks "and the name is not as well" "Arjun" "$(printf '%s' "$out2" | head -c 40)"
out3="$(WELCOME_HONORIFIC= build_spoken_briefing "$records" "" "")"
contains "no honorific means your name" "Arjun" "$out3"

# A list read out with one connective repeated is a list being read out.
lacks "it does not start by counting"   "first," "$out"
ok "\"then\" is not the only join" "1" \
   "$(printf '%s' "$out" | grep -oE ', and then ' | grep -c .)"

# The relative clause is gone: the sentence before already said how many
# are overdue.
lacks "no relative clause on the item" "which is overdue" "$out"
contains "still says which one is late" "already overdue" "$out"

# Contractions reach the briefing.
contains "the briefing contracts too" "It's" "$out"

# ----------------------------------------------------------- the pauses

export WELCOME_PAUSE=short WELCOME_PAUSE_MS=200 WELCOME_SAY_EMPHASIS=1
paced="$(speech_pace "Good evening, sir. It's late, and you have two unread, one overdue." say)"

# Three different pauses, not one repeated: a breath before a
# conjunction, a beat at a clause, a stop at a sentence end.
ok "a breath before a conjunction" "110" \
   "$(printf '%s' "$paced" | grep -oE 'slnc 110' | head -1 | grep -oE '[0-9]+')"
ok "a beat at a clause"            "200" \
   "$(printf '%s' "$paced" | grep -oE 'slnc 200' | head -1 | grep -oE '[0-9]+')"
ok "a stop at the end of a sentence" "350" \
   "$(printf '%s' "$paced" | grep -oE 'slnc 350' | head -1 | grep -oE '[0-9]+')"

contains "the words that matter are leaned on" "[[emph +]]overdue[[emph -]]" "$paced"
contains "and so is unread" "[[emph +]]unread[[emph -]]" "$paced"

# Turning it off turns it off.
plain="$(WELCOME_SAY_EMPHASIS=0 speech_pace "One overdue." say)"
lacks "emphasis is optional" "emph" "$plain"

# A number is still a number.
contains "a thousand keeps its comma" "1,000" \
   "$(speech_pace "You have 1,000 unread." say)"

# Other backends are untouched by any of it.
lacks "elevenlabs gets no say markup" "slnc" "$(speech_pace "Morning, sir." elevenlabs)"
lacks "and no emphasis markup either"  "emph" "$(speech_pace "One overdue." elevenlabs)"
