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
  local text="$1" phrases="$2" facts="$3" history="$4" events="$5" recalled="$6"
  printf '%s\n\n' "$(orbit_identity)"
  printf '%s' "You are on $WELCOME_NAME's Mac. Work out what
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
- If they tell you to drop a subject - "forget that", "anyway", "new
  topic" - it is gone. Do not return to it, do not refer back to it, and
  do not summarise what it was.
- Answer what they JUST said. The recent conversation is there so you know
  who \"her\" or \"that\" refers to, not as a subject to return to. Once
  something is done, it is done: do not keep bringing up a message you
  sent, a call you placed or a topic that has moved on. Never open with a
  reference to an earlier turn.
- \"chat\" answers are SPOKEN ALOUD: one sentence, two only if the second
  is a short question. No markup, no bullets, no emoji, no headings.
  React to what they said, then ask the one question that moves it
  forward. Never refuse; if you do not know, say so in a sentence.
"
  [ -n "$phrases" ] && printf 'Their own macro phrases: %s\n' "$phrases"
  [ -n "$facts" ] && printf 'What you know about them: %s\n' "$facts"
  [ -n "$history" ] && printf 'Recent conversation:\n%s\n' "$history"
  # Only when they ask about the past. Handing the model a list of
  # everything it has done, on every turn, makes it bring those things up
  # unprompted - it keeps talking about the message it sent long after the
  # subject has moved on.
  [ -n "$events" ] && printf 'Things you have done for them lately, for reference only - do NOT
mention any of it unless they ask:\n%s\n' "$events"
  if [ -n "$recalled" ]; then
    printf 'They are asking about something that already happened. From the
record, most recent last:\n%s\n' "$recalled"
    printf 'Answer from that record. If it does not say, say you do not have it
rather than inventing something.\n'
  fi
  printf '\nThey said: %s\n' "$text"
}

# claude_intent "<transcript>" -> intent <TAB> arg1 <TAB> arg2
claude_intent() {
  local text="$1" claude_cmd out line phrases facts history events recalled

  [ "$ORBIT_NLU_FALLBACK" = "1" ] || return 1
  claude_cmd="$(claude_bin)" || return 1

  phrases="$(macros_list 2>/dev/null | cut -f1 | tr '\n' ',' | sed 's/,$//')"
  facts="$(memory_facts 2>/dev/null | cut -f2- | tr '\n' ';' | cut -c1-400)"
  history="$(chat_history 2>/dev/null | tail -6)"
  # Both of these are for looking BACKWARDS, and both only when asked.
  # Carrying them into every turn is what made it dwell on old topics.
  events=""
  recalled=""
  if memory_asks_about_past "$text"; then
    events="$(memory_events "$ORBIT_MEMORY_EVENTS" 2>/dev/null)"
    recalled="$(memory_search "$text" "$ORBIT_MEMORY_MATCHES" 2>/dev/null)"
  fi

  out="$(run_with_timeout "$ORBIT_NLU_TIMEOUT" "$claude_cmd" -p \
    "$(_claude_turn_prompt "$text" "$phrases" "$facts" "$history" "$events" "$recalled")" 2>/dev/null)" || return 1

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
