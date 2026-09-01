#!/bin/bash
# ElevenLabs speech backend.
#
# The voice is a hosted professional clone, so it can only come from their
# API - there's no local equivalent to fall back to for the voice itself.
# What we can do is fail softly: any missing key, network problem, or API
# error returns non-zero and the caller speaks with Apple's `say` instead,
# so a flaky morning still gets you a briefing.

ELEVEN_API="https://api.elevenlabs.io"

# Key lookup, most specific first. The Keychain is the intended home;
# `daily-welcome --set-key` puts it there.
eleven_api_key() {
  if [ -n "${WELCOME_ELEVEN_API_KEY:-}" ]; then
    printf '%s' "$WELCOME_ELEVEN_API_KEY"; return 0
  fi
  local key
  if have_cmd security; then
    key="$(security find-generic-password -s "$WELCOME_KEYCHAIN_SERVICE" -w 2>/dev/null)"
    if [ -n "$key" ]; then printf '%s' "$key"; return 0; fi
  fi
  if [ -f "$WELCOME_ELEVEN_KEY_FILE" ]; then
    tr -d '\n\r' < "$WELCOME_ELEVEN_KEY_FILE"; return 0
  fi
  return 1
}

eleven_available() {
  have_cmd curl && have_cmd afplay && eleven_api_key >/dev/null 2>&1
}

