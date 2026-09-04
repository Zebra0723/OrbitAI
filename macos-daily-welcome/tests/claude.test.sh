#!/bin/bash
# Finding Claude Code, which is what understands you.
#
# "It works when I type it and not when I say it" is almost always this:
# the menu bar app inherits launchd's PATH, not the one your shell builds
# at login. A fixed list of directories is not enough either - under nvm
# the binary sits at ~/.nvm/versions/node/v22.11.0/bin/claude, with the
# version in the middle, and fnm, pnpm and asdf all do something similar.

test_sandbox
load_orbit

# An empty PATH, because the question is what happens when the binary is
# NOT on it - which is the situation the menu bar app is always in.
bare() { ( PATH="/usr/bin:/bin"; claude_forget; "$@" ); }

plant() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\necho 2.1.0\n' > "$1"
  chmod +x "$1"
}

# Every place it could be, gone. Missing one leaves a copy behind that
# the next check finds instead of what it planted - which is how the
# first version of this file passed while testing the wrong thing.
wipe() {
  rm -rf "$HOME/.nvm" "$HOME/.local/share/fnm" "$HOME/Library/pnpm" \
         "$HOME/.asdf" "$HOME/.claude" "$HOME/.volta" "$HOME/.npm-global" \
         "$HOME/.local/bin" "$HOME/.bun" "$HOME/bin" "$HOME/elsewhere" \
         "$HOME/.local/state/fnm_multishells"
}

for where in \
  "$HOME/.nvm/versions/node/v22.11.0/bin/claude" \
  "$HOME/.local/share/fnm/node-versions/v20.9.0/installation/bin/claude" \
  "$HOME/Library/pnpm/claude" \
  "$HOME/.asdf/installs/nodejs/21.6.1/bin/claude" \
  "$HOME/.claude/local/claude" \
  "$HOME/.volta/bin/claude" \
  "$HOME/.npm-global/bin/claude"
do
  wipe
  plant "$where"
  ok "finds it at ${where#$HOME/}" "$where" "$(bare claude_bin)"
done

# The newest node version wins: an upgrade leaves the old one behind,
# often with an older copy of Claude Code in it.
wipe
plant "$HOME/.nvm/versions/node/v18.0.0/bin/claude"
sleep 0.01
plant "$HOME/.nvm/versions/node/v22.11.0/bin/claude"
ok "the newest node version wins" "$HOME/.nvm/versions/node/v22.11.0/bin/claude" \
   "$(bare claude_bin)"

# Found once, remembered - globbing a few directory trees on every
# spoken sentence is not free.
bare claude_bin >/dev/null
ok "it is written down" "$HOME/.nvm/versions/node/v22.11.0/bin/claude" \
   "$(cat "$WELCOME_STATE_DIR/claude-path" 2>/dev/null)"

# And the note is not trusted past the point where it is true.
wipe
ok "a remembered path that has gone is not used" "1" \
   "$( PATH="/usr/bin:/bin"; claude_bin >/dev/null 2>&1; echo $? )"

# Saying where wins over looking.
plant "$HOME/elsewhere/claude"
ok "an explicit setting is honoured" "$HOME/elsewhere/claude" \
   "$( PATH="/usr/bin:/bin"; ORBIT_CLAUDE_BIN="$HOME/elsewhere/claude" claude_bin )"
ok "and a wrong one is not" "1" \
   "$( PATH="/usr/bin:/bin"; claude_forget
       ORBIT_CLAUDE_BIN=/nowhere/claude claude_bin >/dev/null 2>&1; echo $? )"

# Nothing anywhere is a clear no, not a crash.
wipe
ok "nothing installed is a clean answer" "1" \
   "$( PATH="/usr/bin:/bin"; claude_forget; claude_bin >/dev/null 2>&1; echo $? )"

# The commands that fix it exist.
src="$(cat "$TEST_ROOT/bin/daily-welcome")"
contains "there is a command to go and find it" "findclaude" "$src"
contains "and one to say where it is"           "claudeat"   "$src"
contains "and it writes the answer down"        "ORBIT_CLAUDE_BIN" "$src"
contains "doctor asks the same way the app does" "claude_bin" \
  "$(cat "$TEST_ROOT/bin/doctor")"

# Installing it, for the case where it genuinely is not there. Asked for
# by name - "install claude code to orbit, because it seems to think it
# isn't installed" - and the answer to that is usually "it is installed
# and unfindable", so this looks before it downloads.
wipe
plant "$HOME/.local/bin/claude"
out="$( PATH="/usr/bin:/bin"; claude_forget
        "$TEST_ROOT/bin/daily-welcome" --install-claude 2>&1 )"
contains "installing when it is already there installs nothing" "already here" "$out"
ok "and does not fail for it" "0" \
   "$( PATH="/usr/bin:/bin"; claude_forget
       "$TEST_ROOT/bin/daily-welcome" --install-claude >/dev/null 2>&1; echo $? )"

# npm is NAMED rather than found, so this decides for itself whether
# there is one. Left to PATH, a Mac with Homebrew node would run the real
# npm and download Claude Code in the middle of a test run.
wipe
out="$( PATH="/usr/bin:/bin"; claude_forget
        ORBIT_NPM=/nowhere/npm "$TEST_ROOT/bin/daily-welcome" --install-claude 2>&1 )" \
  && rc=0 || rc=1
ok "with no npm to install it with, it stops" "1" "$rc"
contains "and says what to install first" "nodejs.org" "$out"
contains "rather than leaving you at a wall" "run this again" "$out"

# npm there and refusing, which is what a global directory owned by root
# looks like. The advice must be to fix that, not to reach for sudo.
wipe
stub="$WELCOME_STATE_DIR/npm-that-refuses"
printf '#!/bin/sh\necho "EACCES: permission denied" >&2\nexit 243\n' > "$stub"
chmod +x "$stub"
out="$( PATH="/usr/bin:/bin"; claude_forget
        ORBIT_NPM="$stub" "$TEST_ROOT/bin/daily-welcome" --install-claude 2>&1 )" \
  && rc=0 || rc=1
ok "an npm that refuses is a failure" "1" "$rc"
contains "and the advice is to fix the prefix" "config set prefix" "$out"
# It may MENTION sudo, to say not to. What it must never do is hand
# somebody a line beginning with it: installing global npm packages as
# root is how the directory ends up owned by root in the first place.
ok "and never a command line starting with sudo" "" \
   "$(printf '%s\n' "$out" | grep -E '^[[:space:]]*sudo ')"

contains "the console can ask for it too" "installclaude" \
  "$(cat "$TEST_ROOT/web/server.py")"
