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

# ---------------------------------------------------------- turning people away

# One line at random, never the same one twice running.
#
# The refusal used to be a single polite sentence, said identically every
# time, which is the most machine-like thing in the whole system: a
# person who has been told no twice says it differently the second time.
# The line still has to say what is actually happening - not recognised,
# or banned - because being teased and being confused are different
# experiences and only one of them is any fun.
_speaker_pick() {
  local last_file="$WELCOME_STATE_DIR/.last-refusal" last=0 n i
  n="$(grep -c . <<EOF
$1
EOF
)"
  [ "${n:-0}" -gt 0 ] || return 1
  [ -f "$last_file" ] && last="$(cat "$last_file" 2>/dev/null | tr -cd '0-9')"
  i=$(( (RANDOM % n) + 1 ))
  # Not the same joke twice. With one line there is no choice to make.
  if [ "$n" -gt 1 ] && [ "$i" = "${last:-0}" ]; then i=$(( (i % n) + 1 )); fi
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  printf '%s' "$i" > "$last_file" 2>/dev/null
  printf '%s\n' "$1" | grep . | sed -n "${i}p"
}

# A voice it does not know.
speaker_refusal_unknown() {
  # An explicit setting still wins - somebody who wants the polite
  # version, or their own line, sets ORBIT_SPEAKER_UNKNOWN.
  if [ -n "$ORBIT_SPEAKER_UNKNOWN" ]; then
    printf '%s' "$ORBIT_SPEAKER_UNKNOWN"; return 0
  fi
  _speaker_pick "$(cat <<'LINES'
I have no idea who you are, and I do not take requests from strangers. Get your voice verified with the DailyOS team.
Bold of you to assume I answer to unverified voices. The DailyOS team can fix that. They cannot fix the boldness.
Lovely voice. Not on my list. Verify it with the DailyOS team and we can be friends.
Unrecognised voice. Confidence: none whatsoever. Enrol with the DailyOS team and try that again.
I would love to help, but I have standards, and the first one is knowing who you are. Talk to the DailyOS team.
Nice try. I only listen to voices I have actually been introduced to. That is the DailyOS team's department.
You are not in the book, so this is where it ends. The DailyOS team can put you in it.
Absolutely not. You are unverified, which is a polite way of saying I have never heard of you.
That voice means nothing to me, and I mean that in the technical sense. Enrol with the DailyOS team.
Speak all you like, it is not registered. The DailyOS team hands out the credentials, not me.
LINES
)"
}

# A voice it knows perfectly well and has been told to refuse.
speaker_refusal_banned() {
  if [ -n "$ORBIT_SPEAKER_REFUSAL" ]; then
    printf '%s' "$ORBIT_SPEAKER_REFUSAL"; return 0
  fi
  _speaker_pick "$(cat <<'LINES'
Oh, it is you. You are banned. Nothing has changed since the last time you asked.
Still banned. Impressively persistent, though.
I know exactly who you are, and that is the problem. Banned.
Banned is banned. I do admire the optimism.
That would have been a yes if you were not banned. You are. So it is a no.
You are on the list. Not the good list. The other one.
Recognised, and refused. At least we both know where we stand.
LINES
)"
}