# Pulls "voice_id" / "name" pairs out of the voices response without
# requiring jq (which most Macs don't have).
_parse_voice_id() {
  local want="$1"
  if have_cmd jq; then
    jq -r --arg want "$want" '
      (.voices // []) as $v
      | ( [$v[] | select((.name // "" | ascii_downcase) == ($want | ascii_downcase))]
          + $v )[0].voice_id // empty'
    return 0
  fi
  awk -v want="$want" '
    BEGIN { RS = "\"voice_id\"[[:space:]]*:[[:space:]]*\""; first = "" }
    NR == 1 { next }
    {
      id = substr($0, 1, index($0, "\"") - 1)
      rest = $0
      name = ""
      if (match(rest, /"name"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        name = substr(rest, RSTART, RLENGTH)
        sub(/^"name"[[:space:]]*:[[:space:]]*"/, "", name)
        sub(/"$/, "", name)
      }
      if (first == "") first = id
      if (tolower(name) == tolower(want)) { print id; found = 1; exit }
    }
    END { if (!found && first != "") print first }'
}

# Every voice in the account, as "name <TAB> id". Used by --voices, so you
# can see what you actually have rather than guessing at a name.
eleven_list_voices() {
  local key response
  key="$(eleven_api_key)" || return 1
  response="$(curl -sS --max-time 20 -H "xi-api-key: $key" \
    "$ELEVEN_API/v2/voices?page_size=100" 2>/dev/null)" || return 1

  if have_cmd jq; then
    printf '%s' "$response" | jq -r '.voices[]? | "\(.name)\t\(.voice_id)"'
    return 0
  fi
  printf '%s' "$response" | awk '
    BEGIN { RS = "\"voice_id\"[[:space:]]*:[[:space:]]*\"" }
    NR == 1 { next }
    {
      id = substr($0, 1, index($0, "\"") - 1)
      name = ""
      if (match($0, /"name"[[:space:]]*:[[:space:]]*"[^"]*"/)) {
        name = substr($0, RSTART, RLENGTH)
        sub(/^"name"[[:space:]]*:[[:space:]]*"/, "", name)
        sub(/"$/, "", name)
      }
      if (name != "") printf "%s\t%s\n", name, id
    }'
}

# Resolves the configured voice name to an id, once, then remembers it.
eleven_voice_id() {
  if [ -n "$WELCOME_ELEVEN_VOICE_ID" ]; then
    printf '%s' "$WELCOME_ELEVEN_VOICE_ID"; return 0
  fi

  local cache="$WELCOME_STATE_DIR/eleven-voice-id" cached_name cached_id
  if [ -f "$cache" ]; then
    cached_name="$(cut -f1 < "$cache")"
    cached_id="$(cut -f2 < "$cache")"
    if [ "$cached_name" = "$WELCOME_ELEVEN_VOICE_NAME" ] && [ -n "$cached_id" ]; then
      printf '%s' "$cached_id"; return 0
    fi
  fi

  local key response id
  key="$(eleven_api_key)" || return 1

  # url-encode the search term (spaces are the only realistic issue)
  local search
  search="$(printf '%s' "$WELCOME_ELEVEN_VOICE_NAME" | sed 's/ /%20/g')"

  response="$(curl -sS --max-time 20 \
    -H "xi-api-key: $key" \
    "$ELEVEN_API/v2/voices?search=$search&page_size=30" 2>/dev/null)" || return 1

  id="$(printf '%s' "$response" | _parse_voice_id "$WELCOME_ELEVEN_VOICE_NAME")"
  if [ -z "$id" ]; then
    # The search returned nothing, so the name isn't in this account at all.
    # A voice from the ElevenLabs library has to be added to your voices
    # before the API will speak with it.
    welcome_log "elevenlabs: no voice named '$WELCOME_ELEVEN_VOICE_NAME' in your account - add it in ElevenLabs, or run: daily-welcome --use-voice \"<name>\""
    return 1
  fi

  printf '%s\t%s' "$WELCOME_ELEVEN_VOICE_NAME" "$id" > "$cache"
  printf '%s' "$id"
}

_eleven_body() {
  local text="$1" with_speed="$2"
  local speed_field=""
  [ "$with_speed" = "1" ] && speed_field=",\"speed\":$WELCOME_ELEVEN_SPEED"
  cat <<JSON
{"text":"$(json_escape "$text")",
 "model_id":"$WELCOME_ELEVEN_MODEL",
 "voice_settings":{"stability":$WELCOME_ELEVEN_STABILITY,
                   "similarity_boost":$WELCOME_ELEVEN_SIMILARITY,
                   "style":$WELCOME_ELEVEN_STYLE,
                   "use_speaker_boost":$WELCOME_ELEVEN_SPEAKER_BOOST$speed_field}}
JSON
}

# eleven_synthesize TEXT OUTFILE
eleven_synthesize() {
  local text="$1" out="$2"
  local key voice code attempt

  key="$(eleven_api_key)" || return 1
  voice="$(eleven_voice_id)" || return 1

  # `speed` is only accepted on newer models; if it's rejected, try again
  # without it rather than losing the voice over a tuning parameter.
  for attempt in 1 0; do
    code="$(curl -sS --max-time "$WELCOME_ELEVEN_TIMEOUT" \
      -X POST "$ELEVEN_API/v1/text-to-speech/$voice?output_format=$WELCOME_ELEVEN_FORMAT" \
      -H "xi-api-key: $key" \
      -H "Content-Type: application/json" \
      -d "$(_eleven_body "$text" "$attempt")" \
      -o "$out" -w '%{http_code}' 2>/dev/null)"

    if [ "$code" = "200" ] && [ -s "$out" ]; then
      return 0
    fi
    welcome_log "elevenlabs: HTTP $code"
    if [ "$code" = "401" ] || [ "$code" = "403" ]; then
      break   # a bad key won't get better on retry
    fi
  done

  # The failed response body landed in $out; keep the reason, drop the file.
  if [ -s "$out" ]; then
    welcome_log "elevenlabs: $(head -c 300 "$out" | tr -d '\n')"
  fi
  rm -f "$out"
  return 1
}

_eleven_cache_key() {
  printf '%s|%s|%s|%s|%s|%s|%s' "$1" "$WELCOME_ELEVEN_VOICE_NAME$WELCOME_ELEVEN_VOICE_ID" \
    "$WELCOME_ELEVEN_MODEL" "$WELCOME_ELEVEN_STABILITY" "$WELCOME_ELEVEN_SIMILARITY" \
    "$WELCOME_ELEVEN_STYLE" "$WELCOME_ELEVEN_SPEED" \
    | shasum -a 256 2>/dev/null | cut -c1-32
}

_eleven_prune_cache() {
  local dir="$1" keep=40
  ls -t "$dir"/*.mp3 2>/dev/null | tail -n "+$((keep + 1))" | while IFS= read -r old; do
    rm -f "$old"
  done
}

# Speaks TEXT with the hosted voice. Non-zero means "couldn't", and the
# caller should fall back to `say`.
eleven_speak() {
  local text="$1"
  eleven_available || return 1

  local cache_dir="$WELCOME_STATE_DIR/cache" key file
  mkdir -p "$cache_dir"

  key="$(_eleven_cache_key "$text")"
  if [ -n "$key" ]; then
    file="$cache_dir/$key.mp3"
  else
    file="$cache_dir/last.mp3"
  fi

  if [ ! -s "$file" ]; then
    eleven_synthesize "$text" "$file" || return 1
    _eleven_prune_cache "$cache_dir"
  fi

  afplay -v "$WELCOME_VOLUME" "$file" 2>/dev/null
}
