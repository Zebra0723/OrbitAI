#!/bin/bash
# Spoken emoji, in the text that gets sent.
#
# You can't say an emoji, so you describe it: "happy birthday with a party
# emoji". The words are the instruction, not the message - what should
# arrive is "Happy birthday" and a cake.
#
# Applied only to text that gets written down: messages, notes, reminders,
# mail. Never to what Orbit says back, since an emoji read aloud is noise.

emoji_expand() {
  local text="$1"
  [ -z "$text" ] && return 0
  [ "$ORBIT_EMOJI" = "1" ] || { printf '%s' "$text"; return 0; }

  # Nothing to do unless the word is actually in there.
  case "$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')" in
    *emoji*) ;;
    *) printf '%s' "$text"; return 0 ;;
  esac

  have_cmd python3 || { printf '%s' "$text"; return 0; }

  local key out
  key="$(openai_api_key 2>/dev/null)" || key=""
  out="$(OPENAI_API_KEY="$key" WELCOME_STATE_DIR="$WELCOME_STATE_DIR" \
    run_with_timeout 12 python3 "$ROOT/lib/emoji.py" "$text")"

  # A failure here should cost the emoji, never the message.
  if [ -z "$out" ]; then printf '%s' "$text"; else printf '%s' "$out"; fi
}
