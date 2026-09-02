#!/bin/bash
# Shared machinery for the test files.
#
# Every test runs against a throwaway state directory and with the rules-only
# NLU, so nothing here touches your real Orbit, reaches the network, or needs
# a Mac. That means these run in CI, on Linux, and in a hurry - which is the
# only kind of test that actually gets run.

TEST_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
FAILURES=()
CURRENT_FILE=""

# A sandbox: no user config, no real state, no model calls.
test_sandbox() {
  export WELCOME_STATE_DIR
  WELCOME_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/orbit-test.XXXXXX")"
  export WELCOME_CONFIG=/dev/null
  export ORBIT_NLU=rules
  export ORBIT_NLU_FALLBACK=0
  export WELCOME_SPEAK=0
  export WELCOME_TTS=say
  export ORBIT_SPEAKER=0
  export WELCOME_NAME=Arjun
  # Somewhere predictable, so a test that writes cannot reach $HOME.
  export HOME="$WELCOME_STATE_DIR/home"
  mkdir -p "$HOME"
}

test_sandbox_clean() {
  case "$WELCOME_STATE_DIR" in
    */orbit-test.*) rm -rf "$WELCOME_STATE_DIR" ;;
  esac
}

# Loads the libraries a test needs, in the order bin/orbit loads them.
# `load_libs intents` pulls in everything intents.sh leans on too.
load_libs() {
  local lib
  for lib in "$@"; do
    # shellcheck disable=SC1090
    . "$TEST_ROOT/lib/$lib.sh"
  done
}

# Everything bin/orbit loads, in the order it loads it. Sourcing a lib on
# its own mostly works and then mostly does not, because they lean on each
# other; loading the lot is a second of startup and no surprises.
ORBIT_LIBS=(common sources messages mail contacts claude_jobs system freeform
            present speech_text tts_eleven tts_openai tts_piper voice intents
            context ask tone macros watch nlu_openai nlu_claude emoji memory
            slots speaker)

load_orbit() {
  # shellcheck disable=SC1090
  . "$TEST_ROOT/lib/config.sh"
  welcome_load_user_config
  load_libs "${ORBIT_LIBS[@]}"
}

# ------------------------------------------------------------ assertions

# ok DESCRIPTION EXPECTED ACTUAL
ok() {
  local what="$1" want="$2" got="$3"
  if [ "$want" = "$got" ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$CURRENT_FILE: $what
    wanted: $want
    got:    $got")
  fi
}

# A haystack can be a whole prompt, and a failure nobody can read is a
# failure nobody fixes.
_short() {
  local s="$1"
  s="$(printf '%s' "$s" | tr '\n' ' ')"
  if [ "${#s}" -gt 240 ]; then printf '%s...' "${s:0:240}"; else printf '%s' "$s"; fi
}

# contains DESCRIPTION NEEDLE HAYSTACK
contains() {
  local what="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*) PASS=$((PASS + 1)) ;;
    *)
      FAIL=$((FAIL + 1))
      FAILURES+=("$CURRENT_FILE: $what
    wanted to find: $needle
    in:             $(_short "$hay")")
      ;;
  esac
}

# lacks DESCRIPTION NEEDLE HAYSTACK
lacks() {
  local what="$1" needle="$2" hay="$3"
  case "$hay" in
    *"$needle"*)
      FAIL=$((FAIL + 1))
      FAILURES+=("$CURRENT_FILE: $what
    did not want to find: $needle
    in:                   $(_short "$hay")")
      ;;
    *) PASS=$((PASS + 1)) ;;
  esac
}

# succeeds DESCRIPTION COMMAND...
succeeds() {
  local what="$1"; shift
  local out
  if out="$("$@" 2>&1)"; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
    FAILURES+=("$CURRENT_FILE: $what
    command failed: $*
    output: $out")
  fi
}

# The first field of a parse_intent line: the intent itself.
intent_of() { printf '%s' "$1" | head -1 | cut -f1; }
arg1_of()   { printf '%s' "$1" | head -1 | cut -f2; }
arg2_of()   { printf '%s' "$1" | head -1 | cut -f3; }
