#!/bin/bash
# OpenAI as the understanding layer.
#
# The rules are fast, free and predictable, and they cover the phrasings
# you use most. They are also brittle at the edges: "go to Claude and say
# this", "shoot mama a text", "kill the volume" are all obvious to a person
# and invisible to a case statement. This is what catches those.
#
# It never decides what happens - it only decides what you meant. The same
# confirmation rules apply to an intent that came from here as to one the
# rules produced.

# The key, in the same three places as the ElevenLabs one.
openai_api_key() {
  if [ -n "${OPENAI_API_KEY:-}" ]; then printf '%s' "$OPENAI_API_KEY"; return 0; fi
  local key
  if have_cmd security; then
    key="$(security find-generic-password -s "$ORBIT_OPENAI_KEYCHAIN" -w 2>/dev/null)"
    if [ -n "$key" ]; then printf '%s' "$key"; return 0; fi
  fi
  if [ -f "$ORBIT_OPENAI_KEY_FILE" ]; then
    tr -d '\n\r' < "$ORBIT_OPENAI_KEY_FILE"; return 0
  fi
  return 1
}

openai_available() {
  have_cmd python3 && openai_api_key >/dev/null 2>&1
}

# openai_intent "<transcript>" -> intent <TAB> arg1 <TAB> arg2
openai_intent() {
  local text="$1" key out rc
  openai_available || return 1

  key="$(openai_api_key)" || return 1

  # Macro phrases go along so it can recognise the user's own words.
  local phrases=""
  phrases="$(macros_list 2>/dev/null | cut -f1 | tr '\n' ',' | sed 's/,$//')"

  out="$(OPENAI_API_KEY="$key" ORBIT_MACRO_PHRASES="$phrases" \
    run_with_timeout "$ORBIT_OPENAI_TIMEOUT" \
    python3 "$ROOT/lib/openai_intent.py" "$text")"
  rc=$?

  if [ "$rc" -ne 0 ]; then
    welcome_log "openai: $(last_error)"
    return 1
  fi
  case "$out" in
    none*|"") return 1 ;;
  esac
  printf '%s\n' "$out"
}

# openai_chat "<what they said>" -> a spoken reply
#
# This is what makes it a thing you talk to rather than a parser that
# gives up. Anything that isn't a command lands here, with the last few
# turns for company.
openai_chat() {
  local text="$1" key out rc history
  openai_available || return 1
  key="$(openai_api_key)" || return 1

  history="$(chat_history)"
  out="$(OPENAI_API_KEY="$key" ORBIT_CHAT_HISTORY="$history" \
    run_with_timeout "$ORBIT_OPENAI_TIMEOUT" \
    python3 "$ROOT/lib/openai_intent.py" --chat "$text")"
  rc=$?
  [ "$rc" -ne 0 ] && { welcome_log "openai chat: $(last_error)"; return 1; }
  [ -z "$out" ] && return 1

  chat_remember "$text" "$out"
  printf '%s' "$out"
}

# The last few turns, oldest first, as "role<TAB>text" lines.
_chat_file() { printf '%s/chat-history' "$WELCOME_STATE_DIR"; }

chat_history() {
  [ -f "$(_chat_file)" ] || return 0
  # Anything older than the conversation window is not context, it is noise.
  if [ -z "$(find "$(_chat_file)" -mmin "-$((ORBIT_CONVERSATION_SECONDS / 60 + 5))" 2>/dev/null)" ]; then
    rm -f "$(_chat_file)"
    return 0
  fi
  tail -n "$((ORBIT_CHAT_TURNS * 2))" "$(_chat_file)"
}

chat_remember() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  {
    printf 'user\t%s\n' "$(printf '%s' "$1" | tr '\n' ' ')"
    printf 'assistant\t%s\n' "$(printf '%s' "$2" | tr '\n' ' ')"
  } >> "$(_chat_file)"
  tail -n 40 "$(_chat_file)" > "$(_chat_file).tmp" && mv "$(_chat_file).tmp" "$(_chat_file)"
}
