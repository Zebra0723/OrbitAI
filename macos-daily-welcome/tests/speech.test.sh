#!/bin/bash
# How it sounds.
#
# A comma tells a speech engine to STOP, and they stop hard - which is
# most of what makes a synthetic voice sound synthetic. Deleting the
# commas fixed the pausing and cost the phrasing, so the comma is kept
# and the pause is shortened instead. These are the cases that went
# wrong on the way to that.

test_sandbox
load_orbit

export WELCOME_PAUSE=short
export WELCOME_PAUSE_MS=210

# A comma becomes a short, explicit pause rather than the engine's own
# long breath.
out="$(speech_pace "Good morning, Arjun." say)"
contains "a comma becomes a measured pause" "[[slnc 210]]" "$out"
contains "the words are all still there" "Arjun" "$out"

# A comma between digits is not a pause. Stripping it turned 1,000 into
# 1 000, and one version of the sed ate the zero outright.
out="$(speech_pace "You have 1,000 unread." say)"
contains "a thousand is still a thousand" "1,000" "$out"
lacks "no pause inside a number" "1,[[slnc" "$out"

# Dead air, in three disguises.
out="$(speech_pace "Two things - both today." say)"
lacks "a spaced dash is dead air" " - " "$out"
out="$(speech_pace "Well... maybe." say)"
lacks "an ellipsis is dead air" "..." "$out"
out="$(speech_pace "One thing; then another." say)"
lacks "a semicolon is a full stop out loud" ";" "$out"

# Each engine has its own lever.
out="$(speech_pace "Morning, Arjun." elevenlabs)"
contains "elevenlabs gets a break tag" "<break time=" "$out"
lacks "and not the say markup" "slnc" "$out"

out="$(speech_pace "Morning, Arjun." openai)"
ok "openai has no pause control, so the comma stays" "Morning, Arjun." "$out"

# Off, and all the way off.
WELCOME_PAUSE=natural out="$(WELCOME_PAUSE=natural speech_pace "Morning, Arjun." say)"
ok "natural leaves it alone" "Morning, Arjun." "$out"
out="$(WELCOME_PAUSE=none speech_pace "Morning, Arjun." say)"
ok "none drops the comma" "Morning Arjun." "$out"
out="$(WELCOME_PAUSE=none speech_pace "1,000 things." say)"
contains "even then a number keeps its comma" "1,000" "$out"

# ------------------------------------------------------------- tidying

out="$(speech_clean "Standup https://meet.example.com/abc w/ Priya & Sam")"
lacks "a URL is not read out" "https" "$out"
contains "w/ is with" "with" "$out"
contains "an ampersand is a word" "and" "$out"

out="$(speech_clean "**Deploy** the \`api\` at 5pm")"
lacks "no markdown asterisks" "*" "$out"
contains "5pm is spaced for the ear" "5 PM" "$out"

# --------------------------------------------------------------- casing

out="$(printf 'three reminders due today. two emails.' | capitalize_sentences)"
ok "each sentence starts like one" "Three reminders due today. Two emails." "$out"

# --------------------------------------------------------------- clocks

ok "half six"     "six thirty in the evening"     "$(time_words 18 30)"
ok "on the hour"  "six o'clock in the evening"    "$(time_words 18 00)"
ok "quarter to"   "six forty-five in the evening" "$(time_words 18 45)"
ok "morning"      "nine o'clock in the morning"   "$(time_words 9 00)"
ok "midnight"     "twelve o'clock at night"       "$(time_words 0 00)"
ok "late"         "eleven o'clock at night"       "$(time_words 23 00)"
ok "still evening" "nine o'clock in the evening"  "$(time_words 21 00)"
ok "noon"         "twelve o'clock in the afternoon" "$(time_words 12 00)"
# Digits are for reading, not for saying: "9:05" said as "nine five" is
# a different time from the one meant.
ok "past the hour" "nine oh five in the morning"  "$(time_words 9 05)"
