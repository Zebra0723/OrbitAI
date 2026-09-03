#!/bin/bash
# Choosing how to speak, without dying in the attempt.
#
# tts_backend in auto mode walks a chain: the paid clones first, then the
# free local neural voice, then the built-in one. Every link in that
# chain reads configuration, and under `set -u` a variable nobody
# declared does not read as empty - it ends the shell. WELCOME_PIPER_BIN
# was undeclared, so on a Mac (where afplay exists and the chain gets
# that far) working out how to speak killed the run, silently, with the
# reply half built.
#
# The stubs below stand in for the Mac commands the chain looks for, so
# the same walk happens here.

test_sandbox
load_orbit

stub_dir="$WELCOME_STATE_DIR/bin"
mkdir -p "$stub_dir"
for cmd in afplay say osascript; do
  printf '#!/bin/sh\nexit 0\n' > "$stub_dir/$cmd"
  chmod +x "$stub_dir/$cmd"
done

# Each backend is asked in a shell of its own, with `set -u` on and the
# Mac's commands in place. A crash shows up as no output at all.
walk() {
  ( set -u
    export PATH="$stub_dir:$PATH"
    printf 'START '
    tts_backend
    printf ' END' ) 2>/dev/null
}

# OpenAI is no longer in the auto chain - it is still reachable as
# WELCOME_TTS=openai, but nothing falls into it and gets billed for it.
out="$(WELCOME_TTS=auto walk)"
lacks "auto never lands on openai" "openai" "$out"

# The auto branch must not consult it at all - reaching openai by
# accident is the thing being prevented, not merely preferring not to.
auto_branch="$(declare -f tts_backend | sed -n '/auto|\*)/,/;;/p')"
lacks "and auto does not even ask it" "openai_tts_available" "$auto_branch"

# But a provider chosen on purpose still has to be able to speak. A
# setting written when a key worked used to keep naming that provider
# long after the key stopped, and be reported as the voice in use while
# something else did the talking.
out="$(WELCOME_TTS=openai walk)"
lacks "a chosen provider that cannot speak is not used" "END openai" "$out"
contains "something that can speak is used instead" "END" "$out"
out="$(WELCOME_TTS=elevenlabs walk)"
lacks "same for elevenlabs" "END elevenlabs" "$out"
out="$(WELCOME_TTS=piper walk)"
lacks "and for piper" "END piper" "$out"

# The system voice is the default, because it is the only way to reach a
# Siri voice: `say -v` cannot name one, so the route is to name none.
ok "the system voice is the default" "system" "$WELCOME_VOICE"
ok "which resolves to naming no voice at all" "" "$(resolve_voice)"
ok "and a named voice still wins" "Ava (Premium)" \
   "$(WELCOME_VOICE="Ava (Premium)" resolve_voice)"

for setting in auto say elevenlabs openai piper; do
  out="$(WELCOME_TTS="$setting" walk)"
  contains "WELCOME_TTS=$setting survives being asked" "END" "$out"
  lacks "WELCOME_TTS=$setting names a backend" "START END" "$out"
done

# Each predicate on the chain, on its own, so a failure says which link.
for probe in eleven_available openai_tts_available piper_available; do
  out="$( ( set -u; export PATH="$stub_dir:$PATH"
            $probe >/dev/null 2>&1; printf 'survived' ) 2>/dev/null )"
  ok "$probe answers instead of dying" "survived" "$out"
done

# And the pacing, which asks the same question again for its markup.
out="$( ( set -u; export PATH="$stub_dir:$PATH"
          speech_pace "Morning, Arjun." ) 2>/dev/null )"
contains "pacing still knows what to do" "Arjun" "$out"

# ------------------------------------------------------- which brain answers
#
# Anything speaking the OpenAI chat-completions shape works, and two of
# them are free. The trap is that the KEY CHECK ignored the configured
# endpoint, so a Groq key was tested against api.openai.com and reported
# as broken - a good way to be told a working key does not work.

probe_line="$(sed -n '/probe="\$(OPENAI_API_KEY/,/openai_intent.py/p' "$TEST_ROOT/bin/daily-welcome")"
contains "the key is checked against the configured endpoint" "ORBIT_OPENAI_BASE" "$probe_line"
contains "with the configured model"                          "ORBIT_OPENAI_MODEL" "$probe_line"

# Switching provider should not mean hand-editing a config file.
cfg="$WELCOME_STATE_DIR/brain.sh"
switch() { ( export WELCOME_CONFIG="$cfg"; : > "$cfg"
             "$TEST_ROOT/bin/daily-welcome" --brain "$1" >/dev/null 2>&1; cat "$cfg" ); }

contains "groq points at groq"     "api.groq.com"          "$(switch groq)"
contains "and names a groq model"  "llama"                 "$(switch groq)"
contains "gemini points at google" "generativelanguage"    "$(switch gemini)"
contains "ollama stays on this Mac" "localhost:11434"      "$(switch ollama)"
contains "openai points at openai" "api.openai.com"        "$(switch openai)"
contains "and each one turns the model path on" 'ORBIT_NLU="openai"' "$(switch groq)"
contains "claude needs no key at all" 'ORBIT_NLU="claude"' "$(switch claude)"

# Switching twice must not leave both.
two="$( export WELCOME_CONFIG="$cfg"; : > "$cfg"
        "$TEST_ROOT/bin/daily-welcome" --brain groq   >/dev/null 2>&1
        "$TEST_ROOT/bin/daily-welcome" --brain gemini >/dev/null 2>&1
        cat "$cfg" )"
lacks "the old endpoint is gone" "api.groq.com" "$two"
ok "and there is one of each setting" "1" \
   "$(printf '%s\n' "$two" | grep -c '^ORBIT_OPENAI_BASE=')"

ok "an unknown name is refused" "2" \
   "$( export WELCOME_CONFIG="$cfg"
       "$TEST_ROOT/bin/daily-welcome" --brain nonsense >/dev/null 2>&1; echo $? )"

# A setting that changes nothing must not claim it changed something.
#
# "--brain groq doesn't do anything" was a fair report: it wrote the
# config, announced that understanding now went to Groq, and without a
# key the model path is skipped in silence, so everything carried on
# exactly as before.
brain_out() {
  ( export WELCOME_CONFIG="$WELCOME_STATE_DIR/b.sh"; : > "$WELCOME_CONFIG"
    export HOME="$WELCOME_STATE_DIR/nokey"; mkdir -p "$HOME"
    "$TEST_ROOT/bin/daily-welcome" --brain "$1" 2>&1 )
}
out="$(brain_out groq)"
contains "it says the setting is not in use without a key" "NOT IN USE YET" "$out"
lacks "and does not claim otherwise" "understanding goes to groq" "$out"
contains "and says where to get one"  "console.groq.com" "$out"
contains "and how to check afterwards" "--brain test"    "$out"

# One real request, and whatever came back.
out="$( export WELCOME_CONFIG="$WELCOME_STATE_DIR/b.sh"
        export HOME="$WELCOME_STATE_DIR/nokey"
        "$TEST_ROOT/bin/daily-welcome" --brain test 2>&1 )"
contains "the test names the endpoint" "Endpoint:" "$out"
contains "and says when there is no key" "No key stored" "$out"

# And status tells the truth about the same thing.
out="$( export WELCOME_CONFIG="$WELCOME_STATE_DIR/b.sh"
        export HOME="$WELCOME_STATE_DIR/nokey"
        "$TEST_ROOT/bin/daily-welcome" --status 2>&1 )"
contains "status says understanding is not in use" "NO KEY" "$out"
