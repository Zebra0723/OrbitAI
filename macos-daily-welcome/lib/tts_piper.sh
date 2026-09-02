#!/bin/bash
# Piper: a neural voice that runs on this Mac, for free.
#
# No key, no account, no per-word cost, and nothing leaves the machine.
# It is not as good as a hosted clone, but it is far better than the
# built-in `say` voices and it cannot run out of credit halfway through a
# briefing, which is the failure mode that matters.
#
# Setup is two things - the binary and one voice file. Piper ships on
# PyPI, not in Homebrew core:
#   brew install pipx && pipx install piper-tts
#   daily-welcome --setup-piper        downloads a voice and points at it

piper_bin() {
  if [ -n "$WELCOME_PIPER_BIN" ] && [ -x "$WELCOME_PIPER_BIN" ]; then
    printf '%s' "$WELCOME_PIPER_BIN"; return 0
  fi
  command -v piper 2>/dev/null && return 0

  # pipx and pip --user put it somewhere that is often not on the PATH a
  # menu bar app inherits, so look in the usual places rather than
  # declaring it missing.
  local candidate
  for candidate in "$HOME/.local/bin/piper" \
                   "$HOME/Library/Python/3.*/bin/piper" \
                   /opt/homebrew/bin/piper /usr/local/bin/piper; do
    for expanded in $candidate; do
      [ -x "$expanded" ] && { printf '%s' "$expanded"; return 0; }
    done
  done
  return 1
}

piper_available() {
  have_cmd afplay || return 1
  piper_bin >/dev/null 2>&1 || return 1
  [ -s "$WELCOME_PIPER_MODEL" ]
}

_piper_cache_key() {
  printf '%s|%s|%s' "$1" "$WELCOME_PIPER_MODEL" "$WELCOME_PIPER_LENGTH" \
    | (shasum -a 256 2>/dev/null || sha256sum 2>/dev/null) \
    | awk '{print $1}' | cut -c1-32
}

piper_cache_path() {
  local cache_dir="$WELCOME_STATE_DIR/cache" key
  mkdir -p "$cache_dir"
  key="$(_piper_cache_key "$1")"
  # Piper writes WAV, not mp3. afplay is happy with either.
  if [ -n "$key" ]; then printf '%s/pi-%s.wav' "$cache_dir" "$key"
  else printf '%s/pi-last.wav' "$cache_dir"; fi
}

piper_synthesize() {
  local text="$1" out="$2" bin
  bin="$(piper_bin)" || return 1
  [ -s "$WELCOME_PIPER_MODEL" ] || {
    printf 'no piper voice model - run: daily-welcome --setup-piper' \
      > "$WELCOME_STATE_DIR/last-voice-error" 2>/dev/null
    return 1
  }

  text="$(speech_pace "$text" piper)"

  # length_scale below 1 speeds it up; the default reads slightly slowly.
  if ! printf '%s' "$text" | "$bin" \
        --model "$WELCOME_PIPER_MODEL" \
        --length_scale "$WELCOME_PIPER_LENGTH" \
        --output_file "$out" >/dev/null 2>"$WELCOME_STATE_DIR/last-voice-error"; then
    rm -f "$out"
    return 1
  fi
  [ -s "$out" ] || { rm -f "$out"; return 1; }
}

piper_speak() {
  local text="$1" file
  file="$(piper_cache_path "$text")"
  if [ ! -s "$file" ]; then
    piper_synthesize "$text" "$file" || return 1
  fi
  afplay -v "$WELCOME_VOLUME" "$file" 2>/dev/null
}
