#!/bin/bash
# Who is speaking, and whether they are allowed to ask.
#
# The menu bar app leaves the last few seconds of audio in the state
# directory; this reads it. Everything expensive lives in speaker.py -
# this is the part that knows where things are and what to do when the
# answer is "no idea", which is the common case and not an error.

_speaker_py() { printf '%s/lib/speaker.py' "$ROOT"; }

speaker_venv() { printf '%s/.config/daily-welcome/speaker-venv' "$HOME"; }

_speaker_python() {
  # Resemblyzer is a LIBRARY, not an application, so it does not belong to
  # pipx at all - pipx installs every dependency correctly and then
  # refuses at the last step because there is no command to put on your
  # PATH. It lives in its own virtual environment instead, and that
  # environment's interpreter is the only one that can import it.
  if [ -n "$ORBIT_SPEAKER_PYTHON" ] && [ -x "$ORBIT_SPEAKER_PYTHON" ]; then
    printf '%s' "$ORBIT_SPEAKER_PYTHON"; return 0
  fi
  local candidate
  for candidate in "$(speaker_venv)/bin/python" \
                   "$HOME/.local/share/pipx/venvs/resemblyzer/bin/python" \
                   "$HOME/.local/pipx/venvs/resemblyzer/bin/python"; do
    [ -x "$candidate" ] && { printf '%s' "$candidate"; return 0; }
  done
  command -v python3 2>/dev/null && return 0
  return 1
}

speaker_run() {
  local py
  py="$(_speaker_python)" || return 1
  # Every knob the recogniser reads has to be handed over here, or the
  # shell and the Python disagree about where the bar is and `orbit voice
  # test` reports one thing while the gate does another.
  ORBIT_SPEAKER_STORE="$ORBIT_SPEAKER_STORE" \
  ORBIT_SPEAKER_THRESHOLD="$ORBIT_SPEAKER_THRESHOLD" \
  ORBIT_SPEAKER_MARGIN="$ORBIT_SPEAKER_MARGIN" \
  ORBIT_SPEAKER_MIN_SECONDS="$ORBIT_SPEAKER_MIN_SECONDS" \
    "$py" "$(_speaker_py)" "$@"
}

speaker_installed() { speaker_run check >/dev/null 2>&1; }

speaker_enabled() {
  [ "$ORBIT_SPEAKER_ID" = "1" ] || return 1
  speaker_installed
}

speaker_utterance() { printf '%s/utterance.wav' "$WELCOME_STATE_DIR"; }

# Prints name <TAB> score <TAB> ok|banned, or nothing at all. "Nothing"
# is the ordinary answer for an unenrolled voice and must never be
# treated as a failure.
speaker_identify() {
  speaker_enabled || return 1
  local wav="${1:-$(speaker_utterance)}"
  [ -s "$wav" ] || return 1
  # Identification is not worth making anyone wait on.
  run_with_timeout "$ORBIT_SPEAKER_TIMEOUT" speaker_run identify "$wav" 2>/dev/null
}

speaker_name()   { speaker_identify "$@" | cut -f1; }
speaker_banned() { [ "$(speaker_identify "$@" | cut -f3)" = "banned" ]; }

# How many people have enrolled. Nought means the feature is on but
# nobody has taught it anything yet, and turning everyone away at that
# point would lock the first person out of enrolling.
speaker_enrolled_count() {
  speaker_run list 2>/dev/null | grep -c . || printf '0'
}

# Was there anything to identify? A missing or empty recording is not the
# same as an unrecognised voice, and must not be treated as one.
speaker_have_audio() { [ -s "$(speaker_utterance)" ]; }

# ------------------------------------------------------------------- the bypass
#
# One conversation's worth of "yes, I know, let them in".
#
# The situation it is for: somebody speaks, is not recognised, and is
# turned away - and the person whose Mac it is wants them let through
# anyway. They say "bypass <code>" and the next few minutes are open.
#
# A file with a timestamp rather than a flag, because the failure that
# matters is the one where it never turns itself off again.

