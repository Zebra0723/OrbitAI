#!/bin/bash
# Handing work to Claude Code in one of your repos, and reporting back on
# it in the next briefing.
#
# Jobs run detached: you say "tell Claude to debug the dailyos repo", it
# starts, and the result is waiting for you the next time Orbit speaks.

_jobs_dir() { printf '%s/claude-jobs' "$WELCOME_STATE_DIR"; }

# One pass: does any directory under the roots match this exact key?
_repo_match() {
  local normalized="$1" root match
  [ -z "$normalized" ] && return 1

  for root in $ORBIT_REPO_ROOTS; do
    root="${root/#\~/$HOME}"
    [ -d "$root" ] || continue
    match="$(find "$root" -maxdepth "$ORBIT_REPO_DEPTH" \
      \( -name Library -o -name Applications -o -name node_modules -o -name '.*' \) -prune -o \
      -type d -print 2>/dev/null \
      | while IFS= read -r dir; do
          base="$(basename "$dir" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+//g')"
          if [ "$base" = "$normalized" ]; then printf '0\t%s\n' "$dir"
          elif case "$base" in *"$normalized"*) true ;; *) false ;; esac; then printf '1\t%s\n' "$dir"
          fi
        done | sort -k1,1n | head -1 | cut -f2-)"
    if [ -n "$match" ]; then printf '%s' "$match"; return 0; fi
  done
  return 1
}

# Finds a repo by loose name: "dailyos mvp" matches ~/projects/dailyos-mvp.
# Speech adds words that aren't in the folder name ("the dailyos mvp
# development chat"), so trailing words are dropped one at a time until
# something matches - longest match wins, which keeps "dailyos-mvp" from
# losing to "dailyos".
resolve_repo() {
  local words count i candidate normalized
  words="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9 ]+/ /g; s/[[:space:]]+/ /g; s/^ | $//g')"
  [ -z "$words" ] && return 1

  count="$(printf '%s' "$words" | awk '{ print NF }')"
  for (( i = count; i >= 1; i-- )); do
    candidate="$(printf '%s' "$words" | cut -d' ' -f1-"$i")"
    normalized="$(printf '%s' "$candidate" | tr -d ' ')"
    if _repo_match "$normalized"; then return 0; fi
  done
  return 1
}

# claude_dispatch REPO_DIR TASK -> prints the job id
claude_dispatch() {
  local dir="$1" task="$2"
  local jobs id meta log
  jobs="$(_jobs_dir)"
  mkdir -p "$jobs"
  id="$(date '+%Y%m%d-%H%M%S')-$(basename "$dir" | tr -cd '[:alnum:]-' | cut -c1-24)"
  meta="$jobs/$id.meta"
  log="$jobs/$id.log"

  {
    printf 'repo\t%s\n' "$dir"
    printf 'task\t%s\n' "$task"
    printf 'started\t%s\n' "$(date '+%Y-%m-%d %H:%M')"
  } > "$meta"

  # Detached: the briefing reports the outcome later, nobody waits here.
  (
    cd "$dir" 2>/dev/null || exit 1
    # shellcheck disable=SC2086
    "$(claude_bin)" -p "$task" $ORBIT_CLAUDE_FLAGS > "$log" 2>&1
    printf '%s' "$?" > "$jobs/$id.done"
  ) >/dev/null 2>&1 &

  printf '%s' "$id"
}

# Finished jobs that haven't been reported yet, as briefing records.
src_claude() {
  local jobs done_file id meta repo task status summary
  jobs="$(_jobs_dir)"
  [ -d "$jobs" ] || return 0

  for done_file in "$jobs"/*.done; do
    [ -e "$done_file" ] || continue
    id="$(basename "$done_file" .done)"
    meta="$jobs/$id.meta"
    repo="$(awk -F'\t' '$1 == "repo" { print $2 }' "$meta" 2>/dev/null)"
    task="$(awk -F'\t' '$1 == "task" { print $2 }' "$meta" 2>/dev/null)"
    status="$(cat "$done_file" 2>/dev/null)"

    if [ "$status" = "0" ]; then
      summary="$(_claude_summary "$jobs/$id.log")"
      printf 'done\tClaude finished "%s" in %s. %s\t\n' \
        "$task" "$(basename "$repo")" "$summary"
    else
      printf 'failed\tClaude stopped on "%s" in %s\t\n' "$task" "$(basename "$repo")"
    fi
  done
}

# Claude's own last words are the useful part; the rest is process.
_claude_summary() {
  local log="$1"
  [ -f "$log" ] || return 0
  tail -n 20 "$log" \
    | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g' \
    | awk 'NF { last = $0 } END { print last }' \
    | cut -c1-160
}

# Called once a briefing has read them out, so they aren't repeated.
claude_jobs_mark_reported() {
  local jobs archive
  jobs="$(_jobs_dir)"
  archive="$jobs/reported"
  [ -d "$jobs" ] || return 0
  mkdir -p "$archive"
  for f in "$jobs"/*.done; do
    [ -e "$f" ] || continue
    id="$(basename "$f" .done)"
    mv "$f" "$archive/$id.done" 2>/dev/null
    mv "$jobs/$id.meta" "$archive/$id.meta" 2>/dev/null
    mv "$jobs/$id.log" "$archive/$id.log" 2>/dev/null
  done
}
