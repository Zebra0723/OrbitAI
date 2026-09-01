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
  local said="$1" replied="$2"
  memory_init
  {
    printf 'user\t%s\n' "$(printf '%s' "$said" | tr '\n' ' ')"
    printf 'assistant\t%s\n' "$(printf '%s' "$replied" | tr '\n' ' ')"
  } >> "$(_transcript)"

  local lines
  lines="$(wc -l < "$(_transcript)" 2>/dev/null | tr -d ' ')"
  if [ "${lines:-0}" -gt "$ORBIT_MEMORY_MAX_LINES" ]; then
    tail -n "$((ORBIT_MEMORY_MAX_LINES / 2))" "$(_transcript)" > "$(_transcript).tmp" &&
      mv "$(_transcript).tmp" "$(_transcript)"
  fi
}

# The last few exchanges, oldest first, as "role<TAB>text".
memory_recent() {
  [ -f "$(_transcript)" ] || return 0
  tail -n "$((ORBIT_CHAT_TURNS * 2))" "$(_transcript)"
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

chat_history() { memory_recent; }

chat_remember() { memory_log_turn "$1" "$2"; }