_bypass_file() { printf '%s/bypass' "$WELCOME_STATE_DIR"; }

# bypass_grant GRANTER [SUBJECT] - open the door for ORBIT_BYPASS_MINUTES.
#
# SUBJECT is the voice being waved through: a name for somebody known and
# banned, an empty string for a voice nobody recognised, or "*" for
# everybody, which is what the terminal command means. Recording it keeps
# the door narrow - waving one person through is not the same as leaving
# the house open.
bypass_grant() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  printf '%s\t%s\t%s\n' "$(date '+%s')" "${1:-someone}" "${2-}" > "$(_bypass_file)"
}

bypass_end() { rm -f "$(_bypass_file)" 2>/dev/null; }

bypass_subject() {
  awk -F'\t' 'NR == 1 { print $3 }' "$(_bypass_file)" 2>/dev/null
}

# bypass_active [SPEAKER] - is this voice allowed through right now?
#
# Expiring is half the design: a door propped open and forgotten is not a
# door. Being about ONE voice is the other half.
bypass_active() {
  local file age subject
  file="$(_bypass_file)"
  [ -f "$file" ] || return 1
  age="$(_file_age_seconds "$file")" || { bypass_end; return 1; }
  if [ "${age:-0}" -gt $(( ORBIT_BYPASS_MINUTES * 60 )) ]; then
    bypass_end
    return 1
  fi

  subject="$(bypass_subject)"
  case "$subject" in
    '*') return 0 ;;                       # everybody, from the terminal
    '')  [ -z "${1-}" ] && return 0 ;;     # whoever it did not recognise
    *)   [ "$subject" = "${1-}" ] && return 0 ;;
  esac
  return 1
}

# How much longer it lasts, in whole minutes, for saying out loud.
bypass_minutes_left() {
  local age
  age="$(_file_age_seconds "$(_bypass_file)")" || { printf '0'; return; }
  printf '%s' "$(( (ORBIT_BYPASS_MINUTES * 60 - age + 59) / 60 ))"
}

# Was that the code? Spoken digits arrive as words as often as figures,
# and the recogniser puts spaces and commas through the middle of a long
# number, so both are reduced to bare digits before comparing.
_spoken_digits() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E '
    s/(^|[^a-z])zero([^a-z]|$)/\10\2/g; s/(^|[^a-z])oh([^a-z]|$)/\10\2/g
    s/(^|[^a-z])one([^a-z]|$)/\11\2/g;  s/(^|[^a-z])two([^a-z]|$)/\12\2/g
    s/(^|[^a-z])three([^a-z]|$)/\13\2/g; s/(^|[^a-z])four([^a-z]|$)/\14\2/g
    s/(^|[^a-z])five([^a-z]|$)/\15\2/g;  s/(^|[^a-z])six([^a-z]|$)/\16\2/g
    s/(^|[^a-z])seven([^a-z]|$)/\17\2/g; s/(^|[^a-z])eight([^a-z]|$)/\18\2/g
    s/(^|[^a-z])nine([^a-z]|$)/\19\2/g
  ' | tr -cd '0-9'
}

# bypass_code_said "<transcript>" - true when the code is in there.
bypass_code_said() {
  local said want
  want="$(_spoken_digits "$ORBIT_BYPASS_CODE")"
  [ -n "$want" ] || return 1
  said="$(_spoken_digits "$1")"
  case "$said" in
    *"$want"*) return 0 ;;
  esac
  return 1
}

# The few seconds after a refusal, when it is still listening.
#
# A refusal used to close the microphone, so letting somebody in meant
# saying the wake word again first. It stays open instead - and stays
# QUIET: repeating the insult at every sentence is a machine having a
# tantrum, and the person it is aimed at has already heard it.

_bypass_window_file() { printf '%s/bypass-window' "$WELCOME_STATE_DIR"; }

