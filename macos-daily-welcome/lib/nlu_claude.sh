#!/bin/bash
# One Claude call per turn, instead of three.
#
# Understanding a sentence used to cost three separate `claude -p`
# invocations in sequence: classify it, then write a shell command for it,
# then - when both came back empty - actually answer it. Each one boots
# Claude Code afresh, which is about four seconds before it has read the
# prompt, so "I got a new MacBook" took thirteen seconds to earn
# "Congratulations. Air or Pro?".
#
# Two of those three were always going to be thrown away. This asks the
# one question that covers all three jobs and returns whichever answer
# fits, in the same tab-separated shape openai_intent uses, so everything
# downstream is unchanged.

claude_available() { claude_bin >/dev/null 2>&1; }

_claude_turn_prompt() {
  local text="$1" phrases="$2" facts="$3" history="$4"
  printf '%s' "You are Orbit, a voice assistant on $WELCOME_NAME's Mac. Work out what
this spoken sentence wants and answer on ONE line, with real tab
characters between fields, nothing else, no code fences, no explanation.

Forms:
message<TAB><person><TAB><what to say>
mail_send<TAB><person><TAB><what the email says>
mail_reply<TAB><reply text>
claude<TAB><repo name><TAB><task>
readback<TAB><one of: briefing messages mail calendar reminders claude>
command<TAB><what it does in at most twelve words><TAB><one-line shell command>
chat<TAB><your spoken answer><TAB><a fact worth remembering, or empty>

Rules:
- Prefer a real action when the sentence asks for one.
- Use \"command\" only for something the Mac exposes to AppleScript or a
  shell one-liner, and never for anything destructive.
- Anything else - a question, small talk, a greeting, something
  half-heard - is \"chat\", and you answer it there.
- \"chat\" answers are SPOKEN ALOUD: one sentence, two only if the second
  is a short question. No markup, no bullets, no emoji, no headings.
  React to what they said, then ask the one question that moves it
  forward. Never refuse; if you do not know, say so in a sentence.
"
  [ -n "$phrases" ] && printf 'Their own macro phrases: %s\n' "$phrases"
  [ -n "$facts" ] && printf 'What you know about them: %s\n' "$facts"
  [ -n "$history" ] && printf 'Recent conversation:\n%s\n' "$history"
  printf '\nThey said: %s\n' "$text"
}

# claude_intent "<transcript>" -> intent <TAB> arg1 <TAB> arg2
claude_intent() {
  local text="$1" claude_cmd out line phrases facts history

  [ "$ORBIT_NLU_FALLBACK" = "1" ] || return 1
  claude_cmd="$(claude_bin)" || return 1

  phrases="$(macros_list 2>/dev/null | cut -f1 | tr '\n' ',' | sed 's/,$//')"
  facts="$(memory_facts 2>/dev/null | cut -f2- | tr '\n' ';' | cut -c1-400)"
  history="$(chat_history 2>/dev/null | awk -F'\t' '{ printf "%s: %s\n", $1, $2 }' | tail -6)"

  out="$(run_with_timeout "$ORBIT_NLU_TIMEOUT" "$claude_cmd" -p \
    "$(_claude_turn_prompt "$text" "$phrases" "$facts" "$history")" 2>/dev/null)" || return 1

  # The model occasionally writes the word TAB instead of pressing it.
  line="$(printf '%s' "$out" | sed -E 's/<TAB>/\t/g' \
    | grep -E '^(message|mail_send|mail_reply|claude|readback|command|chat)' | head -1)"
  [ -n "$line" ] || return 1

  case "$(printf '%s' "$line" | cut -f1)" in
    command)
      # Same shape the freeform planner produced, so it is confirmed out
      # loud before anything runs - a model-written shell command is not
      # something to run on trust.
      printf 'system\tfreeform\t%s\t%s\n' \
        "$(printf '%s' "$line" | cut -f3)" "$(printf '%s' "$line" | cut -f2)"
      ;;
    *) printf '%s\n' "$line" ;;
  esac
}
