#!/bin/bash
# What it remembers.
#
# Two kinds, because they age differently. The transcript is everything
# ever said, in order, and is only ever read from the end - it gives
# "what were we just talking about". Facts are the handful of durable
# things worth carrying into a conversation next week: that you have a new
# MacBook Air, that your mother is called Mama, that you are working on
# dailyos.
#
# Facts are written by the same request that answers you, so remembering
# costs nothing extra. They live in a plain file you can read and edit.

_memory_dir() { printf '%s/memory' "$WELCOME_STATE_DIR"; }
_transcript()  { printf '%s/transcript.log' "$(_memory_dir)"; }
_facts_file()  { printf '%s/facts.txt' "$(_memory_dir)"; }

memory_init() { mkdir -p "$(_memory_dir)" 2>/dev/null; }

# Every exchange, kept. Trimmed only when it gets genuinely large, from
# the front, so the recent past is never the thing that gets lost.
memory_log_turn() {
  local said="$1" replied="$2" when
  memory_init
  when="$(date '+%Y-%m-%d %H:%M')"
  {
    printf 'user\t%s\t%s\n' "$when" "$(printf '%s' "$said" | tr '\n' ' ')"
    printf 'assistant\t%s\t%s\n' "$when" "$(printf '%s' "$replied" | tr '\n' ' ')"
  } >> "$(_transcript)"

  local lines
  lines="$(wc -l < "$(_transcript)" 2>/dev/null | tr -d ' ')"
  if [ "${lines:-0}" -gt "$ORBIT_MEMORY_MAX_LINES" ]; then
    tail -n "$((ORBIT_MEMORY_MAX_LINES / 2))" "$(_transcript)" > "$(_transcript).tmp" &&
      mv "$(_transcript).tmp" "$(_transcript)"
  fi
}

# The last few exchanges, oldest first, as "role<TAB>text".
# "Forget that" has to actually forget it. The model is handed the last
# few turns for continuity, so telling it to drop a subject while still
# feeding it that subject achieves nothing - it needs a line in the sand.
memory_drop_subject() {
  memory_init
  printf 'reset\t%s\t--\n' "$(date '+%Y-%m-%d %H:%M')" >> "$(_transcript)"
}

memory_recent() {
  [ -f "$(_transcript)" ] || return 0
  # Everything since the last time they said to drop it, and no further
  # back. The full transcript is still on disk for "what did we say
  # about X" to search - this only bounds what rides along automatically.
  awk -F'\t' '$1 == "reset" { n = 0; delete keep; next }
              { keep[++n] = $0 }
              END { for (i = 1; i <= n; i++) print keep[i] }' "$(_transcript)" \
    | tail -n "$((ORBIT_CHAT_TURNS * 2))"
}

# One line per thing worth remembering.
memory_facts() {
  [ -f "$(_facts_file)" ] || return 0
  tail -n "$ORBIT_MEMORY_FACTS_MAX" "$(_facts_file)"
}

# Adds a fact, unless it is one already. A near-duplicate is worse than
# useless: it crowds out the facts that are actually different.
memory_add_fact() {
  local fact="$1" existing
  fact="$(printf '%s' "$fact" | tr '\n' ' ' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | cut -c1-160)"
  [ -z "$fact" ] && return 0
  memory_init

  if [ -f "$(_facts_file)" ] &&
     grep -Fqi -- "$fact" "$(_facts_file)" 2>/dev/null; then
    return 0
  fi
  printf '%s\t%s\n' "$(date '+%Y-%m-%d')" "$fact" >> "$(_facts_file)"
}

memory_forget() {
  local needle="$1"
  [ -f "$(_facts_file)" ] || return 0
  grep -vi -- "$needle" "$(_facts_file)" > "$(_facts_file).tmp" 2>/dev/null
  mv "$(_facts_file).tmp" "$(_facts_file)"
}

memory_clear() {
  rm -f "$(_transcript)" "$(_facts_file)"
}

# --- the old short-term names, now backed by the persistent store -------

# Old transcripts have two fields, new ones three. Read both rather than
# throwing away everything said before the change.
_memory_line_text() { awk -F'\t' '{ print $1 ": " (NF >= 3 ? $3 : $2) }'; }

chat_history() { memory_recent | _memory_line_text; }

