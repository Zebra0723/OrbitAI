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
