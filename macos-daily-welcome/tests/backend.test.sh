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
