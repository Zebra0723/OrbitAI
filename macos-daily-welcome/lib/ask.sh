#!/bin/bash
# Answering questions.
#
# Without this, an assistant that can drive your Mac still can't tell you
# how long to boil an egg - anything unrecognised fell through to the
# command writer, which would try to solve a question with a shell script.
#
# Answers are written to be heard, not read: no markup, no lists, no
# preamble, and short enough that you don't reach for the mute.

# Strips anything that would sound wrong read aloud.
_spoken_only() {
  printf '%s' "$1" \
    | sed -E 's/^[[:space:]]*[-*][[:space:]]+//' \
    | tr -d '#*_' \
    | tr '\n' ' ' \
    | sed -E 's/[[:space:]]+/ /g; s/^ | $//g'
}

# ask_claude "<question>" -> a spoken-length answer on stdout
ask_claude() {
  local question="$1" prompt answer hint

  local claude_cmd
  claude_cmd="$(claude_bin)" || return 1
  hint="$(tone_prompt_hint "${ORBIT_TONE:-neutral}")"

  prompt="You are the voice of a Mac assistant. Answer the question below out loud.

Rules:
- At most $ORBIT_ASK_SENTENCES sentences. One is usually better.
- Plain spoken English. No markup, no bullet points, no headings, no emoji.
- Numbers, dates and times written as words, the way you would say them.
- If you do not know, say so in one sentence rather than guessing.
- No preamble. Start with the answer.
- $hint

Question: $question"

  answer="$(run_with_timeout "$ORBIT_ASK_TIMEOUT" "$claude_cmd" -p "$prompt" 2>/dev/null)" || return 1
  answer="$(_spoken_only "$answer")"
  [ -z "$answer" ] && return 1
  printf '%s' "$answer"
}

# What's on screen, described by Claude. The screenshot is taken, read and
# deleted; it goes nowhere except to Claude Code running on this Mac.
ask_about_screen() {
  local question="${1:-What is on this screen? If there is an error, explain it.}"
  local shot prompt answer

  local claude_cmd
  claude_cmd="$(claude_bin)" || return 1
  have_cmd screencapture || return 1

  shot="$(mktemp -t orbit-screen.XXXXXX)" || return 1
  rm -f "$shot"
  shot="$shot.png"

  if ! screencapture -x "$shot" 2>/dev/null; then
    rm -f "$shot"
    return 1
  fi

  prompt="Read the image at $shot and answer out loud, in at most three
sentences of plain spoken English. No markup, no lists, no preamble. If the
question is about an error, say what it means and the single most likely fix.

Question: $question"

  answer="$(run_with_timeout "$ORBIT_SCREEN_TIMEOUT" "$claude_cmd" -p "$prompt" 2>/dev/null)"
  rm -f "$shot"

  answer="$(_spoken_only "$answer")"
  [ -z "$answer" ] && return 1
  printf '%s' "$answer"
}
