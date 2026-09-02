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
  ORBIT_SPEAKER_STORE="$ORBIT_SPEAKER_STORE" \
  ORBIT_SPEAKER_THRESHOLD="$ORBIT_SPEAKER_THRESHOLD" \
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
