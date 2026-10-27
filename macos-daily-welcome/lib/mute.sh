#!/bin/bash
# Muting Orbit for a while, or until someone says otherwise.
#
# The rule itself - no sound at all while muted - is enforced in common.sh
# (orbit_muted), where every function that can make a noise checks it. This
# file only turns "for two hours" or "until 7:30" into the file that rule
# reads, and back into words.

# orbit_mute_until "<how long>" -> "never" or the epoch second it ends.
#
#   ""  forever  indefinitely  "until I unmute you"   -> never
#   45m  2h  1d  1h30m  90 (minutes)                  -> that long from now
#   "for two hours"  "half an hour"  "3 days"         -> spoken durations
#   "until 7:30"  "until 7pm"  "till 19:00"           -> the next time it's that time
orbit_mute_until() {
  local text now secs h m ampm
  text="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/ /g; s/^(for|for the next) //')"
  now="$(date +%s)"

  case "$text" in
    ''|forever|indefinitely|"for good"|always|"until further notice"|\
    "until i unmute"*|"till i unmute"*|"until i say"*|"till i say"*|"until i tell"*|"till i tell"*)
      printf 'never'; return 0 ;;
  esac

  # A clock time: "until 7:30", "till 7pm", "until 19:00", "until 7 30 pm".
  case "$text" in
    until\ *|till\ *|til\ *)
      local clock="${text#* }"
      clock="$(printf '%s' "$clock" | sed -E 's/\.//g; s/ ?(am|pm)$/ \1/; s/^([0-9]{1,2}) ([0-9]{2})/\1:\2/')"
      ampm=""
      case "$clock" in *" am") ampm=am; clock="${clock% am}" ;; *" pm") ampm=pm; clock="${clock% pm}" ;; esac
      case "$clock" in
        [0-9]|[0-9][0-9]) h="$clock"; m=0 ;;
        [0-9]:[0-9][0-9]|[0-9][0-9]:[0-9][0-9]) h="${clock%%:*}"; m="${clock#*:}" ;;
        *) return 1 ;;
      esac
      h=$((10#$h)); m=$((10#$m))
      [ "$h" -gt 23 ] || [ "$m" -gt 59 ] && return 1
      if [ "$ampm" = pm ] && [ "$h" -lt 12 ]; then h=$((h + 12)); fi
      if [ "$ampm" = am ] && [ "$h" -eq 12 ]; then h=0; fi
      local nh nm ns into target
      nh="$(date +%H)"; nm="$(date +%M)"; ns="$(date +%S)"
      into=$((10#$nh * 3600 + 10#$nm * 60 + 10#$ns))
      target=$((h * 3600 + m * 60))
      secs=$((target - into))
      [ "$secs" -le 0 ] && secs=$((secs + 86400))
      printf '%s' "$((now + secs))"
      return 0 ;;
  esac

  # Compact forms: 45m, 2h, 1d, 1h30m, 90 (a bare number means minutes).
  if printf '%s' "$text" | grep -Eq '^([0-9]+[dhms] ?)+$'; then
    secs=0
    local part
    for part in $(printf '%s' "$text" | sed -E 's/([dhms])/\1 /g'); do
      case "$part" in
        *d) secs=$((secs + ${part%d} * 86400)) ;;
        *h) secs=$((secs + ${part%h} * 3600)) ;;
        *m) secs=$((secs + ${part%m} * 60)) ;;
        *s) secs=$((secs + ${part%s})) ;;
      esac
    done
    [ "$secs" -gt 0 ] || return 1
    printf '%s' "$((now + secs))"
    return 0
  fi
  if printf '%s' "$text" | grep -Eq '^[0-9]+$'; then
    [ "$text" -gt 0 ] || return 1
    printf '%s' "$((now + text * 60))"
    return 0
  fi

  # Days, which the timer parser has no reason to know about.
  case "$text" in
    "a day"|"one day"|"1 day") printf '%s' "$((now + 86400))"; return 0 ;;
    *" days"|*" day")
      local n="${text% day*}"
      n="$(_number_from_words "$n" 2>/dev/null || printf '%s' "$n")"
      case "$n" in ''|*[!0-9]*) return 1 ;; esac
      printf '%s' "$((now + n * 86400))"; return 0 ;;
  esac

  # Everything else the way a timer is said: "two hours", "half an hour".
  secs="$(_duration_seconds "$text" 2>/dev/null)"
  case "$secs" in ''|*[!0-9]*|0) return 1 ;; esac
  printf '%s' "$((now + secs))"
}

# orbit_mute "<how long>" - mutes, stops anything already talking, and
# prints when it ends ("never" or an epoch second). Fails on a duration it
# can't read, and then nothing changes.
orbit_mute() {
  local until
  until="$(orbit_mute_until "${1:-}")" || return 1
  mkdir -p "$(dirname "$(orbit_mute_file)")" 2>/dev/null
  printf '%s\n' "$until" > "$(orbit_mute_file)"
  hush
  printf '%s' "$until"
}

orbit_unmute() {
  rm -f "$(orbit_mute_file)"
}

# "until 4:30 PM" / "until tomorrow at 7:30 AM" / "until you unmute me"
orbit_mute_words() {
  local until="${1:-}" clock day
  if [ "$until" = never ]; then
    printf 'until you unmute me'
    return 0
  fi
  clock="$(_epoch_format "$until" '+%-I:%M %p')"
  day="$(_epoch_format "$until" '+%Y-%m-%d')"
  if [ "$day" = "$(date +%Y-%m-%d)" ]; then
    printf 'until %s' "$clock"
  elif [ "$day" = "$(_epoch_format "$(( $(date +%s) + 86400 ))" '+%Y-%m-%d')" ]; then
    printf 'until tomorrow at %s' "$clock"
  else
    printf 'until %s at %s' "$(_epoch_format "$until" '+%A')" "$clock"
  fi
}

# BSD date (macOS) and GNU date (the tests, on Linux) spell this differently.
_epoch_format() {
  date -r "$1" "$2" 2>/dev/null || date -d "@$1" "$2" 2>/dev/null
}

# "two" -> 2, for "two days". Digits pass straight through.
_number_from_words() {
  case "$1" in
    *[!a-z\ -]*) printf '%s' "$1" ;;
    *) _duration_seconds "$1 seconds" ;;
  esac
}
