#!/usr/bin/env python3
"""Turn a spoken sentence into an Orbit intent, using OpenAI.

Prints one tab-separated line - intent, arg1, arg2 - in exactly the format
the shell rules produce, so it drops into the same pipeline. Prints
"none" and exits 0 when it can't tell; failure of any other kind exits
non-zero so the caller can fall back to the rules.

The whole point is the messy middle: "go to Claude and say this", "shoot
mama a text saying I'm late", "kill the volume". Rules can be written for
any one of those, but not for all of them.
"""

import json
import os
import sys
import urllib.error
import urllib.request

MODEL = os.environ.get("ORBIT_OPENAI_MODEL", "gpt-4o-mini")

# The endpoint is a setting, not a constant. Groq, Google's Gemini and a
# local Ollama all speak this same chat-completions shape, and two of
# those are free - which matters more than brand loyalty when the whole
# point is a fast answer that costs nothing.
BASE = os.environ.get("ORBIT_OPENAI_BASE", "https://api.openai.com/v1").rstrip("/")
ENDPOINT = BASE + "/chat/completions"
# A second inside the shell's own timeout, so a slow reply is reported as
# a slow reply rather than as a killed process.
TIMEOUT = max(3.0, float(os.environ.get("ORBIT_OPENAI_TIMEOUT", "7")) - 1)

SYSTEM = """You convert spoken commands for a Mac voice assistant into one intent.

Answer with JSON only: {"intent": ..., "arg1": ..., "arg2": ..., "reply": ...}

"reply" is only used for intent "chat". It is SPOKEN ALOUD: one sentence.
Two only if the second is a short question. No markup, no bullet points,
no emoji, no headings, no preamble, numbers written as words.

Short is not the same as flat. React to what they actually said, then ask
the one question that moves it forward. "I got a new MacBook" deserves
"Congratulations. Air or Pro?" - not a definition, not a list of things
you could help with, and not silence.

Never offer a menu of options. Ask one question instead.

"remember" is optional: one short line, only when they have said something
durable about themselves worth knowing next week - what they own, who
people are to them, what they are working on, what they prefer. Not
pleasantries, not questions, not things that will be stale tomorrow.

Intents and their arguments:
  message     arg1 = person, arg2 = what to say
  call        arg1 = person, arg2 = call_phone | call_video | call_audio
  claude      arg1 = repo name (or "" for the default), arg2 = the task
  mail_reply  arg1 = the reply text (only for replying to everything awaiting a reply)
  system      arg1 = action, arg2 = argument (see the action list)
  readback    arg1 = briefing | messages | mail | calendar | reminders | claude
  social      arg1 = thanks | hello | howareyou | goodnight | nevermind | praise | present
  ask         arg1 = the question, asked as the person asked it
  screen      arg1 = the question about what is on screen
  macro       arg1 = the phrase, only if it matches one of the user's macros
  chat        not a command - put your spoken answer in "reply"

system actions:
  volume_set(0-100) volume_up volume_down mute unmute brightness_up brightness_down
  dark_mode_on dark_mode_off playpause next_track prev_track play_spotify(query)
  open_app(name) quit_app(name) switch_app(name) open_url(url) web_search(query)
  app_menu("App|Menu item") new_tab close_tab reload_page go_back save
  screenshot lock sleep_display sleep_mac restart shut_down
  wifi_on wifi_off bluetooth_on bluetooth_off empty_trash battery time_now
  new_note(text) add_reminder(text) timer(minutes) type_text(text)
  copy_text(text) read_clipboard find_file(name) end_call
  stop_talking      they want the voice to stop, not the Mac muted
  stop_listening    they want the microphone closed until they ask again
  start_listening   they want it listening again
  minimize fullscreen close_window hide_others

Rules:
- A question about the world is "ask", not a command to run.
- "what time is it", "how much battery", "what's on my calendar" are system or
  readback, not ask - they are answered locally.
- Anything about the screen in front of them is "screen".
- Thanks, goodbye and greetings are "social".
- Anything that is not a command - a question, a remark, small talk,
  something half-heard - is "chat", and you answer it in "reply". Never
  refuse to respond.
- When a command is clear, act on it: do not chat about it instead."""


def answer(intent, arg1="", arg2=""):
    clean = lambda v: str(v or "").replace("\t", " ").replace("\n", " ").strip()
    print(f"{intent}\t{clean(arg1)}\t{clean(arg2)}")
    sys.exit(0)


