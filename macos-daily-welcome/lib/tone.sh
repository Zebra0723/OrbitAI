#!/bin/bash
# Matching your tone.
#
# Reading emotion from audio would need prosody analysis this doesn't have,
# so the signal used is the one that's actually available: the words. A
# clipped three-word order at eleven at night is not the same request as
# "hey, could you grab my calendar when you get a sec", and answering both
# the same way is what makes an assistant feel like a vending machine.
#
# Tone changes two things: how the reply is worded, and how the voice
# delivers it. Nothing else - it never changes what the command does.

# tone_of "<transcript>" -> urgent | frustrated | warm | quiet | neutral
tone_of() {
  local text lower words
  text="$1"
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  words="$(printf '%s' "$lower" | wc -w | tr -d ' ')"

  case "$lower" in
    *"not working"*|*"still not"*|*"still won"*|*"why won"*|*"why isn"*|\
    *"doesn t work"*|*"broken"*|*"come on"*|*"ugh"*|*"seriously"*|\
    *"for the third time"*|*"i said"*|*"i already"*)
      printf 'frustrated'; return 0 ;;
  esac

  case "$lower" in
    *"right now"*|*"quickly"*|*"quick"*|*"hurry"*|*"asap"*|*"immediately"*|\
    *"now now"*|*"urgent"*|*"emergency"*)
      printf 'urgent'; return 0 ;;
  esac

  case "$lower" in
    *"please"*|*"could you"*|*"would you mind"*|*"when you get a"*|*"if you can"*|\
    *"thanks"*|*"thank you"*|*"no rush"*|*"whenever"*)
      printf 'warm'; return 0 ;;
  esac

  # Late at night people speak quietly and want to be answered quietly.
  local hour; hour="$(date '+%-H')"
  if [ "$hour" -ge "$ORBIT_QUIET_FROM_HOUR" ] || [ "$hour" -lt "$ORBIT_QUIET_UNTIL_HOUR" ]; then
    printf 'quiet'; return 0
  fi

  # A bare two-word order is business, not conversation.
  if [ "$words" -le 3 ]; then printf 'urgent'; return 0; fi

  printf 'neutral'
}

# How the voice should deliver a given tone. Echoes:
#   stability <TAB> style <TAB> speed <TAB> volume
tone_voice_settings() {
  case "$1" in
    urgent)     printf '0.45\t0.0\t1.10\t%s' "$WELCOME_VOLUME" ;;
    frustrated) printf '0.65\t0.0\t1.00\t%s' "$WELCOME_VOLUME" ;;
    warm)       printf '0.40\t0.25\t0.98\t%s' "$WELCOME_VOLUME" ;;
    quiet)      printf '0.60\t0.0\t0.95\t%s' "$(awk -v v="$WELCOME_VOLUME" 'BEGIN { printf "%.2f", v * 0.65 }')" ;;
    *)          printf '%s\t%s\t%s\t%s' "$WELCOME_ELEVEN_STABILITY" "$WELCOME_ELEVEN_STYLE" \
                       "$WELCOME_ELEVEN_SPEED" "$WELCOME_VOLUME" ;;
  esac
}

# Applies a tone to the current shell's voice settings. Called before
# anything is spoken, so a reply is delivered the way it was asked for.
tone_apply() {
  local tone="$1" settings
  [ "$ORBIT_MATCH_TONE" = "1" ] || return 0
  settings="$(tone_voice_settings "$tone")"
  WELCOME_ELEVEN_STABILITY="$(printf '%s' "$settings" | cut -f1)"
  WELCOME_ELEVEN_STYLE="$(printf '%s' "$settings" | cut -f2)"
  WELCOME_ELEVEN_SPEED="$(printf '%s' "$settings" | cut -f3)"
  WELCOME_VOLUME="$(printf '%s' "$settings" | cut -f4)"
}

# Trims a reply to match the tone: an urgent question doesn't want a
# sentence of preamble, and a frustrated one doesn't want cheerfulness.
tone_shape() {
  local tone="$1" text="$2"
  case "$tone" in
    urgent)
      # Drop a leading pleasantry: "Sure thing, muted." -> "Muted."
      printf '%s' "$text" | sed -E 's/^(sure( thing)?|of course|okay|alright|no problem|happy to)[,.!]?[[:space:]]*//I' ;;
    frustrated)
      printf '%s' "$text" | sed -E 's/^(sure( thing)?|of course|great|perfect)[,.!]?[[:space:]]*//I' ;;
    *)
      printf '%s' "$text" ;;
  esac
}

# The instruction handed to Claude when it writes an answer, so a spoken
# reply matches the question it was asked.
tone_prompt_hint() {
  case "$1" in
    urgent)     printf 'The asker is in a hurry. One short sentence. No preamble, no pleasantries.' ;;
    frustrated) printf 'The asker is frustrated and something has already failed. Be direct and practical, no apologies beyond a few words, no cheerfulness.' ;;
    warm)       printf 'The asker is relaxed and friendly. A warm, conversational sentence or two is right.' ;;
    quiet)      printf 'It is late at night. Keep it short and calm.' ;;
    *)          printf 'Plain and even. Two sentences at most.' ;;
  esac
}
