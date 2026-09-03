#!/bin/bash
# Naming a model in a config file is naming something that will be
# retired.
#
# llama-3.3-70b-versatile was the model recommended here until Groq
# decommissioned it, at which point every spoken sentence failed against
# an error nobody sees. Remembering a name is the wrong mechanism;
# asking the endpoint is the right one.

test_sandbox
load_orbit

# ---------------------------------------------------------- choosing one

# The list under test goes through a file: a function body reading "$@"
# would see its OWN arguments when called, not the ones given here.
_list="$WELCOME_STATE_DIR/models.txt"
openai_models() { cat "$_list" 2>/dev/null; }
pick() { printf '%s\n' "$@" > "$_list"; openai_pick_model; }

# Small and quick first: working out one spoken sentence is a small job,
# and on a voice assistant the wait before it starts talking is the thing
# you feel.
ok "the quick one over the big one" "llama-3.1-8b-instant" \
   "$(pick llama-3.3-70b-versatile llama-3.1-8b-instant)"
ok "and over a big one listed first" "llama-3.1-8b-instant" \
   "$(pick openai/gpt-oss-120b llama-3.1-8b-instant qwen/qwen3-32b)"
ok "flash beats pro" "gemini-2.0-flash" \
   "$(pick gemini-2.5-pro gemini-2.0-flash)"

# Everything that is not a chat model is listed alongside the ones that
# are, and none of them can answer a question.
ok "not a transcriber"   "llama-3.1-8b-instant" "$(pick whisper-large-v3 llama-3.1-8b-instant)"
ok "not a safety filter" "openai/gpt-oss-120b" \
   "$(pick meta-llama/llama-guard-4-12b openai/gpt-oss-120b)"
ok "not an embedder"     "qwen/qwen3-32b"      "$(pick text-embedding-3-large qwen/qwen3-32b)"
ok "not a voice"         "qwen/qwen3-32b"      "$(pick playai-tts qwen/qwen3-32b)"

# Nothing usable is not the same as picking badly.
printf '%s\n' whisper-large-v3 playai-tts > "$_list"
ok "nothing usable means no answer" "1" "$(openai_pick_model >/dev/null 2>&1; echo $?)"
: > "$_list"
ok "an empty list too" "1" "$(openai_pick_model >/dev/null 2>&1; echo $?)"

# A name it has never seen still gets chosen over nothing.
ok "something unfamiliar beats nothing" "somelab/brand-new-9b" \
   "$(pick somelab/brand-new-9b)"

# ------------------------------------------------------- and using them

src="$(cat "$TEST_ROOT/bin/daily-welcome")"
contains "switching asks what is served"  "openai_pick_model" "$src"
contains "and a failed request does too"  "decommission"      "$src"
contains "then writes the live one down"  "ORBIT_OPENAI_MODEL" "$src"
contains "there is a way to just look"    "brainmodels"       "$src"

# The dead model must not be handed out as a default any more. It is
# still named in the comments explaining why none of this hardcodes a
# model, which is the opposite of recommending it.
setting="$(grep -hE '^[[:space:]]*(: "\$\{)?ORBIT_OPENAI_MODEL' \
             "$TEST_ROOT/bin/daily-welcome" "$TEST_ROOT/lib/config.sh"
           grep -hE 'model="' "$TEST_ROOT/bin/daily-welcome")"
lacks "the retired model is not a default anywhere" "llama-3.3-70b-versatile" "$setting"
