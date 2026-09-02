#!/bin/bash
# What Orbit understands.
#
# Nearly every "it stopped working" in this project has been a sentence
# the rules stopped matching. Each case below is one of those.

test_sandbox
load_orbit

# expect "what you said" intent [arg1] [arg2]
expect() {
  local said="$1" want_intent="$2" want1="${3-}" want2="${4-}"
  local line; line="$(parse_intent "$said")"
  ok "\"$said\" is a $want_intent" "$want_intent" "$(intent_of "$line")"
  [ $# -ge 3 ] && ok "\"$said\" -> arg1" "$want1" "$(arg1_of "$line")"
  [ $# -ge 4 ] && ok "\"$said\" -> arg2" "$want2" "$(arg2_of "$line")"
  return 0
}

# --------------------------------------------------------------- messages

expect "message Mama saying I'm running late"        message Mama "I'm running late"
expect "text Priya saying dinner at eight"           message Priya "dinner at eight"
expect "send a message to Mom: landed safely"        message Mom "landed safely"
expect "tell Dad I'll be home by six"                message Dad "I'll be home by six"
expect "let Priya know the meeting moved"            message Priya "the meeting moved"
# The name comes before the noun in half the ways people say this.
expect "send Mama a message saying I'm on my way"    message Mama "I'm on my way"

# ---------------------------------------------------------------- system

expect "mute"                     system mute
expect "what time is it"          system time_now
expect "stop listening"           system stop_listening
# Shushing stops the sentence in progress; it does not close the ears.
expect "shush"                    system stop_talking
expect "that's enough"            system stop_talking
# Said to an assistant this means "stop listening". Taking it as an
# instruction to sleep the Mac ends the session you were in the middle of.
expect "go to sleep"              system stop_listening
# Naming the machine still means the machine.
expect "sleep the mac"            system sleep_mac
expect "put the mac to sleep"     system sleep_mac

# A command has to be the whole sentence. Matching "go away" anywhere in
# what was said meant "did the pain go away?" shut the microphone.
expect "did the pain go away"     ask
expect "when should I wake up"    ask

# ------------------------------------------------------------- questions

expect "what's the capital of Peru"   ask
expect "who wrote Middlemarch"        ask
expect "explain how a diesel engine works" ask

# ------------------------------------------------------------------ web

line="$(parse_intent "search the web for the best noise cancelling headphones")"
ok "a web search is a web search" web_search "$(intent_of "$line")"
line="$(parse_intent "look at https://example.com and tell me what it says")"
contains "a URL is a page to read" web_page "$(intent_of "$line")"

# ---------------------------------------------------------------- silence

expect ""      none
expect "   "   none
expect "um"    none
