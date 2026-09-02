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
# Plays an already-rendered file. Both speech backends produce mp3s, so
# playback stopped belonging to either of them.
play_file() {
  local file="$1"
  [ -s "$file" ] || return 1
  have_cmd afplay || return 1
  afplay -v "$WELCOME_VOLUME" "$file" 2>/dev/null
}

tts_backend() {
  case "$WELCOME_TTS" in
    say) printf 'say' ;;
    elevenlabs) printf 'elevenlabs' ;;
    openai) printf 'openai' ;;
    piper) printf 'piper' ;;
    auto|*)
      # Paid clones first if they are working, then the local neural
      # voice, then the built-in one. Free and offline beats robotic.
      if eleven_available; then printf 'elevenlabs'
      elif openai_tts_available; then printf 'openai'
      elif piper_available; then printf 'piper'
      else printf 'say'; fi ;;
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
  # "system" means: pass no -v at all, and let `say` use whatever voice is
  # set in System Settings. That is the only way to reach the Siri voices,
  # which are the best free ones on the Mac by a distance and which `say`
  # will not select by name.
  [ "$WELCOME_VOICE" = "system" ] && return 0
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

# The prosody prefix `say` accepts. Sent once at the front, it applies to
# everything after it.
_say_prosody() {
  local out=""
  [ -n "$WELCOME_SAY_PITCH" ] && out="$out[[pbas $WELCOME_SAY_PITCH]] "
  [ -n "$WELCOME_SAY_MODULATION" ] && out="$out[[pmod $WELCOME_SAY_MODULATION]] "
  printf '%s' "$out"
}

say_speak() {
  local text="$1" voice
  have_cmd say || return 1
  text="$(_say_prosody)$(speech_pace "$text" say)"
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

# Records -> "call the bank, which is overdue" - a CLAUSE, one per line,
# with no full stop. Every item used to end in one, and a full stop is a
# hard stop: a briefing made of four-word sentences reads out like a
# telegram being dictated. The caller joins these into real sentences.
_spoken_items() {
  local records="$1" max="$2" count=0 when title
  while IFS="$(printf '\t')" read -r when title _; do
    [ "$when" = "#note" ] && continue
    [ -z "$title" ] && continue
    count=$((count + 1))
    [ "$count" -gt "$max" ] && break
    title="$(speech_clean "$title" | sed -E 's/[.[:space:]]+$//')"
    case "$when" in
      OVERDUE)      printf '%s, which is overdue\n' "$title" ;;
      flagged)      printf '%s, flagged\n' "$title" ;;
      done|failed)  printf '%s\n' "$title" ;;
      "")           printf '%s\n' "$title" ;;
      *)            printf '%s at %s\n' "$title" "$(time_words_relative "$when")" ;;
    esac
  done <<EOT
$records
EOT
}

# "a, b and c" - the way a person lists things out loud.
_join_clauses() {
  awk 'NF { n++; item[n] = $0 }
       END {
         for (i = 1; i <= n; i++) {
           printf "%s", item[i]
           if (i == n - 1) printf " and "
           else if (i < n)  printf ", "
         }
       }'
}