# ------------------------------------------------------------- what it did
#
# The transcript records what was SAID. It never recorded what was DONE, so
# "who did I message earlier" had nothing to look at even though Orbit was
# the one who sent it.
_events_file() { printf '%s/events.log' "$(_memory_dir)"; }

# The past tense of an action, for the record. "add_reminder call the
# bank" is a log line; "Added a reminder: call the bank" is something a
# voice can read back.
memory_event_words() {
  local action="$1" arg="${2:-}"
  case "$action" in
    add_reminder) printf 'Added a reminder: %s' "$arg" ;;
    new_note)     printf 'Made a note: %s' "$arg" ;;
    timer)        printf 'Set a timer for %s minutes' "$arg" ;;
    open_app)     printf 'Opened %s' "$arg" ;;
    quit_app)     printf 'Quit %s' "$arg" ;;
    play_spotify) printf 'Played %s' "$arg" ;;
    type_text)    printf 'Typed: %s' "$arg" ;;
    freeform)     printf 'Ran a command: %s' "$arg" ;;
    empty_trash)  printf 'Emptied the trash' ;;
    restart)      printf 'Restarted the Mac' ;;
    shut_down)    printf 'Shut the Mac down' ;;
    sleep_mac)    printf 'Put the Mac to sleep' ;;
    *)            printf '%s%s' "$action" "${arg:+ $arg}" ;;
  esac
}

# memory_log_event KIND SUMMARY
memory_log_event() {
  [ -n "${2:-}" ] || return 0
  memory_init
  printf '%s\t%s\t%s\n' "$(date '+%Y-%m-%d %H:%M')" "$1" \
    "$(printf '%s' "$2" | tr '\n' ' ')" >> "$(_events_file)"

  local lines
  lines="$(wc -l < "$(_events_file)" 2>/dev/null | tr -d ' ')"
  if [ "${lines:-0}" -gt "$ORBIT_MEMORY_MAX_LINES" ]; then
    tail -n "$((ORBIT_MEMORY_MAX_LINES / 2))" "$(_events_file)" > "$(_events_file).tmp" &&
      mv "$(_events_file).tmp" "$(_events_file)"
  fi
}

# The last few things it actually did, newest last, in plain English.
memory_events() {
  [ -f "$(_events_file)" ] || return 0
  tail -n "${1:-12}" "$(_events_file)" \
    | awk -F'\t' '{ printf "%s  %s\n", $1, $3 }'
}

# memory_search "what they said" - the lines of history that look related.
#
# Deliberately crude: the content words of the question, matched against
# everything ever said or done. A model reading ten plausible lines beats
# clever retrieval that returns nothing.
memory_search() {
  local query="$1" limit="${2:-10}" words pattern
  [ -n "$query" ] || return 0

  words="$(printf '%s' "$query" | tr '[:upper:]' '[:lower:]' \
    | tr -cs "a-z0-9'" '\n' \
    | awk 'length($0) > 3' \
    | grep -Ev '^(what|when|where|which|that|this|there|were|was|did|does|done|have|has|had|about|with|from|then|than|they|them|你|the|and|you|your|yours|mine|remember|earlier|before|last|time|said|say|tell|told|again|ever|just|like|much|many|some|any|know|think)$' \
    | sort -u | head -6 | tr '\n' '|' | sed 's/|$//')"
  [ -n "$words" ] || return 0

  {
    [ -f "$(_transcript)" ] && grep -Ei "$words" "$(_transcript)" 2>/dev/null | _memory_line_text
    [ -f "$(_events_file)" ] && grep -Ei "$words" "$(_events_file)" 2>/dev/null \
      | awk -F'\t' '{ printf "%s: %s\n", $1, $3 }'
  } | tail -n "$limit"
}

# Is this sentence asking about the past at all? Only then is it worth
# searching - every question would otherwise drag history into its prompt.
memory_asks_about_past() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    *"did i "*|*"did we "*|*"did you "*|*remember*|*earlier*|*yesterday*|\
    *"last time"*|*"we talked"*|*"you said"*|*"i said"*|*"i told you"*|\
    *"this morning"*|*"last night"*|*"the other day"*|*"what was"*|\
    *"who was"*|*"when was"*|*"have i "*|*"had i "*|*again*)
      return 0 ;;
  esac
  return 1
}

chat_remember() { memory_log_turn "$1" "$2"; }