# bypass_window_start [WHO] - remembers who was just turned away, so a
# code said straight afterwards waves through THAT voice and not the next
# person to walk in.
bypass_window_start() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  printf '%s\t%s\n' "$(date '+%s')" "${1-}" > "$(_bypass_window_file)"
}

# Who the last refusal was aimed at: a name, or empty for a voice nobody
# recognised.
bypass_window_subject() {
  awk -F'\t' 'NR == 1 { print $2 }' "$(_bypass_window_file)" 2>/dev/null
}

bypass_window_end() { rm -f "$(_bypass_window_file)" 2>/dev/null; }

bypass_window_open() {
  local file age
  file="$(_bypass_window_file)"
  [ -f "$file" ] || return 1
  age="$(_file_age_seconds "$file")" || { bypass_window_end; return 1; }
  if [ "${age:-0}" -gt "$ORBIT_BYPASS_LISTEN_SECONDS" ]; then
    bypass_window_end
    return 1
  fi
  return 0
}

# ---------------------------------------------------------- turning people away

_refusals_file() { printf '%s/lib/refusals.txt' "$ROOT"; }

# One line at random from a named section of lib/refusals.txt.
_refusal_line() {
  awk -v want="$1" -v seed="$2" '
    /^#/ { section = substr($0, 3); next }
    /^[[:space:]]*$/ { next }
    section == want { lines[++n] = $0 }
    END {
      if (!n) exit 1
      srand(seed)
      print lines[int(rand() * n) + 1]
    }' "$(_refusals_file)" 2>/dev/null
}

# Three sentences, each picked separately.
#
# Not a list of finished refusals - a set of interchangeable ones. Every
# line in the file is a COMPLETE SENTENCE, so any opener joined to any
# reason joined to any redirect is grammatical, and thirty-five by
# thirty-four by twenty-four is twenty-eight thousand of them. Nobody is
# going to hear the same one twice.
#
# The reason is the slot that matters: every line in it says the voice is
# not enrolled, so however the sentence comes out, the person being
# refused is told what is actually wrong.
_refusal_compose() {
  local a b c seed
  # $RANDOM alone repeats within a second on some shells; the pid moves
  # even when the clock does not.
  seed="$(( ${RANDOM:-0} + $$ + $(date '+%s') ))"
  a="$(_refusal_line "$1" "$((seed + 1))")"
  b="$(_refusal_line "$2" "$((seed + 7919))")"
  c="$(_refusal_line "$3" "$((seed + 104729))")"
  [ -n "$b" ] || return 1
  printf '%s %s %s' "$a" "$b" "$c" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//'
}

# A voice it does not know.
speaker_refusal_unknown() {
  # An explicit setting still wins - somebody who wants the polite
  # version, or their own line, sets ORBIT_SPEAKER_UNKNOWN.
  if [ -n "$ORBIT_SPEAKER_UNKNOWN" ]; then
    printf '%s' "$ORBIT_SPEAKER_UNKNOWN"; return 0
  fi
  _refusal_compose unknown/open unknown/reason unknown/redirect ||
    printf 'I do not recognise that voice. Get verified with the DailyOS team.'
}

# A voice it knows perfectly well and has been told to refuse.
speaker_refusal_banned() {
  if [ -n "$ORBIT_SPEAKER_REFUSAL" ]; then
    printf '%s' "$ORBIT_SPEAKER_REFUSAL"; return 0
  fi
  _refusal_compose banned/open banned/reason banned/flourish ||
    printf 'I know exactly who that is, and you are banned.'
}

# How many different refusals there are, for anyone who wants to know.
speaker_refusal_count() {
  awk -v kind="$1" '
    /^#/ { section = substr($0, 3); next }
    /^[[:space:]]*$/ { next }
    index(section, kind "/") == 1 { n[section]++ }
    END {
      total = 1; any = 0
      for (s in n) { total *= n[s]; any = 1 }
      print any ? total : 0
    }' "$(_refusals_file)" 2>/dev/null
}
