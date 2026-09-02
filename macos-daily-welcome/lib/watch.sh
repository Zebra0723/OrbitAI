#!/bin/bash
# Speaking first.
#
# Everything else in Orbit waits to be asked. This is the part that
# volunteers: a meeting about to start, a job Claude finished, mail from
# someone who matters. That makes it the part most likely to become
# irritating, so it is deliberately hard to make noisy - quiet hours, a
# rate limit, nothing while the screen is locked or the room is muted, and
# each thing announced exactly once.

_watch_seen_file() { printf '%s/announced' "$WELCOME_STATE_DIR"; }
_watch_last_file() { printf '%s/last-announcement' "$WELCOME_STATE_DIR"; }

# Has this exact thing been announced before?
_watch_seen() {
  [ -f "$(_watch_seen_file)" ] || return 1
  grep -Fxq "$1" "$(_watch_seen_file)"
}

_watch_remember() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  printf '%s\n' "$1" >> "$(_watch_seen_file)"
  # Keep the file from growing forever; yesterday's ids can't recur.
  tail -n 200 "$(_watch_seen_file)" > "$(_watch_seen_file).tmp" 2>/dev/null &&
    mv "$(_watch_seen_file).tmp" "$(_watch_seen_file)"
}

# Every reason not to speak, in one place.
watch_may_speak() {
  [ "$ORBIT_PROACTIVE" = "1" ] || return 1

  local hour; hour="$(date '+%-H')"
  if [ "$hour" -ge "$ORBIT_QUIET_FROM_HOUR" ] || [ "$hour" -lt "$ORBIT_QUIET_UNTIL_HOUR" ]; then
    return 1
  fi

  # Not to an empty room, and not over a locked screen.
  screen_is_locked && return 1

  # And never over a call.
  on_a_call && return 1

  # Not while you've muted it for the day.
  if [ -f "$WELCOME_STATE_DIR/muted-on" ] &&
     [ "$(cat "$WELCOME_STATE_DIR/muted-on")" = "$(date '+%Y-%m-%d')" ]; then
    return 1
  fi

  # And not more often than the rate limit allows.
  if [ -f "$(_watch_last_file)" ]; then
    local last now
    last="$(cat "$(_watch_last_file)" 2>/dev/null || echo 0)"
    now="$(date '+%s')"
    [ $((now - last)) -lt "$ORBIT_PROACTIVE_GAP_SECONDS" ] && return 1
  fi
  return 0
}

_watch_spoke() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  date '+%s' > "$(_watch_last_file)"
}

# --- the things worth interrupting for -------------------------------------

# A meeting about to start. The one interruption people reliably want.
_watch_calendar() {
  local records line when title minutes now_min event_min key
  records="$(src_calendar)" || return 0
  now_min=$(( $(date '+%-H') * 60 + $(date '+%-M') ))

  while IFS="$(printf '\t')" read -r when title _; do
    [ "$when" = "#note" ] && continue
    [ -z "$title" ] || [ -z "$when" ] && continue

    event_min="$(printf '%s' "$when" | awk '
      { h = 0; m = 0
        if (match($0, /^[0-9]+/)) h = substr($0, RSTART, RLENGTH) + 0
        if (match($0, /:[0-9][0-9]/)) m = substr($0, RSTART + 1, 2) + 0
        if (tolower($0) ~ /pm/ && h < 12) h += 12
        if (tolower($0) ~ /am/ && h == 12) h = 0
        print h * 60 + m }')"
    [ -z "$event_min" ] && continue

    minutes=$((event_min - now_min))
    if [ "$minutes" -ge 0 ] && [ "$minutes" -le "$ORBIT_MEETING_WARNING_MINUTES" ]; then
      key="event:$(date '+%Y-%m-%d'):$when:$title"
      _watch_seen "$key" && continue
      _watch_remember "$key"
      if [ "$minutes" -le 1 ]; then
        printf '%s is starting now.' "$(speech_clean "$title")"
      else
        printf '%s in %s minutes.' "$(speech_clean "$title")" "$(num_word "$minutes")"
      fi
      return 0
    fi
  done <<EOT
$records
EOT
  return 1
}

# Something Claude finished while you were doing something else.
_watch_claude() {
  local records line key
  records="$(src_claude)" || return 0
  [ -z "$records" ] && return 1

  while IFS="$(printf '\t')" read -r when title _; do
    [ -z "$title" ] && continue
    key="claude:$title"
    _watch_seen "$key" && continue
    _watch_remember "$key"
    printf '%s' "$(speech_clean "$title")"
    return 0
  done <<EOT
$records
EOT
  return 1
}

# Mail from someone on the short list of people worth interrupting for.
_watch_vip_mail() {
  [ -n "$ORBIT_VIPS" ] || return 1
  local records vip key who
  records="$(src_mail)" || return 0

  while IFS="$(printf '\t')" read -r when title _; do
    [ "$when" = "#note" ] && continue
    [ -z "$title" ] && continue
    who="$(printf '%s' "$title" | cut -d: -f1)"

    local IFS_SAVE="$IFS"
    IFS='|'
    for vip in $ORBIT_VIPS; do
      IFS="$IFS_SAVE"
      [ -z "$vip" ] && continue
      case "$(printf '%s' "$who" | tr '[:upper:]' '[:lower:]')" in
        *"$(printf '%s' "$vip" | tr '[:upper:]' '[:lower:]')"*)
          key="mail:$title"
          _watch_seen "$key" && continue 2
          _watch_remember "$key"
          printf 'Mail from %s.' "$(speech_clean "$title")"
          return 0 ;;
      esac
    done
    IFS="$IFS_SAVE"
  done <<EOT
$records
EOT
  return 1
}

# One announcement, or nothing. Called on a timer by the menu bar app.
watch_once() {
  watch_may_speak || return 1

  local line=""
  line="$(_watch_claude)" || line=""
  [ -z "$line" ] && { line="$(_watch_calendar)" || line=""; }
  [ -z "$line" ] && { line="$(_watch_vip_mail)" || line=""; }

  [ -z "$line" ] && return 1
  _watch_spoke
  printf '%s' "$line"
}
