#!/bin/bash
# Timers.
#
# A timer that is wrong says nothing until it goes off, so the parsing has
# to be right the first time. Reading only the number - which is what it
# used to do - made "two hours" a two minute timer and "thirty seconds" a
# thirty minute one.

test_sandbox
load_orbit

dur() { ok "\"$1\" is ${2}s" "$2" "$(_duration_seconds "$1")"; }

dur "5 minutes"             300
dur "ten minutes"           600
dur "twenty five minutes"   1500
dur "30 seconds"            30
dur "two hours"             7200
dur "an hour"               3600
dur "half an hour"          1800
dur "an hour and a half"    5400
dur "two and a half hours"  9000
dur "1 minute"              60
# No unit said means minutes, which is what people mean when they leave it off.
dur "ten"                   600
dur "nothing at all"        ""

# End to end, through the intent parser.
line="$(parse_intent "set a timer for two hours")"
ok "a two hour timer is two hours" "7200" "$(arg2_of "$line")"
line="$(parse_intent "set a timer for 30 seconds")"
ok "a thirty second timer is thirty seconds" "30" "$(arg2_of "$line")"

# And back into words, which is what it says out loud.
say() { ok "${1}s reads as \"$2\"" "$2" "$(duration_words "$1")"; }
say 30    "thirty seconds"
say 60    "one minute"
say 300   "five minutes"
say 3600  "one hour"
say 5400  "an hour and a half"
say 7200  "two hours"

attr() { ok "${1}s attributive is \"$2\"" "$2" "$(duration_attr "$1")"; }
attr 7200 "two hour"
attr 300  "five minute"
attr 5400 "hour and a half"
