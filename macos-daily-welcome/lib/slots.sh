#!/bin/bash
# The half-finished request.
#
# "Send mama a message" is a complete sentence and an incomplete
# instruction. Orbit used to answer the only way it could - by guessing,
# or by giving up - because a turn was a closed box: whatever you said had
# to contain everything, or nothing happened.
#
# So a turn can now end owing you a question. The missing piece is written
# down here, the question is asked, and the next thing you say fills it in.
# One slot at a time, short-lived, and abandoned the moment you say
# something that is clearly a fresh instruction.

_slot_file() { printf '%s/pending-slot' "$WELCOME_STATE_DIR"; }

# slot_save INTENT SLOT [ARG1] [ARG2] - what we are waiting to be told.
slot_save() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  {
    printf 'AT\t%s\n' "$(date '+%s')"
    printf 'INTENT\t%s\n' "$1"
    printf 'SLOT\t%s\n' "$2"
    printf 'ARG1\t%s\n' "${3:-}"
    printf 'ARG2\t%s\n' "${4:-}"
  } > "$(_slot_file)"
}

slot_clear() { rm -f "$(_slot_file)" 2>/dev/null; }

# Prints INTENT<TAB>SLOT<TAB>ARG1<TAB>ARG2 while a question is still live.
# An unanswered question goes stale: coming back an hour later and saying
# "hello" must not finish a message you had forgotten about.
slot_pending() {
  local file at now
  file="$(_slot_file)"
  [ -f "$file" ] || return 1

  at="$(awk -F'\t' '$1 == "AT" { print $2; exit }' "$file")"
  now="$(date '+%s')"
  if [ -z "$at" ] || [ $((now - at)) -gt "$ORBIT_SLOT_TTL_SECONDS" ]; then
    slot_clear
    return 1
  fi

  printf '%s\t%s\t%s\t%s\n' \
    "$(awk -F'\t' '$1 == "INTENT" { print $2; exit }' "$file")" \
    "$(awk -F'\t' '$1 == "SLOT"   { print $2; exit }' "$file")" \
    "$(awk -F'\t' '$1 == "ARG1"   { print $2; exit }' "$file")" \
    "$(awk -F'\t' '$1 == "ARG2"   { print $2; exit }' "$file")"
}

# Some answers are not answers. "Never mind" has to win over slot filling,
# or there is no way out of a question except to answer it.
slot_is_abandon() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+$//')" in
    "never mind"|"nevermind"|"forget it"|"cancel"|"cancel that"|"stop"|\
    "no"|"nothing"|"don't"|"dont"|"drop it"|"leave it"|"forget about it")
      return 0 ;;
  esac
  return 1
}

# And some are plainly a new instruction rather than the answer to the
# question just asked. Only a short list, because after "what should I say
# to mama?" almost anything IS the answer - including sentences that look
# like commands. "Tell her I'm running late" is a message, not a command.
slot_is_new_command() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    "what time"*|"what is the time"*|"brief me"*|"lock my mac"*|\
    "shut down"*|"restart"*|"go to sleep"*|"take a screenshot"*|\
    "volume up"*|"volume down"*|"stop listening"*|"stop talking"*|\
    "hey orbit"*)
      return 0 ;;
  esac
  return 1
}