# build_spoken_briefing REMINDERS CALENDAR TASKS MESSAGES MAIL CLAUDE
build_spoken_briefing() {
  local rem="$1" cal="$2" tsk="$3" msg="${4:-}" mail="${5:-}" cld="${6:-}"
  local n_rem n_cal n_tsk n_msg n_mail n_cld n_overdue text parts=""

  n_rem="$(count_records "$rem")"
  n_cal="$(count_records "$cal")"
  n_tsk="$(count_records "$tsk")"
  n_msg="$(count_records "$msg")"
  n_mail="$(count_records "$mail")"
  n_cld="$(count_records "$cld")"
  n_overdue="$(printf '%s\n' "$rem" | awk -F'\t' '$1 == "OVERDUE" { n++ } END { print n + 0 }')"

  local honorific=""
  [ -n "$WELCOME_HONORIFIC" ] && honorific=", $WELCOME_HONORIFIC"

  # Spoken, not printed. The old version was a stack of four-word
  # declaratives - "Three reminders due today. Two events on the calendar.
  # Four unread emails." - which reads crisply on a page and out loud
  # sounds like a telegram: every full stop is a hard stop, and there were
  # nine of them before the first real clause. These join into sentences.
  local counts=""
  {
    if [ "$n_rem" -gt 0 ]; then
      if [ "$n_overdue" -gt 0 ]; then
        printf '%s %s due today, %s of them overdue\n' \
          "$(num_word "$n_rem")" "$(_plural "$n_rem" reminder reminders)" "$(num_word "$n_overdue")"
      else
        printf '%s %s due today\n' "$(num_word "$n_rem")" "$(_plural "$n_rem" reminder reminders)"
      fi
    fi
    [ "$n_cal" -gt 0 ] && printf '%s %s on the calendar\n' \
      "$(num_word "$n_cal")" "$(_plural "$n_cal" event events)"
    [ "$n_msg" -gt 0 ] && printf '%s unread %s\n' \
      "$(num_word "$n_msg")" "$(_plural "$n_msg" message messages)"
    [ "$n_mail" -gt 0 ] && printf '%s unread %s\n' \
      "$(num_word "$n_mail")" "$(_plural "$n_mail" email emails)"
    [ "$n_tsk" -gt 0 ] && printf '%s open %s\n' \
      "$(num_word "$n_tsk")" "$(_plural "$n_tsk" task tasks)"
    true
  } > "$WELCOME_STATE_DIR/.counts.$$" 2>/dev/null
  counts="$(_join_clauses < "$WELCOME_STATE_DIR/.counts.$$")"
  rm -f "$WELCOME_STATE_DIR/.counts.$$"

  # The greeting and the time run together as one sentence, because that
  # is how someone would actually say it.
  text="Welcome back, $(speech_clean "$WELCOME_NAME") - $(printf '%s' "$(_greeting_word)" | tr '[:upper:]' '[:lower:]')${honorific}. "
  if [ -n "$counts" ]; then
    text="${text}It's $(now_words) on $(today_words), and you have ${counts}. "
  else
    text="${text}It's $(now_words) on $(today_words), and the day is clear - nothing due, nothing scheduled. "
  fi

  local items
  items="$( { _spoken_items "$cld" "$WELCOME_SPEAK_MAX_ITEMS"
              _spoken_items "$rem" "$WELCOME_SPEAK_MAX_ITEMS"
              _spoken_items "$cal" "$WELCOME_SPEAK_MAX_ITEMS"
              if [ "$n_rem" -eq 0 ] && [ "$n_cal" -eq 0 ]; then
                _spoken_items "$tsk" "$WELCOME_SPEAK_MAX_ITEMS"
              fi
              true; } | head -n "$WELCOME_SPEAK_MAX_ITEMS")"

  if [ -n "$(printf '%s' "$items" | tr -d '[:space:]')" ]; then
    # "First X, then Y, then Z" - one sentence, not three headings with
    # colons after them.
    local first rest joined idx=0 line
    joined=""
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      idx=$((idx + 1))
      case "$idx" in
        1) joined="first, $line" ;;
        *) joined="$joined, then $line" ;;
      esac
    done <<EOT
$items
EOT
    [ -n "$joined" ] && text="${text}${joined}. "
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
      # Each step down is a real voice before it is a robot one: a hosted
      # service refusing is not a reason to give up on the other one.
      elevenlabs) eleven_speak "$text" || openai_speak "$text" || piper_speak "$text" || say_speak "$text" ;;
      openai)     openai_speak "$text" || piper_speak "$text" || say_speak "$text" ;;
      piper)      piper_speak "$text" || say_speak "$text" ;;
      *)          say_speak "$text" ;;
    esac
  ) >/dev/null 2>&1 &
  WELCOME_SPEAK_PID=$!
}

# Renders TEXT and prints the path to the audio, without playing it.
# The listener plays it itself, which saves launching a second shell and
# an afplay just to make a sound - on a one-word reply that overhead was
# most of the wait.
speak_to_file() {
  local text="$1" file
  [ "$WELCOME_SPEAK" = "1" ] || return 1
  [ -z "$text" ] && return 1

  case "$(tts_backend)" in
    elevenlabs)
      file="$(eleven_cache_path "$text")"
      [ -s "$file" ] && { printf '%s' "$file"; return 0; }
      # A hosted voice that refuses is not a reason to go silent when a
      # second service is configured and willing.
      if eleven_synthesize "$text" "$file"; then printf '%s' "$file"; return 0; fi
      openai_tts_available || return 1
      ;;
    openai) ;;
    piper)
      file="$(piper_cache_path "$text")"
      [ -s "$file" ] && { printf '%s' "$file"; return 0; }
      piper_synthesize "$text" "$file" || return 1
      printf '%s' "$file"; return 0 ;;
    *) return 1 ;;
  esac

  file="$(openai_tts_cache_path "$text")"
  [ -s "$file" ] && { printf '%s' "$file"; return 0; }
  if openai_tts_synthesize "$text" "$file"; then printf '%s' "$file"; return 0; fi
  piper_available || return 1
  file="$(piper_cache_path "$text")"
  [ -s "$file" ] && { printf '%s' "$file"; return 0; }
  piper_synthesize "$text" "$file" || return 1
  printf '%s' "$file"
}

# Stops whatever is currently talking.
hush() {
  pkill -x afplay 2>/dev/null
  pkill -x say 2>/dev/null
  return 0
}
