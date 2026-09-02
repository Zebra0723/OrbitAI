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

export WELCOME_PAUSE=short WELCOME_PAUSE_MS=200
line="Good evening, sir. It's late, and you have two unread, one overdue."
paced="$(WELCOME_SAY_EMPHASIS=0 speech_pace "$line" say)"

# Two lengths, not one repeated: barely a breath before a conjunction, a
# proper beat at a comma that opens a clause.
ok "a breath before a conjunction" "110" \
   "$(printf '%s' "$paced" | grep -oE 'slnc 110' | head -1 | grep -oE '[0-9]+')"
ok "a beat at a clause"            "200" \
   "$(printf '%s' "$paced" | grep -oE 'slnc 200' | head -1 | grep -oE '[0-9]+')"

# Nothing added at a full stop. `say` already stops there, and stacking
# another pause on top made every sentence land with a thud.
lacks "no pause piled onto a full stop" ". [[slnc" "$paced"

# Emphasis is off unless it is asked for. What `say` does with [[emph]]
# is blunt - the word jumps and stretches - so it is a thing to try, not
# a thing to default to.
lacks "emphasis is off by default" "emph" "$paced"
loud="$(WELCOME_SAY_EMPHASIS=1 speech_pace "$line" say)"
contains "and on when asked for" "[[emph +]]overdue[[emph -]]" "$loud"
contains "on the words that mean act on this" "[[emph +]]unread[[emph -]]" "$loud"

# A number is still a number.
contains "a thousand keeps its comma" "1,000" \
   "$(WELCOME_SAY_EMPHASIS=0 speech_pace "You have 1,000 unread." say)"

# Other backends are untouched by any of it.
lacks "elevenlabs gets no say markup" "slnc" "$(speech_pace "Morning, sir." elevenlabs)"
lacks "and no emphasis markup either"  "emph" "$(speech_pace "One overdue." elevenlabs)"


# ------------------------------------------------------- turning people away
#
# Being told no in exactly the same words every single time is the most
# machine-like thing a machine can do. lib/refusals.txt is not a list of
# finished lines - it is interchangeable ones, every entry a complete
# sentence, so any opener joined to any reason joined to any redirect is
# grammatical and there are tens of thousands of them.

export ORBIT_SPEAKER_UNKNOWN="" ORBIT_SPEAKER_REFUSAL=""

ok "there are thousands of refusals for a stranger" "yes" \
   "$([ "$(speaker_refusal_count unknown)" -gt 5000 ] && echo yes || echo no)"
ok "and thousands for a banned voice" "yes" \
   "$([ "$(speaker_refusal_count banned)" -gt 1000 ] && echo yes || echo no)"

seen=""
for i in $(seq 1 30); do seen="$seen$(speaker_refusal_unknown)
"; done
ok "thirty in a row are nearly all different" "yes" \
   "$([ "$(printf '%s' "$seen" | sort -u | grep -c .)" -ge 25 ] && echo yes || echo no)"
ok "and never the same twice running" "0" \
   "$(printf '%s' "$seen" | awk 'NF { if ($0 == prev) n++; prev = $0 } END { print n + 0 }')"

# Every one has to say what is actually wrong, or it is only rudeness.
# Checked against the reason list rather than every combination, which is
# the whole point of composing them: the reason slot always appears.
missing="$(awk '
  /^#/ { section = substr($0, 3); next }
  /^[[:space:]]*$/ { next }
  section == "unknown/reason" {
    line = tolower($0)
    if (line !~ /enrol|registe|verif|recognis|know|list|file|record|stranger|match|credential|introduc|mystery|mine|familiar|book|means nothing|no you|found nothing|who you are|never heard/) print
  }' "$TEST_ROOT/lib/refusals.txt")"
ok "every reason says the voice is not known" "" "$missing"

missing="$(awk '
  /^#/ { section = substr($0, 3); next }
  /^[[:space:]]*$/ { next }
  section == "banned/reason" {
    line = tolower($0)
    if (line !~ /ban|refus|block|barred|not allowed|revoked|no list/) print
  }' "$TEST_ROOT/lib/refusals.txt")"
ok "and every ban says it is a ban" "" "$missing"

# Every line is a whole sentence. That is what makes any combination
# work, and one entry without a full stop breaks every line built from it.
missing="$(awk '
  /^#/ { next }
  /^[[:space:]]*$/ { next }
  $0 !~ /[.!?]$/ { print }' "$TEST_ROOT/lib/refusals.txt")"
ok "every line is a finished sentence" "" "$missing"

# Three sentences joined, not one.
line="$(speaker_refusal_unknown)"
ok "a refusal is three sentences" "yes" \
   "$([ "$(printf '%s' "$line" | grep -oE '[.!?]' | grep -c .)" -ge 3 ] && echo yes || echo no)"

# A setting of your own still wins, including the polite one.
ok "your own line is used instead" "Please verify your voice." \
   "$(ORBIT_SPEAKER_UNKNOWN="Please verify your voice." speaker_refusal_unknown)"
ok "for bans too" "No." "$(ORBIT_SPEAKER_REFUSAL="No." speaker_refusal_banned)"

# And if the file goes missing it still refuses, rather than saying
# nothing at all and letting the moment pass.
ok "a missing library still refuses" "yes" \
   "$(ROOT=/nowhere speaker_refusal_unknown | grep -qi "recognis" && echo yes || echo no)"
