#!/bin/bash
# Orbit's voice: which engine speaks, and how.
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
    # An explicitly chosen provider still has to be able to speak. It
    # used to be taken at its word, so a setting written when a key
    # worked kept naming that provider long after the key stopped -
    # reported everywhere as the voice in use, while something else did
    # the talking.
    elevenlabs) if eleven_available; then printf 'elevenlabs'
                elif piper_available; then printf 'piper'
                else printf 'say'; fi ;;
    openai)     if openai_tts_available; then printf 'openai'
                elif piper_available; then printf 'piper'
                else printf 'say'; fi ;;
    piper)      if piper_available; then printf 'piper'
                else printf 'say'; fi ;;
    auto|*)
      # ElevenLabs if it is working, then the local neural voice, then
      # the built-in one. OpenAI is deliberately not in this chain - it
      # is still available as WELCOME_TTS=openai for anyone who wants it,
      # but it is not something to fall into by accident and be billed
      # for.
      if eleven_available; then printf 'elevenlabs'
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
      # "which is overdue" is a relative clause in the middle of a
      # spoken list, and the sentence before it has already said how many
      # are overdue. Two words does the same job.
      OVERDUE)      printf '%s, already overdue\n' "$title" ;;
      flagged)      printf '%s, flagged\n' "$title" ;;
      done|failed)  printf '%s\n' "$title" ;;
      "")           printf '%s\n' "$title" ;;
      *)            printf '%s at %s\n' "$title" "$(time_words_relative "$when")" ;;
    esac
  done <<EOT
$records
EOT
}

# Speaks in the background and leaves the pid in WELCOME_SPEAK_PID, so the
# caller can wait for it rather than exiting mid-sentence.
speak_async() {
  local text="$1"
  [ "$WELCOME_SPEAK" = "1" ] || return 0
  [ -z "$text" ] && return 0
  # The backstop: whatever asked for this, it is not worth talking into a
  # recording of somebody's voice.
  enrolling_now 2>/dev/null && return 0

  (
    case "$(tts_backend)" in
      # Each step down is a real voice before it is a robot one: a hosted
      # service refusing is not a reason to give up on the other one.
      elevenlabs) eleven_speak "$text" || piper_speak "$text" || say_speak "$text" ;;
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
