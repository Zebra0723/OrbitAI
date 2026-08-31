#!/bin/bash
# The catch-all: anything the catalog in lib/system.sh doesn't cover gets
# written by Claude Code as a one-line command.
#
# Two rules make this safe enough to leave on. Nothing runs without being
# read back to you first - you hear the plain-English summary and say yes -
# and a short denylist refuses whole categories outright, so a
# misunderstanding can't reach for sudo or the disk utility no matter how
# the sentence was phrased.

# Categories Orbit will not run, whatever it was asked.
_freeform_refused() {
  local cmd
  cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$cmd" in
    *sudo*|*"rm -rf"*|*"rm -fr"*|*"rm -f /"*|*diskutil*|*mkfs*|*fdisk*|*"dd if="*|*"dd of="*|\
    */dev/disk*|*"chmod -r"*|*"chown -r"*|*"security dump-keychain"*|*"security find-generic"*|\
    *"defaults delete"*|*launchctl*|*"killall -9"*|*"pkill -9"*|*shutdown\ -*|*halt*|\
    *"| sh"*|*"|sh"*|*"| bash"*|*"|bash"*|*"curl "*|*"wget "*|*"nc "*|*"ssh "*|*"scp "*|\
    *"base64 -d"*|*"> /etc"*|*"> /system"*|*"history -c"*|*"crontab"*)
      return 0 ;;
  esac
  # A one-liner is the contract; anything multi-line is out of scope.
  case "$cmd" in
    *$'\n'*) return 0 ;;
  esac
  return 1
}

# freeform_plan "<transcript>" -> summary <TAB> command
freeform_plan() {
  local text="$1" out summary command

  [ "$ORBIT_FREEFORM" = "1" ] || return 1
  have_cmd claude || return 1

  out="$(run_with_timeout "$ORBIT_NLU_TIMEOUT" claude -p "$(cat <<PROMPT
You control a Mac through a voice assistant. Turn the request below into ONE
shell command that a macOS terminal can run, preferring \`osascript -e\` for
anything an app or the system exposes to AppleScript.

Answer in exactly two lines, nothing else, no code fences:
SUMMARY: <what it does, plain English, present tense, at most twelve words>
COMMAND: <the single-line command>

If the request is unclear, destructive, or can't be done in one line, answer
exactly: NONE

Request: $text
PROMPT
)" 2>/dev/null)" || return 1

  case "$out" in *NONE*) return 1 ;; esac

  summary="$(printf '%s\n' "$out" | sed -nE 's/^[[:space:]]*SUMMARY:[[:space:]]*//p' | head -1)"
  command="$(printf '%s\n' "$out" | sed -nE 's/^[[:space:]]*COMMAND:[[:space:]]*//p' | head -1)"

  [ -z "$summary" ] && return 1
  [ -z "$command" ] && return 1
  _freeform_refused "$command" && {
    welcome_log "freeform: refused '$command'"
    return 1
  }

  printf '%s\t%s\n' "$summary" "$command"
}
