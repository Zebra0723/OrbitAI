#!/bin/bash
# The briefing's contents, and the order they come out in.
#
# A day read out in the wrong order is not obviously broken - it is just
# wrong, every morning, in a way that is easy to hear and hard to place.
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

# ----------------------------------------------------------------- tasks

tasks="$WELCOME_STATE_DIR/todo.md"
cat > "$tasks" <<'TODO'
# My list

- [ ] call the bank
- [x] already done
* [ ] book the flights
TODO
out="$(WELCOME_TASKS_FILE="$tasks" src_tasks)"
contains "an unchecked box is a task"        "call the bank"   "$out"
contains "whichever bullet it uses"          "book the flights" "$out"
lacks "a ticked box is not"                  "already done"    "$out"
lacks "and neither is the heading"           "My list"         "$out"
ok "each task is a record with an empty time" "2" \
   "$(printf '%s\n' "$out" | awk -F'\t' 'NF == 3 && $1 == ""' | grep -c .)"

# A file with no checkboxes at all is a list of lines.
printf 'buy milk\n# a comment\n\nwalk the dog\n' > "$tasks"
out="$(WELCOME_TASKS_FILE="$tasks" src_tasks)"
contains "a plain list works too" "buy milk"     "$out"
contains "all of it"              "walk the dog" "$out"
lacks "comments are not tasks"    "a comment"    "$out"
ok "and blank lines are not tasks" "2" "$(printf '%s\n' "$out" | grep -c .)"

# A file that is not there is not an error.
ok "no file, no tasks, no complaint" "" \
   "$(WELCOME_TASKS_FILE=/nowhere/todo.md src_tasks)"
