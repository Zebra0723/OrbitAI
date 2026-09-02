#!/bin/bash
# What it remembers, and what it lets go of.
#
# Two complaints made this: it could not refer back to anything ("it
# should be able to reference past events in conversation") and it would
# not let a subject go ("if I message someone, it keeps talking about
# messages long after").

test_sandbox
load_orbit

memory_init
memory_log_turn you "message Mama saying I'm running late"
memory_log_turn orbit "Sent to Mama."
memory_log_turn you "what's the weather"
memory_log_event add_reminder "$(memory_event_words add_reminder "call the bank")"
memory_log_event timer "$(memory_event_words timer 1800)"

# ------------------------------------------------------------- recalling

out="$(memory_events)"
contains "the reminder is on the record" "call the bank" "$out"
contains "in words a voice can read" "Added a reminder" "$out"
contains "and so is the timer, in its own units" "thirty minutes" "$out"

out="$(memory_recent)"
contains "so is what was said" "running late" "$out"

# Searching finds the line whichever side said it.
out="$(memory_search "what did I say to Mama")"
contains "a search finds the message" "Mama" "$out"
out="$(memory_search "did I set a reminder about the bank")"
contains "and finds the reminder" "bank" "$out"
# Nothing matching is nothing, not everything.
ok "an unrelated search finds nothing" "" "$(memory_search "penguins in Antarctica")"

# --------------------------------------------------- is this about the past

past() { if memory_asks_about_past "$1"; then ok "\"$1\" looks backwards" y y
         else ok "\"$1\" looks backwards" y n; fi; }
now()  { if memory_asks_about_past "$1"; then ok "\"$1\" does not" n y
         else ok "\"$1\" does not" n n; fi; }

past "what did I say about the bank"
past "do you remember the meeting"
past "what did we talk about earlier"
past "you said you would remind me"
now  "what's the weather"
now  "send Mama a message"
now  "set a timer for ten minutes"

# ------------------------------------------------------- dropping a subject

memory_drop_subject
out="$(memory_recent)"
ok "after being told to drop it, there is no thread to pick back up" "" "$out"
# The record of what it did is not the conversation, and survives.
contains "but what it actually did is still known" "call the bank" "$(memory_events)"
