#!/bin/bash
# Spoken half of the briefing. The phrasing here is deliberately not the
# same as the on-screen text: a screen reads well in columns, a voice
# reads well in sentences.

# "Ava (Premium)        en_US    # Hello! ..." -> "Ava (Premium)"
_installed_voices() {
  say -v '?' 2>/dev/null \
    | sed -E 's/[[:space:]]+[a-z]{2}(_[A-Z]{2})?[[:space:]]+#.*$//' \
    | sed -E 's/[[:space:]]+$//'
}

# Echoes the first voice from WELCOME_VOICES that is actually installed.
# Empty output means "let `say` use the system default".
resolve_voice() {
  if [ -n "$WELCOME_VOICE" ]; then
    printf '%s' "$WELCOME_VOICE"
    return 0
  fi
  have_cmd say || return 0

  local installed candidates="$WELCOME_VOICES" candidate rest
  installed="$(_installed_voices)"

  while [ -n "$candidates" ]; do
    case "$candidates" in
      *"|"*) candidate="${candidates%%|*}"; rest="${candidates#*|}" ;;
      *)     candidate="$candidates"; rest="" ;;
    esac
    if [ -n "$candidate" ] && printf '%s\n' "$installed" | grep -Fxq "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
    candidates="$rest"
  done
  return 0
}

# `say` treats [[...]] as embedded speech commands, so anything coming out
# of a reminder title has to lose those brackets before it's spoken.
_speech_safe() {
  printf '%s' "$1" | tr '\n\r\t' '   ' | sed -e 's/\[\[/(/g' -e 's/\]\]/)/g'
}

_greeting_word() {
  local hour; hour="$(date '+%H')"
  hour="${hour#0}"; [ -z "$hour" ] && hour=0
  if [ "$hour" -lt 12 ]; then printf 'Good morning'
  elif [ "$hour" -lt 18 ]; then printf 'Good afternoon'
  else printf 'Good evening'
  fi
}

# Turns records into "Call the bank, at 9:30 AM" style clauses.
_spoken_items() {
  local records="$1" max="$2"
  printf '%s\n' "$records" | awk -F'\t' -v max="$max" '
    $1 == "#note" { next }
    NF >= 2 && $2 != "" {
      n++
      if (n > max) { next }
      if ($1 == "OVERDUE")      { printf "%s, which is overdue.\n", $2 }
      else if ($1 == "flagged") { printf "%s, flagged.\n", $2 }
      else if ($1 != "")        { printf "%s, at %s.\n", $2, $1 }
      else                      { printf "%s.\n", $2 }
    }'
}

# build_spoken_briefing REMINDERS CALENDAR TASKS
build_spoken_briefing() {
  local rem="$1" cal="$2" tsk="$3"
  local n_rem n_cal n_tsk n_overdue text

  n_rem="$(count_records "$rem")"
  n_cal="$(count_records "$cal")"
  n_tsk="$(count_records "$tsk")"
  n_overdue="$(printf '%s\n' "$rem" | awk -F'\t' '$1 == "OVERDUE" { n++ } END { print n + 0 }')"

  local honorific=""
  [ -n "$WELCOME_HONORIFIC" ] && honorific=", $WELCOME_HONORIFIC"

  text="[[slnc 500]]Welcome back, $(_speech_safe "$WELCOME_NAME").[[slnc 350]] "
  text="${text}$(_greeting_word)${honorific}.[[slnc 300]] "
  text="${text}It's $(date '+%-I:%M %p') on $(date '+%A, %B %-d').[[slnc 400]] "

  local parts=""
  if [ "$n_rem" -gt 0 ]; then
    parts="$n_rem $(_plural "$n_rem" reminder reminders) due today"
    if [ "$n_overdue" -gt 0 ]; then
      parts="$parts, $n_overdue of them overdue"
    fi
  fi
  if [ "$n_cal" -gt 0 ]; then
    [ -n "$parts" ] && parts="$parts, and "
    parts="$parts$n_cal $(_plural "$n_cal" event events) on the calendar"
  fi
  if [ "$n_tsk" -gt 0 ] && [ "$n_rem" -eq 0 ] && [ "$n_cal" -eq 0 ]; then
    parts="$n_tsk open $(_plural "$n_tsk" task tasks) on your list"
  fi

  if [ -z "$parts" ]; then
    text="${text}Your day is clear. Nothing due, and nothing on the calendar.[[slnc 300]] "
  else
    text="${text}You have ${parts}.[[slnc 450]] "
    local first=1 line
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      if [ "$first" -eq 1 ]; then
        text="${text}First up: $(_speech_safe "$line")[[slnc 300]] "
        first=0
      else
        text="${text}Then, $(_speech_safe "$line")[[slnc 300]] "
      fi
    done <<EOT
$( { _spoken_items "$rem" "$WELCOME_SPEAK_MAX_ITEMS"
     _spoken_items "$cal" "$WELCOME_SPEAK_MAX_ITEMS"; } \
   | head -n "$WELCOME_SPEAK_MAX_ITEMS")
EOT
  fi

  text="${text}[[slnc 400]]Standing by."
  printf '%s' "$text"
}

# Speaks without blocking, so the dialog and the voice come up together.
speak_async() {
  local text="$1" voice
  have_cmd say || return 0
  [ "$WELCOME_SPEAK" = "1" ] || return 0

  voice="$(resolve_voice)"
  if [ -n "$voice" ]; then
    say -v "$voice" -r "$WELCOME_SPEAK_RATE" "$text" >/dev/null 2>&1 &
  else
    say -r "$WELCOME_SPEAK_RATE" "$text" >/dev/null 2>&1 &
  fi
  return 0
}
