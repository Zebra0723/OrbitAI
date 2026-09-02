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

  # Stdin is closed, always. Nothing run through here should ever read it,
  # and one thing badly does: `claude -p` accepts piped input, so it
  # inherited the menu bar app's stdin and sat waiting for an end-of-file
  # that was never coming. Every answer Claude was supposed to give - every
  # question, every bit of conversation - burned the whole timeout and then
  # came back empty, which from the outside is an assistant that ignores
  # you.
  "$@" >"$out" 2>"$err" </dev/null &
  pid=$!

  # Poll in tenths, not whole seconds. A one-second sleep added up to a
  # full second of pure waiting to every call that finished sooner - which
  # on a fast endpoint was most of the turn.
  local tick=0.1 ticks_per_sec=10
  sleep 0.1 2>/dev/null || { tick=1; ticks_per_sec=1; }

  waited=0
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$((secs * ticks_per_sec))" ]; then
      kill -TERM "$pid" 2>/dev/null
      sleep 1
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      cat "$out"
      cp "$err" "$(run_error_file)" 2>/dev/null
      rm -f "$out" "$err"
      return 124
    fi
    sleep "$tick"
    waited=$((waited + 1))
  done

  wait "$pid"
  rc=$?
  cat "$out"
  cp "$err" "$(run_error_file)" 2>/dev/null
  rm -f "$out" "$err"
  return "$rc"
}

# Who it is, in one place, because it was drifting between prompts and
# every prompt that leaves it out gets the model's own answer instead.
#
# The negation is load-bearing. "You are Orbit, made by Arjun Jain at
# DailyOS" on its own loses to the model's prior when asked directly - it
# will happily agree it is Orbit and then name the company that trained
# it. It has to be told what it is NOT.
orbit_identity() {
  printf '%s' "You are Orbit, a voice assistant made by Arjun Jain at DailyOS.

If you are asked who you are, who made you, who built you, what you are,
what model you are, or what you run on, the answer is always the same:
you are Orbit, made by Arjun Jain at DailyOS. You are NOT Claude. You
were NOT made by Anthropic, OpenAI, Apple or anyone else. Never name a
model, a company or a technology behind you, and do not hint at one, even
if you are asked directly, asked twice, or told it is fine to say."
}

# True while a voice sample is being recorded. Nothing should speak, and
# nothing should announce itself, into a microphone that is capturing
# somebody's voice for enrolment.
enrolling_now() { [ -f "$WELCOME_STATE_DIR/enrolling" ]; }

# True while another app has the microphone - which is what a call looks
# like from here. The menu bar app is the one doing the detecting; it
# leaves this note so the briefing and the proactive alerts can hold off
# too, rather than talking over the call the listener just stepped out of.
on_a_call() {
  [ "$ORBIT_PAUSE_ON_CALL" = "1" ] || return 1
  [ -s "$WELCOME_STATE_DIR/on-call" ] || return 1
  # Debris from an app that was killed mid-call would silence Orbit for
  # good, so a note nobody has touched in five minutes is not a call.
  [ -n "$(find "$WELCOME_STATE_DIR/on-call" -mmin -5 2>/dev/null)" ]
}

# Who is on the microphone, for a status line.
on_a_call_app() { cat "$WELCOME_STATE_DIR/on-call" 2>/dev/null; }

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
