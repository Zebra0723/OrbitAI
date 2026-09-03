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
# The models an endpoint will actually serve today.
#
# Named models get decommissioned - "llama-3.3-70b-versatile" was the
# recommended one here until Groq retired it - and a config file that
# names a dead model fails with an error nobody reads. Asking is more
# reliable than remembering.
openai_models() {
  local key base
  base="${1:-$ORBIT_OPENAI_BASE}"
  key="${2:-$(openai_api_key)}" || return 1
  curl -fsS --max-time 10 -H "Authorization: Bearer $key" "$base/models" 2>/dev/null \
    | python3 -c 'import json,sys
try:
    data = json.load(sys.stdin).get("data", [])
except Exception:
    raise SystemExit(1)
for m in data:
    name = m.get("id") or m.get("name") or ""
    if name:
        print(name.replace("models/", ""))'
}

# The best of them for this job, or nothing if it cannot tell.
#
# Working out what somebody meant by one spoken sentence is a small job.
# A bigger model understands more and takes noticeably longer to start
# talking, and on a voice assistant the wait is the thing you feel - so
# the small fast ones come first, and anything that is not a chat model
# at all is left out.
openai_pick_model() {
  openai_models "$@" | python3 -c '
import sys

models = [m.strip() for m in sys.stdin if m.strip()]
if not models:
    raise SystemExit(1)

# Not chat models: transcription, speech, embeddings, safety classifiers,
# image generation. They will all happily be listed alongside.
def usable(name):
    bad = ("whisper", "tts", "embed", "guard", "moderation", "image",
           "dall-e", "vision", "rerank", "distil")
    return not any(b in name.lower() for b in bad)

models = [m for m in models if usable(m)]
if not models:
    raise SystemExit(1)

# Small and quick first. Substrings rather than exact names, so this
# keeps working when the numbers move.
for want in ("instant", "8b", "flash-lite", "flash", "mini", "scout",
             "20b", "haiku", "small", "turbo", "instruct", "versatile"):
    for m in models:
        if want in m.lower():
            print(m)
            raise SystemExit(0)
print(models[0])
'
}

openai_intent() {
  local text="$1" key out rc
  openai_available || return 1

  key="$(openai_api_key)" || return 1

  # Macro phrases go along so it can recognise the user's own words.
  local phrases=""
  phrases="$(macros_list 2>/dev/null | cut -f1 | tr '\n' ',' | sed 's/,$//')"

  out="$(OPENAI_API_KEY="$key" ORBIT_MACRO_PHRASES="$phrases" \
    ORBIT_OPENAI_BASE="$ORBIT_OPENAI_BASE" ORBIT_OPENAI_MODEL="$ORBIT_OPENAI_MODEL" \
    ORBIT_CHAT_HISTORY="$(chat_history)" \
    ORBIT_MEMORY_FACTS="$(memory_facts | cut -f2-)" \
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
  local past=""
  memory_asks_about_past "$text" && past="$(memory_search "$text" "$ORBIT_MEMORY_MATCHES" 2>/dev/null)"
  history="$(printf '%s\n%s\n%s' "$history" \
    "$(memory_events "$ORBIT_MEMORY_EVENTS" 2>/dev/null)" "$past" | grep . )"

  out="$(OPENAI_API_KEY="$key" ORBIT_CHAT_HISTORY="$history" \
    ORBIT_OPENAI_BASE="$ORBIT_OPENAI_BASE" ORBIT_OPENAI_MODEL="$ORBIT_OPENAI_MODEL" \
    run_with_timeout "$ORBIT_OPENAI_TIMEOUT" \
    python3 "$ROOT/lib/openai_intent.py" --chat "$text")"
  rc=$?
  [ "$rc" -ne 0 ] && { welcome_log "openai chat: $(last_error)"; return 1; }
  [ -z "$out" ] && return 1

  chat_remember "$text" "$out"
  printf '%s' "$out"
}

