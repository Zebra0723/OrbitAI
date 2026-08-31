#!/bin/bash
# The spoken half of the briefing.
#
# Two things matter here. First, the phrasing is not the screen's phrasing:
# a screen reads well in columns, a voice reads well in sentences. Second,
# everything is written out in words by lib/speech_text.sh before it
# reaches an engine - no digits, no clock times, and no engine-specific
# markup like [[slnc]], which newer voices read aloud instead of obeying.

# ---------------------------------------------------------------- backend

# Echoes the backend that will actually be used: elevenlabs or say.
tts_backend() {
  case "$WELCOME_TTS" in
    say) printf 'say' ;;
    elevenlabs) printf 'elevenlabs' ;;
    auto|*)
      if eleven_available; then printf 'elevenlabs'; else printf 'say'; fi ;;
  esac
}

# --- Apple `say`, the offline fallback ---

_installed_voices() {
  say -v '?' 2>/dev/null \
    | sed -E 's/[[:space:]]+[a-z]{2}(_[A-Z]{2})?[[:space:]]+#.*$//' \
    | sed -E 's/[[:space:]]+$//'
}

# First voice from WELCOME_VOICES that's installed; empty = system default.
resolve_voice() {
  if [ -n "$WELCOME_VOICE" ]; then printf '%s' "$WELCOME_VOICE"; return 0; fi
  have_cmd say || return 0

  local installed candidates="$WELCOME_VOICES" candidate rest
  installed="$(_installed_voices)"
  while [ -n "$candidates" ]; do
    case "$candidates" in
      *"|"*) candidate="${candidates%%|*}"; rest="${candidates#*|}" ;;
      *)     candidate="$candidates"; rest="" ;;
    esac
    if [ -n "$candidate" ] && printf '%s\n' "$installed" | grep -Fxq "$candidate"; then
      printf '%s' "$candidate"; return 0
    fi
    candidates="$rest"
  done
  return 0
}

say_speak() {
  local text="$1" voice
  have_cmd say || return 1
  voice="$(resolve_voice)"
  if [ -n "$voice" ]; then
    say -v "$voice" -r "$WELCOME_SPEAK_RATE" "$text" >/dev/null 2>&1
  else
    say -r "$WELCOME_SPEAK_RATE" "$text" >/dev/null 2>&1
  fi
}

# ------------------------------------------------------------ the wording

_greeting_word() {
  local hour; hour="$(date '+%-H')"
  if [ "$hour" -lt 12 ]; then printf 'Good morning'
  elif [ "$hour" -lt 18 ]; then printf 'Good afternoon'
  else printf 'Good evening'
  fi
}

# Records -> "Call the bank, which is overdue." one per line.
_spoken_items() {
  local records="$1" max="$2" count=0 when title
  while IFS="$(printf '\t')" read -r when title _; do
    [ "$when" = "#note" ] && continue
    [ -z "$title" ] && continue
    count=$((count + 1))
    [ "$count" -gt "$max" ] && break
    title="$(speech_clean "$title")"
    case "$when" in
      OVERDUE) printf '%s. That one is overdue.\n' "$title" ;;
      flagged) printf '%s. Flagged.\n' "$title" ;;
      "")      printf '%s.\n' "$title" ;;
      *)       printf '%s, at %s.\n' "$title" "$(time_words_relative "$when")" ;;
    esac
  done <<EOT
$records
EOT
}

# build_spoken_briefing REMINDERS CALENDAR TASKS
build_spoken_briefing() {
  local rem="$1" cal="$2" tsk="$3"
  local n_rem n_cal n_tsk n_overdue text parts=""

  n_rem="$(count_records "$rem")"
  n_cal="$(count_records "$cal")"
  n_tsk="$(count_records "$tsk")"
  n_overdue="$(printf '%s\n' "$rem" | awk -F'\t' '$1 == "OVERDUE" { n++ } END { print n + 0 }')"

  local honorific=""
  [ -n "$WELCOME_HONORIFIC" ] && honorific=", $WELCOME_HONORIFIC"

  # Short declaratives. "You have four reminders, and there are also two
  # events" hedges; "Four reminders due today. Two events." doesn't.
  text="Welcome back, $(speech_clean "$WELCOME_NAME"). "
  text="${text}$(_greeting_word)${honorific}. "
  text="${text}It's $(now_words), $(today_words). "

  if [ "$n_rem" -gt 0 ]; then
    parts="$(num_word "$n_rem") $(_plural "$n_rem" reminder reminders) due today"
    if [ "$n_overdue" -gt 0 ]; then
      parts="$parts, $(num_word "$n_overdue") overdue"
    fi
    parts="$parts. "
  fi
  if [ "$n_cal" -gt 0 ]; then
    parts="$parts$(num_word "$n_cal") $(_plural "$n_cal" event events) on the calendar. "
  fi
  if [ "$n_tsk" -gt 0 ] && [ "$n_rem" -eq 0 ] && [ "$n_cal" -eq 0 ]; then
    parts="$(num_word "$n_tsk") open $(_plural "$n_tsk" task tasks). "
  elif [ "$n_tsk" -gt 0 ]; then
    parts="$parts$(num_word "$n_tsk") open $(_plural "$n_tsk" task tasks). "
  fi

  if [ -z "$parts" ]; then
    text="${text}The day is clear. Nothing due, nothing scheduled. "
  else
    text="${text}${parts}"
    local idx=0 line
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      idx=$((idx + 1))
      case "$idx" in
        1) text="${text}Top of the list: $line " ;;
        2) text="${text}Next: $line " ;;
        *) text="${text}After that: $line " ;;
      esac
    done <<EOT
$( { _spoken_items "$rem" "$WELCOME_SPEAK_MAX_ITEMS"
     _spoken_items "$cal" "$WELCOME_SPEAK_MAX_ITEMS"
     [ "$n_rem" -eq 0 ] && [ "$n_cal" -eq 0 ] && _spoken_items "$tsk" "$WELCOME_SPEAK_MAX_ITEMS"
     true; } | head -n "$WELCOME_SPEAK_MAX_ITEMS")
EOT
  fi

  text="${text}$WELCOME_CLOSER"
  # Collapse the whitespace the assembly above leaves behind.
  printf '%s' "$text" | sed -E 's/[[:space:]]+/ /g; s/ $//' | capitalize_sentences
}

# ------------------------------------------------------------- delivery

# Speaks in the background and leaves the pid in WELCOME_SPEAK_PID, so the
# caller can wait for it rather than exiting mid-sentence.
speak_async() {
  local text="$1"
  [ "$WELCOME_SPEAK" = "1" ] || return 0
  [ -z "$text" ] && return 0

  (
    case "$(tts_backend)" in
      elevenlabs) eleven_speak "$text" || say_speak "$text" ;;
      *)          say_speak "$text" ;;
    esac
  ) >/dev/null 2>&1 &
  WELCOME_SPEAK_PID=$!
}

# Stops whatever is currently talking.
hush() {
  pkill -x afplay 2>/dev/null
  pkill -x say 2>/dev/null
  return 0
}