CHAT_SYSTEM = """You are Orbit, a voice assistant living on a Mac, made by
DailyOS. If asked who or what you are, that is the answer - never name any
model or company behind you. You are
speaking out loud, so:

- One or two sentences. Never more than three.
- No markup, no lists, no headings, no emoji, no stage directions.
- Numbers, dates and times written the way you would say them.
- Plain, warm and direct. No preamble, no "as an AI", no offering to help
  in the abstract - just answer the person.
- If they ask you to do something on the Mac that you were not able to
  carry out, say what you could not do in one sentence."""


def chat():
    """Answers conversationally rather than classifying."""
    text = " ".join(sys.argv[2:]).strip()
    if not text:
        sys.exit(2)

    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        sys.exit(2)

    messages = [{"role": "system", "content": CHAT_SYSTEM}]
    # A few previous turns, so "and the other one?" means something.
    history = os.environ.get("ORBIT_CHAT_HISTORY", "")
    for line in history.splitlines():
        if "\t" in line:
            role, content = line.split("\t", 1)
            if role in ("user", "assistant") and content.strip():
                messages.append({"role": role, "content": content.strip()})
    messages.append({"role": "user", "content": text})

    body = json.dumps({
        "model": MODEL,
        "messages": messages,
        "temperature": 0.4,
        "max_tokens": 160,
    }).encode()

    request = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            payload = json.load(response)
    except Exception as error:  # noqa: BLE001
        print(f"openai: {error}", file=sys.stderr)
        sys.exit(3)

    try:
        reply = payload["choices"][0]["message"]["content"].strip()
    except (KeyError, IndexError):
        sys.exit(4)

    print(" ".join(reply.replace("*", "").replace("#", "").split()))
    sys.exit(0)


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "--chat":
        chat()
    text = " ".join(sys.argv[1:]).strip()
    if not text:
        answer("none")

    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key:
        sys.exit(2)

    macros = os.environ.get("ORBIT_MACRO_PHRASES", "").strip()
    user = text if not macros else f"{text}\n\nThe user's macro phrases: {macros}"

    system = SYSTEM
    facts = os.environ.get("ORBIT_MEMORY_FACTS", "").strip()
    if facts:
        system += "\n\nWhat you already know about them:\n" + facts

    messages = [{"role": "system", "content": system}]
    for line in os.environ.get("ORBIT_CHAT_HISTORY", "").splitlines():
        if "\t" in line:
            role, content = line.split("\t", 1)
            if role in ("user", "assistant") and content.strip():
                messages.append({"role": role, "content": content.strip()})
    messages.append({"role": "user", "content": user})

    body = json.dumps({
        "model": MODEL,
        "messages": messages,
        "response_format": {"type": "json_object"},
        "temperature": 0,
        "max_tokens": 200,
    }).encode()

    request = urllib.request.Request(
        ENDPOINT,
        data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )

    try:
        with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as error:
        # The reason matters to whoever is debugging this, and stderr is
        # already captured by the shell's timeout wrapper.
        print(f"openai: HTTP {error.code} {error.read()[:200]!r}", file=sys.stderr)
        sys.exit(3)
    except Exception as error:  # noqa: BLE001 - reported, not raised
        print(f"openai: {error}", file=sys.stderr)
        sys.exit(4)

    try:
        content = payload["choices"][0]["message"]["content"]
        parsed = json.loads(content)
    except (KeyError, IndexError, json.JSONDecodeError):
        answer("none")

    intent = str(parsed.get("intent", "chat")).strip().lower()
    allowed = {"message", "call", "claude", "mail_reply", "system",
               "readback", "social", "ask", "screen", "macro", "chat", "none"}
    if intent not in allowed:
        intent = "chat"

    # One request, not two. Classifying and then asking again for something
    # to say doubled the wait on every sentence that wasn't a command.
    if intent in ("chat", "none"):
        reply = str(parsed.get("reply") or parsed.get("arg1") or "").strip()
        if reply:
            # arg2 carries anything worth remembering, which the shell
            # appends to the facts file.
            answer("chat", reply, parsed.get("remember", ""))
        answer("none")

    answer(intent, parsed.get("arg1", ""), parsed.get("arg2", ""))


if __name__ == "__main__":
    main()
