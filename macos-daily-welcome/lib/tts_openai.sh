#!/bin/bash
# OpenAI speech backend - the alternative when ElevenLabs won't play.
#
# Same shape as the ElevenLabs one and the same contract: any missing key,
# network problem or API error returns non-zero and the caller drops to
# Apple's `say`, so a bad day still gets you a briefing. It reuses the
# OpenAI key already set for understanding what you say, so switching to
# it costs nothing but a config line.

OPENAI_TTS_API="https://api.openai.com/v1/audio/speech"

openai_tts_available() {
  have_cmd curl && have_cmd afplay && openai_api_key >/dev/null 2>&1
}

_openai_tts_cache_key() {
  printf '%s|%s|%s|%s' "$1" "$WELCOME_OPENAI_VOICE" "$WELCOME_OPENAI_TTS_MODEL" \
    "$WELCOME_OPENAI_TTS_INSTRUCTIONS" \
    | (shasum -a 256 2>/dev/null || sha256sum 2>/dev/null) \
    | awk '{print $1}' | cut -c1-32
}

openai_tts_cache_path() {
  local cache_dir="$WELCOME_STATE_DIR/cache" key
  mkdir -p "$cache_dir"
  key="$(_openai_tts_cache_key "$1")"
  if [ -n "$key" ]; then
    printf '%s/oa-%s.mp3' "$cache_dir" "$key"
  else
    printf '%s/oa-last.mp3' "$cache_dir"
  fi
}

_openai_tts_body() {
  local text="$1"
  # `instructions` steers delivery on the newer model and is rejected by
  # the older one, so it is only sent when there is something to say.
  if [ -n "$WELCOME_OPENAI_TTS_INSTRUCTIONS" ] && [ "$2" = "1" ]; then
    printf '{"model":"%s","voice":"%s","input":"%s","instructions":"%s","response_format":"mp3"}' \
      "$WELCOME_OPENAI_TTS_MODEL" "$WELCOME_OPENAI_VOICE" \
      "$(json_escape "$text")" "$(json_escape "$WELCOME_OPENAI_TTS_INSTRUCTIONS")"
  else
    printf '{"model":"%s","voice":"%s","input":"%s","response_format":"mp3"}' \
      "$WELCOME_OPENAI_TTS_MODEL" "$WELCOME_OPENAI_VOICE" "$(json_escape "$text")"
  fi
}

openai_tts_synthesize() {
  local text="$1" out="$2" key code attempt

  text="$(speech_pace "$text")"
  key="$(openai_api_key)" || return 1

  for attempt in 1 0; do
    code="$(curl -sS --max-time "$WELCOME_ELEVEN_TIMEOUT" \
      -X POST "$OPENAI_TTS_API" \
      -H "Authorization: Bearer $key" \
      -H "Content-Type: application/json" \
      -d "$(_openai_tts_body "$text" "$attempt")" \
      -o "$out" -w '%{http_code}' 2>/dev/null)"

    [ "$code" = "200" ] && [ -s "$out" ] && return 0
    welcome_log "openai tts: HTTP $code"
    [ "$code" = "401" ] || [ "$code" = "403" ] && break
  done

  if [ -s "$out" ]; then
    local reason
    reason="$(head -c 400 "$out" | tr -d '\n')"
    welcome_log "openai tts: $reason"
    printf '%s' "$reason" > "$WELCOME_STATE_DIR/last-voice-error" 2>/dev/null
  fi
  rm -f "$out"
  return 1
}

# The voices OpenAI offers, for `daily-welcome --voices`.
openai_tts_voices() {
  printf 'alloy    neutral\nash      warm, low\nballad   soft\ncoral    bright, American female\n'
  printf 'echo     even\nfable    British\nnova     clear, American female\nonyx     deep\n'
  printf 'sage     calm\nshimmer  light, American female\n'
}

# Renders and plays in one go, the counterpart to eleven_speak.
openai_speak() {
  local text="$1" file
  file="$(openai_tts_cache_path "$text")"
  if [ ! -s "$file" ]; then
    openai_tts_synthesize "$text" "$file" || return 1
  fi
  afplay -v "$WELCOME_VOLUME" "$file" 2>/dev/null
}
