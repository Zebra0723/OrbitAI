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
# True while a voice sample is being recorded - but only for as long as
# that could plausibly still be happening. `orbit voice enroll` removes
# the flag when it is done and traps the usual interruptions, and a
# terminal closed or a process killed outright still leaves it. While it
# is there Orbit says nothing at all, so a stale one is an assistant that
# has gone silent for no reason anybody can see. Enrolment takes
# forty-five seconds; three minutes is well past any doubt.
enrolling_now() {
  local flag="$WELCOME_STATE_DIR/enrolling"
  [ -f "$flag" ] || return 1
  local age
  age="$(_file_age_seconds "$flag")"
  if [ "${age:-0}" -gt 180 ]; then
    rm -f "$flag" 2>/dev/null
    return 1
  fi
  return 0
}

# Seconds since a file was last written.
#
# stat's flags collide: -f is "format" on macOS and "filesystem" on GNU,
# so `stat -f %m` on Linux prints a block-size report and SUCCEEDS - the
# `||` fallback never fires and the caller gets a paragraph where it
# wanted a number. The answer is checked for being a number instead of
# the command being checked for failing.
_file_age_seconds() {
  local mtime now
  mtime="$(stat -f %m "$1" 2>/dev/null)"
  case "$mtime" in
    ''|*[!0-9]*) mtime="$(stat -c %Y "$1" 2>/dev/null)" ;;
  esac
  case "$mtime" in
    ''|*[!0-9]*) return 1 ;;
  esac
  now="$(date '+%s')"
  printf '%s' "$(( now - mtime ))"
}

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

# Sorts records by the clock time in their first field.
#
# Sorting those strings as strings puts "10:00 AM" before "9:00 AM" and
# "1:00 PM" before either, so the day was read out in an order that was
# neither chronological nor obviously wrong - just quietly shuffled. This
# reads the hour and minute properly, twelve- or twenty-four-hour, and
# leaves anything it cannot read at the end where it belongs.
sort_by_time_field() {
  awk -F'\t' '
    function minutes(t,   s, parts, n, h, m, pm, am) {
      s = toupper(t)
      pm = (index(s, "PM") > 0)
      am = (index(s, "AM") > 0)
      gsub(/[^0-9:]/, "", s)
      n = split(s, parts, ":")
      if (n < 2) return 99999
      h = parts[1] + 0; m = parts[2] + 0
      if (pm && h < 12) h += 12
      if (am && h == 12) h = 0
      if (h > 23 || m > 59) return 99999
      return h * 60 + m
    }
    { printf "%05d\t%s\n", minutes($1), $0 }' \
  | sort -t"$(printf '\t')" -k1,1n -s \
  | cut -f2-
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
  extra="$extra:$HOME/Library/pnpm:$HOME/.claude/bin"
  # nvm and fnm put the node version in the path, so the directory has to
  # be found rather than named. Newest first.
  for dir in $(ls -td "$HOME"/.nvm/versions/node/*/bin \
                      "$HOME"/.local/share/fnm/node-versions/*/installation/bin \
                      2>/dev/null | head -3); do
    extra="$extra:$dir"
  done
  for dir in $(printf '%s' "$extra" | tr ':' ' '); do
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) [ -d "$dir" ] && PATH="$PATH:$dir" ;;
    esac
  done
  export PATH
}

# Where Claude Code actually is.
#
# The menu bar app inherits launchd's PATH, not the one your shell builds
# at login, so "it works when I type it and not when I say it" is the
# usual shape of this. A fixed list of directories is not enough either:
# under nvm the binary lives at
# ~/.nvm/versions/node/v22.11.0/bin/claude, with the version in the
# middle, and fnm, pnpm and asdf all do something similar. Those have to
# be searched for rather than guessed.
#
# The answer is remembered, because globbing a few directory trees on
# every spoken sentence is not free.
_claude_cache() { printf '%s/claude-path' "$WELCOME_STATE_DIR"; }

claude_bin() {
  local candidate cached

  # Set by hand, or written by `daily-welcome --find-claude`.
  if [ -n "${ORBIT_CLAUDE_BIN:-}" ] && [ -x "$ORBIT_CLAUDE_BIN" ]; then
    printf '%s' "$ORBIT_CLAUDE_BIN"; return 0
  fi

  cached="$(cat "$(_claude_cache)" 2>/dev/null)"
  if [ -n "$cached" ] && [ -x "$cached" ]; then printf '%s' "$cached"; return 0; fi

  candidate="$(command -v claude 2>/dev/null)"
  if [ -n "$candidate" ]; then _claude_remember "$candidate"; return 0; fi

  for candidate in "$HOME/.claude/local/claude" "$HOME/.local/bin/claude" \
                   "$HOME/.bun/bin/claude" "$HOME/.volta/bin/claude" \
                   "$HOME/.npm-global/bin/claude" "$HOME/bin/claude" \
                   "/opt/homebrew/bin/claude" "/usr/local/bin/claude"; do
    [ -x "$candidate" ] && { _claude_remember "$candidate"; return 0; }
  done

  # The version-numbered ones. Newest first, since a stale node version
  # left behind by an upgrade often still has an older copy in it.
  for candidate in $(ls -td "$HOME"/.nvm/versions/node/*/bin/claude \
                            "$HOME"/.local/share/fnm/node-versions/*/installation/bin/claude \
                            "$HOME"/Library/pnpm/claude \
                            "$HOME"/.asdf/installs/nodejs/*/bin/claude \
                            "$HOME"/.local/state/fnm_multishells/*/bin/claude \
                            2>/dev/null); do
    [ -x "$candidate" ] && { _claude_remember "$candidate"; return 0; }
  done

  # Whatever npm itself thinks its global bin is - the one place that is
  # right by definition, and slow enough to be the last thing tried.
  if command -v npm >/dev/null 2>&1; then
    candidate="$(npm prefix -g 2>/dev/null)/bin/claude"
    [ -x "$candidate" ] && { _claude_remember "$candidate"; return 0; }
  fi

  return 1
}

_claude_remember() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  printf '%s' "$1" > "$(_claude_cache)" 2>/dev/null
  printf '%s' "$1"
}

# Forget it, for when Claude Code moves or is reinstalled.
claude_forget() { rm -f "$(_claude_cache)" 2>/dev/null; }

have_claude() { claude_bin >/dev/null 2>&1; }
