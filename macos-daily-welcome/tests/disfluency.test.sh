#!/bin/bash
# Speech is not writing.
#
# Every one of these is a real transcript shape: fillers, restarts, and
# the same word twice while you think. The scrubber has to take them out
# without taking out anything that changes what was asked for.

test_sandbox
load_orbit

scrub() { ok "\"$1\"" "$2" "$(_scrub_disfluency "$1")"; }

scrub "um send a message to Mama"        "send a message to Mama"
scrub "uh, what time is it"              "what time is it"
scrub "so what's the weather"            "what's the weather"
scrub "can you, can you send a message"  "can you send a message"
scrub "the the meeting moved"            "the meeting moved"
scrub "what time is it please"           "what time is it"
scrub "mute thanks"                      "mute"
scrub "  spaced   out  "                 "spaced out"

# Left alone on purpose. These are content, not filler, and taking them
# out changes what was asked for.
keep() { ok "\"$1\" survives" "$1" "$(_scrub_disfluency "$1")"; }
keep "play something like jazz"
keep "turn right at the lights"
# A hedge is only a hedge when a comma says so. Stripping these on sight
# turned a question into a different question and ate the middle of a
# message.
keep "what kind of bird is that"
keep "tell Mama I mean it"
keep "sort of a big deal"
scrub "you know, what time is it"   "what time is it"
# The comma that opened the hedge is left where it is: a small pause is
# not worth a regex that could reach inside a word to remove it.
scrub "it is, kind of, urgent"      "it is, urgent"
scrub "basically what happened"     "what happened"
