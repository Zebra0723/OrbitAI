#!/bin/bash
# What readbacks contain, and the order they come out in.
#
# A day read out in the wrong order is not obviously broken - it is just
# wrong, every time, in a way that is easy to hear and hard to place.
# Sorting clock times as strings put ten in the morning before nine and
# one in the afternoon before both.

test_sandbox
load_orbit

day="$(printf '9:00:00 AM\tNine\tHome
10:00:00 AM\tTen\tHome
1:00:00 PM\tAfternoon\tWork
OVERDUE\tThe overdue one\tHome
flagged\tSomeday\tHome
8:30:00 AM\tEarly\tWork
12:00:00 PM\tNoon\tWork
11:45:00 PM\tLate\tHome')"

out="$(_reminders_format "$day")"
order="$(printf '%s\n' "$out" | cut -f2 | tr '\n' '|')"

ok "overdue first, then the day in order, then the undated" \
   "The overdue one|Early|Nine|Ten|Noon|Afternoon|Late|Someday|" "$order"

# The seconds are dropped, the rest is left alone.
contains "the time is said the way you would say it" "8:30 AM" "$out"
lacks "without the seconds" ":00:00" "$out"

# Nothing is lost on the way through.
ok "every reminder survives" "8" "$(printf '%s\n' "$out" | grep -c .)"

# Rows without a title are not rows.
out="$(_reminders_format "$(printf '9:00:00 AM\t\tHome\n10:00:00 AM\tReal\tHome')")"
ok "an untitled reminder is dropped" "1" "$(printf '%s\n' "$out" | grep -c .)"

# ------------------------------------------------------- the shared sorter

times="$(printf '10:00 AM\tten\n9:00 AM\tnine\n1:00 PM\tone\n12:00 AM\tmidnight\n12:00 PM\tnoon\nnot a time\tlast')"
ok "midnight, morning, noon, afternoon - in that order" \
   "midnight|nine|ten|noon|one|last|" \
   "$(printf '%s\n' "$times" | sort_by_time_field | cut -f2 | tr '\n' '|')"

# Twenty-four hour clocks too, which is what a Mac set to one hands over.
times="$(printf '14:30:00\tafternoon\n09:15:00\tmorning\n23:59:00\tlate\n00:05:00\tearly')"
ok "and a twenty-four hour clock" "early|morning|afternoon|late|" \
   "$(printf '%s\n' "$times" | sort_by_time_field | cut -f2 | tr '\n' '|')"
