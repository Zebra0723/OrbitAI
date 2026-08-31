#!/bin/bash
# Small helpers shared by the rest of daily-welcome. Written for the
# /bin/bash 3.2 that ships with macOS - no associative arrays, no mapfile.

welcome_log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# run_with_timeout SECONDS CMD... - macOS has no coreutils `timeout`.
# Returns 124 if the command had to be killed.
run_with_timeout() {
  local secs="$1"; shift
  local out rc pid waited
  out="$(mktemp -t daily-welcome)" || return 1

  "$@" >"$out" 2>/dev/null &
  pid=$!

  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      cat "$out"
      rm -f "$out"
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done

  wait "$pid"
  rc=$?
  cat "$out"
  rm -f "$out"
  return "$rc"
}

# True while the login session is locked (the key is only present when
# the screen is actually locked).
screen_is_locked() {
  ioreg -n Root -d1 -a 2>/dev/null | grep -q 'CGSSessionScreenIsLocked'
}

# Trim leading/trailing whitespace from stdin.
trim_lines() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Keep the first N non-empty lines, and report how many were dropped.
# Usage: limit_items MAX  (reads stdin, writes stdout)
limit_items() {
  local max="$1" count=0 total=0 line
  local kept=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    total=$((total + 1))
    if [ "$count" -lt "$max" ]; then
      kept="${kept}${line}"$'\n'
      count=$((count + 1))
    fi
  done
  printf '%s' "$kept"
  if [ "$total" -gt "$max" ]; then
    printf '  ...and %d more\n' "$((total - max))"
  fi
}

# Escape a string for embedding in an AppleScript double-quoted literal.
applescript_quote() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

# _plural COUNT SINGULAR PLURAL
_plural() { [ "$1" -eq 1 ] && printf '%s' "$2" || printf '%s' "$3"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }
