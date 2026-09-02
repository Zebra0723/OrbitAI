#!/bin/bash
# Numbers said out loud.
#
# "set a timer for twenty five minutes" has to become 25, and the first
# version of this read it as 20. Anything with a compound number in it -
# timers, alarms, volume - depends on this.

test_sandbox
load_orbit

num() { ok "\"$1\" is $2" "$2" "$(_first_number "$1")"; }

num "5 minutes"                     5
num "for 30 seconds"                30
num "five"                          5
num "twelve minutes"                12
num "twenty minutes"                20
num "twenty five minutes"           25
num "twenty-five minutes"           25
num "forty five"                    45
num "ninety nine"                   99
num "an hour and a half"            1
num "half"                          ""
num "no number here"                ""

# The first number, not the largest or the last.
num "3 of the 40 things"            3
