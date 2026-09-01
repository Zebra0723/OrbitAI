#!/bin/bash
# Short-term memory: who and what you were just talking about.
#
# Without this every command is an island, and you end up saying "message
# Priya saying I'm running late" twice instead of "and tell Priya the
# same". The memory is deliberately shallow and short-lived - a couple of
# minutes - because a follow-up that lands on stale context is worse than
# no context at all.

_context_file() { printf '%s/context' "$WELCOME_STATE_DIR"; }

# Expired context is the same as no context.
_context_fresh() {
  local file
  file="$(_context_file)"
  [ -f "$file" ] || return 1
  local age now stamp
  stamp="$(awk -F'\t' '$1 == "at" { print $2 }' "$file" 2>/dev/null)"
  [ -z "$stamp" ] && return 1
  now="$(date '+%s')"
  age=$((now - stamp))
  [ "$age" -le "$ORBIT_CONTEXT_TTL_SECONDS" ]
}

context_get() {
  _context_fresh || return 1
  local value
  value="$(awk -F'\t' -v key="$1" '$1 == key { print $2 }' "$(_context_file)" 2>/dev/null)"
  [ -z "$value" ] && return 1
  printf '%s' "$value"
}

# context_remember key value [key value ...]
context_remember() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  {
    printf 'at\t%s\n' "$(date '+%s')"
    while [ $# -ge 2 ]; do
      [ -n "$2" ] && printf '%s\t%s\n' "$1" "$2"
      shift 2
    done
  } > "$(_context_file)"
}

context_forget() { rm -f "$(_context_file)"; }

# Rewrites a follow-up into a full command, using what was just said.
# Anything that isn't a follow-up passes through untouched, so this can sit
# in front of the parser without changing ordinary commands.
context_expand() {
  local text="$1" lower who body

  # Only spend the lookups on something that looks like a follow-up.
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    "and "*|"also "*|"actually "*|"same "*|"do that "*|"do it "*|"again"*|\
    *" the same"*|*"same thing"*|"make that "*|"change that to "*|\
    "tell her "*|"tell him "*|"tell them "*|"message her "*|"message him "*|"message them "*|\
    "call her"*|"call him"*|"call them"*|"reply "*) ;;
    *) printf '%s' "$text"; return 0 ;;
  esac

  who="$(context_get who)" || who=""
  body="$(context_get body)" || body=""

  # "and tell Priya the same"  ->  message Priya saying <last body>
  if [ -n "$body" ]; then
    case "$lower" in
      *" the same"*|*"same thing"*|"same for "*)
        local target
        target="$(printf '%s' "$text" | sed -E '
          s/^(and|also)[[:space:]]+//I
          s/^(tell|message|text|send (a )?(message|text) to)[[:space:]]+//I
          s/[[:space:]]+(the same( thing)?|same thing|same)[[:space:]]*$//I
          s/^same for[[:space:]]+//I')"
        target="$(printf '%s' "$target" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
        [ -z "$target" ] && target="$who"
        if [ -n "$target" ]; then
          printf 'message %s saying %s' "$target" "$body"
          return 0
        fi ;;
    esac
  fi

  # "actually make that seven"  ->  same person, new message
  if [ -n "$who" ]; then
    case "$lower" in
      "actually "*|"make that "*|"change that to "*)
        local new_body
        new_body="$(printf '%s' "$text" | sed -E 's/^(actually,?[[:space:]]+)?(make that|change that to|say)[[:space:]]+//I')"
        new_body="$(printf '%s' "$new_body" | sed -E 's/^actually,?[[:space:]]+//I')"
        if [ -n "$new_body" ] && [ "$new_body" != "$text" ]; then
          printf 'message %s saying %s' "$who" "$new_body"
          return 0
        fi ;;
      # "tell her I'm on my way" - a pronoun standing in for the last person
      "tell her "*|"tell him "*|"tell them "*|"message her "*|"message him "*|"message them "*)
        local said
        said="$(printf '%s' "$text" | sed -E 's/^(tell|message)[[:space:]]+(her|him|them)[[:space:]]+//I')"
        said="$(printf '%s' "$said" | sed -E 's/^(that|saying)[[:space:]]+//I')"
        [ -n "$said" ] && { printf 'message %s saying %s' "$who" "$said"; return 0; } ;;
      "call her"*|"call him"*|"call them"*)
        printf 'call %s' "$who"; return 0 ;;
    esac
  fi

  # "and open Safari" - a conjunction, not a reference to anything
  case "$lower" in
    "and "*|"also "*)
      printf '%s' "$(printf '%s' "$text" | sed -E 's/^(and|also)[[:space:]]+//I')"
      return 0 ;;
  esac

  printf '%s' "$text"
}
