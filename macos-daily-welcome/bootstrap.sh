#!/bin/bash
# Gets OrbitAI onto a Mac that has nothing on it yet.
#
# install.sh is the real installer and it expects to be sitting inside a
# copy of the repository, because it builds a Swift app out of the files
# next to it. This is the part before that: fetch the repository, then
# hand over. It is the one thing that cannot be a button, since there is
# nothing on the machine yet to draw one.
#
#   curl -fsSL https://raw.githubusercontent.com/Zebra0723/OrbitAI/main/macos-daily-welcome/bootstrap.sh | bash
#
# Safe to run again. A second run updates what is there rather than
# installing a second copy.

set -euo pipefail

REPO="${ORBIT_REPO:-https://github.com/Zebra0723/OrbitAI.git}"
BRANCH="${ORBIT_BRANCH:-main}"
DIR="${ORBIT_DIR:-$HOME/.orbitai}"

say()  { printf '\033[36m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "OrbitAI is a Mac app, and this is $(uname -s)."

# Piping a script into bash means stdin is the script, not the terminal,
# so nothing here may ask a question - there would be nobody to answer.
# Anything that needs a decision is a setting on the Setup page instead.

if ! command -v git >/dev/null 2>&1; then
  fail "This needs git. Run: xcode-select --install
Let Apple's download finish, then paste the same line again."
fi

if ! command -v swiftc >/dev/null 2>&1; then
  # Not fatal: install.sh can set up a version with no menu bar app. But
  # the menu bar app is the whole point, so say so plainly first.
  say "Note: swiftc is missing, so there will be no menu bar app."
  say "To get one: xcode-select --install, then run this line again."
  echo
fi

if [ -d "$DIR/.git" ]; then
  say "Updating the copy in $DIR"
  git -C "$DIR" fetch --quiet origin "$BRANCH"
  git -C "$DIR" checkout --quiet "$BRANCH"
  # Hard reset rather than pull: a pull can stop on a conflict with an
  # edit somebody made in here, and then the installer runs against a
  # half-merged tree. This directory is Orbit's, not theirs.
  git -C "$DIR" reset --quiet --hard "origin/$BRANCH"
else
  say "Fetching OrbitAI into $DIR"
  rm -rf "$DIR"
  git clone --quiet --depth 1 --branch "$BRANCH" "$REPO" "$DIR"
fi

[ -x "$DIR/macos-daily-welcome/install.sh" ] ||
  fail "That copy has no installer in it, which should not be possible.
Try again, and if it happens twice: https://github.com/Zebra0723/OrbitAI/issues"

say "Installing"
exec "$DIR/macos-daily-welcome/install.sh" "$@"
