#!/bin/bash
# Screen half of the briefing: records -> text -> dialog / notification.

# Items only; "#note" lines are chrome, not work.
count_records() {
  printf '%s\n' "$1" | awk -F'\t' '$1 != "#note" && NF >= 2 && $2 != "" { n++ } END { print n + 0 }'
}

# "  9:30 AM   Call the bank  (Work)" / "  - Ship the thing"
format_records() {
  local records="$1" max="$2"
  printf '%s\n' "$records" | awk -F'\t' -v max="$max" '
    $1 == "#note" { notes[++nn] = "  (" $2 ")"; next }
    NF >= 2 && $2 != "" {
      n++
      if (n <= max) {
        if ($1 == "") { line = sprintf("  - %s", $2) }
        else          { line = sprintf("  %-9s %s", $1, $2) }
        if ($3 != "") { line = line "  (" $3 ")" }
        items[n] = line
      }
    }
    END {
      for (i = 1; i <= n && i <= max; i++) print items[i]
      if (n > max) printf "  ...and %d more\n", n - max
      for (i = 1; i <= nn; i++) print notes[i]
    }'
}

section_title() {
  case "$1" in
    reminders) printf 'REMINDERS' ;;
    calendar)  printf "TODAY'S SCHEDULE" ;;
    tasks)     printf 'TASKS' ;;
    *)         printf '%s' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" ;;
  esac
}

# build_screen_text REMINDERS CALENDAR TASKS
build_screen_text() {
  local rem="$1" cal="$2" tsk="$3"
  local out body section records shown=0

  out="$(date '+%A, %B %-d')  ·  $(date '+%-I:%M %p')"$'\n'

  for section in $WELCOME_SECTIONS; do
    case "$section" in
      reminders) records="$rem" ;;
      calendar)  records="$cal" ;;
      tasks)     records="$tsk" ;;
      *)         records="" ;;
    esac
    body="$(format_records "$records" "$WELCOME_MAX_ITEMS")"
    [ -z "$body" ] && continue
    [ "$(count_records "$records")" -gt 0 ] && shown=1
    out="${out}"$'\n'"$(section_title "$section")"$'\n'"${body}"$'\n'
  done

  if [ "$shown" -eq 0 ]; then
    out="${out}"$'\n'"Nothing due and nothing scheduled. The day is yours."$'\n'
  fi

  printf '%s' "$out"
}

present_dialog() {
  local title="$1" text="$2" timeout="$3"
  have_cmd osascript || return 0
  # Arguments go in as argv so nothing needs escaping into AppleScript.
  osascript - "$title" "$text" "$timeout" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set theTitle to item 1 of argv
  set theText to item 2 of argv
  set theTimeout to (item 3 of argv) as integer
  tell application "System Events"
    activate
    if theTimeout > 0 then
      display dialog theText with title theTitle buttons {"Onward"} default button 1 with icon note giving up after theTimeout
    else
      display dialog theText with title theTitle buttons {"Onward"} default button 1 with icon note
    end if
  end tell
end run
APPLESCRIPT
  return 0
}

present_notification() {
  local title="$1" subtitle="$2" text="$3"
  have_cmd osascript || return 0
  osascript - "$title" "$subtitle" "$text" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  display notification (item 3 of argv) with title (item 1 of argv) subtitle (item 2 of argv)
end run
APPLESCRIPT
  return 0
}

# One-line summary for the notification body.
build_notification_line() {
  local rem="$1" cal="$2" tsk="$3"
  local n_rem n_cal n_tsk parts=""
  n_rem="$(count_records "$rem")"
  n_cal="$(count_records "$cal")"
  n_tsk="$(count_records "$tsk")"

  [ "$n_rem" -gt 0 ] && parts="$n_rem $(_plural "$n_rem" reminder reminders)"
  [ "$n_cal" -gt 0 ] && parts="${parts:+$parts · }$n_cal $(_plural "$n_cal" event events)"
  [ "$n_tsk" -gt 0 ] && parts="${parts:+$parts · }$n_tsk $(_plural "$n_tsk" task tasks)"
  [ -z "$parts" ] && parts="Nothing due today"
  printf '%s' "$parts"
}
