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

  prompt="You are Orbit, a voice assistant made by DailyOS. If asked who or\nwhat you are, that is the answer - never name any model or company behind\nyou. Answer the question below out loud.

Rules:
- At most $ORBIT_ASK_SENTENCES sentences. One is usually better.
- Plain spoken English. No markup, no bullet points, no headings, no emoji.
- Numbers, dates and times written as words, the way you would say them.
- If you do not know, say so in one sentence rather than guessing.
- No preamble. Start with the answer.
- Opinions, recommendations and small talk are all fair game. Answer the
  way a person would, not the way a reference book would.
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

# chat_claude "<what they said>" -> a spoken reply
#
# ask_claude answers questions; this one talks. The difference matters:
# a factual prompt met with "wanna chat?" produces either a refusal or a
# definition of chatting, and both are worse than "sure, what's up".
chat_claude() {
  local text="$1" prompt reply history claude_cmd facts prompt_facts=""
  claude_cmd="$(claude_bin)" || return 1

  history="$(chat_history 2>/dev/null | awk -F'\t' '{ printf "%s: %s\n", $1, $2 }')"
  facts="$(memory_facts 2>/dev/null | cut -f2-)"
  [ -n "$facts" ] && prompt_facts="

What you already know about them:
$facts"

  prompt="$(orbit_identity)

You are on ${WELCOME_NAME}'s Mac. You are
speaking out loud.

- One sentence. Two only if the second is a short question. Spoken aloud,
  so no markup, no bullet points, no emoji, no headings.
- Short is not flat. React to what they said, then ask the one question
  that moves it forward. \"I got a new MacBook\" deserves \"Congratulations,
  Air or Pro?\" - not a definition, and never a menu of options.
- Small talk is welcome. If they want to chat, chat.
- Never refuse to answer. If you do not know, say so in a sentence."

  prompt="$prompt${prompt_facts}"

  [ -n "$history" ] && prompt="$prompt

What was said just before:
$history"

  prompt="$prompt

They said: $text"

  reply="$(run_with_timeout "$ORBIT_ASK_TIMEOUT" "$claude_cmd" -p "$prompt" 2>/dev/null)" || return 1
  reply="$(_spoken_only "$reply")"
  [ -z "$reply" ] && return 1
  chat_remember "$text" "$reply" 2>/dev/null
  printf '%s' "$reply"
}

# --------------------------------------------------------------- the web
#
# Claude Code can search and can read a page; it just has to be told it is
# allowed to. Both are slower than an ordinary answer because they are
# doing real work, so they are only used when the sentence asks for it.

ask_web() {
  local query="$1" claude_cmd answer
  claude_cmd="$(claude_bin)" || return 1

  local prompt
  prompt="Search the web and answer in ONE spoken sentence, two only if the
second is a short question. No markup, no bullets, no citations, no URLs -
this is read aloud. If the answer is a number or a name, lead with it.

Question: $query"

  answer="$(run_with_timeout "$ORBIT_WEB_TIMEOUT" "$claude_cmd" -p "$prompt" \
    --allowedTools WebSearch 2>/dev/null)" || return 1
  answer="$(printf '%s' "$answer" | sed -E '/^Sources:/,$d' | grep . | head -3)"
  [ -n "$answer" ] || return 1
  printf '%s' "$answer"
}

ask_page() {
  local url="$1" question="${2:-What is this page about?}" claude_cmd answer
  claude_cmd="$(claude_bin)" || return 1

  local prompt
  prompt="Read $url and answer in at most two spoken sentences. No markup,
no bullets, no URLs - this is read aloud.

Question: $question"

  answer="$(run_with_timeout "$ORBIT_WEB_TIMEOUT" "$claude_cmd" -p "$prompt" \
    --allowedTools WebFetch 2>/dev/null)" || return 1
  answer="$(printf '%s' "$answer" | sed -E '/^Sources:/,$d' | grep . | head -3)"
  [ -n "$answer" ] || return 1
  printf '%s' "$answer"
}
