#!/bin/bash
# Small helpers shared by the rest of daily-welcome. Written for the
# /bin/bash 3.2 that ships with macOS - no associative arrays, no mapfile.

welcome_log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2
}

# Where the last failure's stderr is kept. It goes in a file rather than a
# variable because callers wrap this in $( ), and a subshell can't hand a
# variable back to its parent - "it didn't work" is not a diagnosis, and
# AppleScript is usually quite specific about why it refused.
run_error_file() {
  printf '%s/last-error' "${WELCOME_STATE_DIR:-${TMPDIR:-/tmp}}"
}

last_error() {
  tr '\n' ' ' < "$(run_error_file)" 2>/dev/null | cut -c1-300
}

# run_with_timeout SECONDS CMD... - macOS has no coreutils `timeout`.
# Returns 124 if the command had to be killed.

run_with_timeout() {
  local secs="$1"; shift
  local out err rc pid waited
  # The template needs the X's spelled out: BSD mktemp is happy with a bare
  # prefix, GNU is not, and this script also gets run under test on Linux.
  out="$(mktemp -t daily-welcome.XXXXXX)" || return 1
  err="$(mktemp -t daily-welcome-err.XXXXXX)" || { rm -f "$out"; return 1; }
  mkdir -p "$(dirname "$(run_error_file)")" 2>/dev/null

  "$@" >"$out" 2>"$err" &
  pid=$!

  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      cat "$out"
      cp "$err" "$(run_error_file)" 2>/dev/null
      rm -f "$out" "$err"
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done

  wait "$pid"
  rc=$?
  cat "$out"
  cp "$err" "$(run_error_file)" 2>/dev/null
  rm -f "$out" "$err"
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

# Escapes a string for use as a JSON string value.
json_escape() {
  printf '%s' "$1" \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' \
    | awk 'BEGIN { ORS = "" } NR > 1 { print "\\n" } { print }'
}

# "9:30:00 AM" -> "9:30 AM" in the first field. AppleScript's time string
# carries seconds that nobody wants to read. Interval expressions like
# {2} aren't portable across awks, so this spells the digits out.
tidy_time_field() {
  awk -F'\t' 'BEGIN { OFS = "\t" }
    {
      if (match($1, /^[0-9][0-9]?:[0-9][0-9]:[0-9][0-9]/)) {
        head = substr($1, 1, RLENGTH)
        rest = substr($1, RLENGTH + 1)
        sub(/:[0-9][0-9]$/, "", head)
        $1 = head rest
      }
      print
    }'
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# The menu bar app inherits launchd's PATH, not a login shell's, so tools
# installed in a home directory are invisible to it - which made every
# Claude-backed feature fail silently when spoken and work perfectly when
# typed. Widening PATH here fixes all of them at once.
orbit_widen_path() {
  local extra dir
  extra="$HOME/.local/bin:$HOME/.claude/local:$HOME/bin:$HOME/.npm-global/bin"
  extra="$extra:$HOME/.bun/bin:$HOME/.volta/bin:/opt/homebrew/bin:/usr/local/bin"
  for dir in $(printf '%s' "$extra" | tr ':' ' '); do
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) [ -d "$dir" ] && PATH="$PATH:$dir" ;;
    esac
  done
  export PATH
}

# Where Claude Code actually is. `command -v` first, then the places it
# installs itself.
claude_bin() {
  local candidate
  candidate="$(command -v claude 2>/dev/null)"
  if [ -n "$candidate" ]; then printf '%s' "$candidate"; return 0; fi
  for candidate in "$HOME/.claude/local/claude" "$HOME/.local/bin/claude" \
                   "$HOME/.bun/bin/claude" "/opt/homebrew/bin/claude" \
                   "/usr/local/bin/claude"; do
    [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  return 1
}

have_claude() { claude_bin >/dev/null 2>&1; }
