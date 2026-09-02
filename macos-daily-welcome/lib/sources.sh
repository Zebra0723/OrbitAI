#!/bin/bash
# Data sources for the daily briefing.
#
# Every source emits TAB-separated records:  when <TAB> title <TAB> context
#   when    - "OVERDUE", a time like "9:30 AM", or empty for undated items
#   title   - what it is
#   context - reminder list / calendar name / empty
# Formatting for the screen and phrasing for the voice both work off these,
# so the two can't drift apart. A source that is unavailable emits nothing
# but a single "#note" record explaining itself.

_note() { printf '#note\t%s\t\n' "$1"; }

# The menu bar app doubles as an EventKit reader. It's the preferred path
# for reminders and events: AppleScript needs the target app running and
# gets due dates wrong, EventKit needs neither.
_eventkit_bin() {
  printf '%s/Applications/DailyWelcome.app/Contents/MacOS/DailyWelcome' "$HOME"
}

_have_eventkit() { [ -x "$(_eventkit_bin)" ]; }

# ---------------------------------------------------------------- reminders

_reminders_applescript() {
  local include_undated="$1"
  osascript <<APPLESCRIPT
on run
  set dayStart to (current date)
  set time of dayStart to 0
  set dayEnd to dayStart + (1 * days)
  set outText to ""
  tell application "Reminders"
    repeat with theList in lists
      set listName to name of theList
      repeat with r in (reminders of theList whose completed is false)
        -- The "due date is not missing value" filter can't be trusted:
        -- undated reminders come back from it anyway, and comparing one
        -- to a date fails the whole script with -1700.
        set dd to missing value
        try
          set dd to due date of r
        end try
        if dd is not missing value and dd < dayEnd then
          if dd < dayStart then
            set whenLabel to "OVERDUE"
          else
            set whenLabel to (time string of dd)
          end if
          set outText to outText & whenLabel & tab & (name of r) & tab & listName & linefeed
        end if
      end repeat
      if $include_undated is 1 then
        repeat with r in (reminders of theList whose completed is false and due date is missing value and flagged is true)
          set outText to outText & "flagged" & tab & (name of r) & tab & listName & linefeed
        end repeat
      end if
    end repeat
  end tell
  return outText
end run
APPLESCRIPT
}

src_reminders() {
  local raw rc

  if _have_eventkit; then
    raw="$(run_with_timeout 30 "$(_eventkit_bin)" --dump-reminders)"
    rc=$?
    case "$rc" in
      0) _reminders_format "$raw"; return 0 ;;
      3) _note "$(last_error)"; return 0 ;;
      *) : ;;   # anything else: fall through and try AppleScript
    esac
  fi

  have_cmd osascript || return 0

  raw="$(run_with_timeout "$WELCOME_SOURCE_TIMEOUT" \
    _reminders_applescript "$WELCOME_REMINDERS_INCLUDE_UNDATED")"
  rc=$?

  if [ "$rc" -eq 124 ]; then
    _note "Reminders took too long to answer"; return 0
  fi
  if [ "$rc" -ne 0 ]; then
    # Say what actually went wrong. "Allow access" is one possible cause of
    # a failure here, not the only one, and claiming it when the real error
    # is something else sends you to a switch that was never the problem.
    _note "Reminders: $(last_error) (daily-welcome --doctor)"
    return 0
  fi

  _reminders_format "$raw"
}

# Overdue first, then chronological, then undated.
_reminders_format() {
  # Overdue, then the rest of the day in order, then the undated.
  #
  # Two keys, sorted together. The second used to be the time as a
  # string, which put ten in the morning before nine and one in the
  # afternoon before either - an order that was neither chronological nor
  # obviously wrong, just quietly shuffled.
  printf '%s\n' "$1" | awk -F'\t' '
    function minutes(t,   s, parts, n, h, m, pm, am) {
      s = toupper(t)
      pm = (index(s, "PM") > 0)
      am = (index(s, "AM") > 0)
      gsub(/[^0-9:]/, "", s)
      n = split(s, parts, ":")
      if (n < 2) return 99999
      h = parts[1] + 0; m = parts[2] + 0
      if (pm && h < 12) h += 12
      if (am && h == 12) h = 0
      if (h > 23 || m > 59) return 99999
      return h * 60 + m
    }
    NF >= 2 && $2 != "" {
      rank = ($1 == "OVERDUE") ? 0 : (($1 == "flagged") ? 2 : 1)
      printf "%d\t%05d\t%s\t%s\t%s\n", rank, minutes($1), $1, $2, $3
    }' \
  | sort -t"$(printf '\t')" -k1,1n -k2,2n -s \
  | cut -f3- \
  | tidy_time_field
}

# ----------------------------------------------------------------- calendar

_calendar_icalbuddy() {
  icalBuddy -n -nc -nrd -eep "notes,url,location,attendees" \
    -iep "datetime,title" -df "" -tf "%-l:%M%p" -b "" -ps "|@@|" \
    eventsToday 2>/dev/null
}

_calendar_applescript() {
  osascript <<'APPLESCRIPT'
on run
  set dayStart to (current date)
  set time of dayStart to 0
  set dayEnd to dayStart + (1 * days)
  set outText to ""
  tell application "Calendar"
    repeat with c in calendars
      repeat with e in (every event of c whose start date is greater than or equal to dayStart and start date is less than dayEnd)
        set outText to outText & (time string of (start date of e)) & tab & (summary of e) & tab & (name of c) & linefeed
      end repeat
    end repeat
  end tell
  return outText
end run
APPLESCRIPT
}

src_calendar() {
  local raw rc

  # EventKit first: no icalBuddy to install, and no need for Calendar.app
  # to be running.
  if _have_eventkit; then
    raw="$(run_with_timeout 30 "$(_eventkit_bin)" --dump-events)"
    rc=$?
    case "$rc" in
      0) printf '%s\n' "$raw" | awk -F'\t' 'NF >= 2 && $2 != ""' | tidy_time_field; return 0 ;;
      3) _note "$(last_error)"; return 0 ;;
      *) : ;;
    esac
  fi

  if have_cmd icalBuddy; then
    raw="$(run_with_timeout "$WELCOME_SOURCE_TIMEOUT" _calendar_icalbuddy)"
    rc=$?
    [ "$rc" -eq 124 ] && { _note "Calendar took too long to answer"; return 0; }
    # "9:00AM - 9:15AM@@Standup" -> when, title. Anything that doesn't match
    # that shape is passed through as an undated title rather than dropped.
    printf '%s\n' "$raw" | awk -F'@@' '
      { gsub(/^[ \t]+|[ \t]+$/, "", $0) }
      $0 == "" { next }
      NF >= 2 {
        when = $1; title = $2
        gsub(/^[ \t]+|[ \t]+$/, "", when)
        gsub(/^[ \t]+|[ \t]+$/, "", title)
        sub(/ *- *.*$/, "", when)     # keep the start time only
        printf "%s\t%s\t\n", when, title
        next
      }
      { printf "\t%s\t\n", $0 }'
    return 0
  fi

  if [ "$WELCOME_CALENDAR_APPLESCRIPT" != "1" ]; then
    return 0
  fi

  raw="$(run_with_timeout "$WELCOME_SOURCE_TIMEOUT" _calendar_applescript)"
  rc=$?
  [ "$rc" -eq 124 ] && { _note "Calendar took too long to answer"; return 0; }
  [ "$rc" -ne 0 ] && { _note "Calendar: $(last_error) (daily-welcome --doctor)"; return 0; }
  printf '%s\n' "$raw" | awk -F'\t' 'NF >= 2 && $2 != "" { print }' \
    | sort_by_time_field | tidy_time_field
}

# -------------------------------------------------------------- tasks file

# Unchecked markdown checkboxes, or every non-comment line if the file
# doesn't use checkboxes at all.
src_tasks() {
  local file="$WELCOME_TASKS_FILE"
  [ -f "$file" ] || return 0

  if grep -qE '^[[:space:]]*[-*] \[ \]' "$file"; then
    grep -E '^[[:space:]]*[-*] \[ \]' "$file" \
      | sed -E 's/^[[:space:]]*[-*] \[ \][[:space:]]*//'
  else
    grep -vE '^[[:space:]]*(#|$)' "$file" | trim_lines
  fi | awk 'NF { printf "\t%s\t\n", $0 }'
}
