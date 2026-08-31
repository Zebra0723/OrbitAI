#!/bin/bash
# Installs daily-welcome: a menu bar agent that greets you the first time
# you open your Mac each day. Safe to re-run - it replaces what's there.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="${DAILY_WELCOME_LABEL:-com.arjun.dailywelcome}"
APP_DIR="$HOME/Applications/DailyWelcome.app"
BIN_LINK="$HOME/.local/bin/daily-welcome"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="$HOME/.local/state/daily-welcome"
LOG="$STATE_DIR/agent.log"
CONFIG="$HOME/.config/daily-welcome/config.sh"
INTERVAL="${DAILY_WELCOME_INTERVAL:-120}"
AGENT_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
WANT_APP=1

for arg in "$@"; do
  case "$arg" in
    --no-app) WANT_APP=0 ;;         # skip the menu bar app, poll instead
    -h|--help)
      sed -n '2,4p' "$0"
      echo
      echo "  ./install.sh            menu bar app if swiftc is available"
      echo "  ./install.sh --no-app   background polling only, no menu bar item"
      exit 0 ;;
    *) echo "install: unknown option $arg" >&2; exit 2 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  echo "install: this is macOS-only (found $(uname -s))." >&2
  exit 1
fi

say_step() { printf '\033[1m==>\033[0m %s\n' "$1"; }

# --- 1. directories, config, and a stable path to the script ---------------

say_step "Setting up directories"
mkdir -p "$STATE_DIR" "$HOME/.local/bin" "$HOME/Library/LaunchAgents" \
         "$HOME/Applications" "$(dirname "$CONFIG")"

if [ ! -f "$CONFIG" ]; then
  cp "$ROOT/config.example.sh" "$CONFIG"
  say_step "Wrote starter settings to $CONFIG"
fi

ln -sfn "$ROOT/bin/daily-welcome" "$BIN_LINK"
chmod +x "$ROOT/bin/daily-welcome"

# --- 2. stop anything already running --------------------------------------

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "DailyWelcome.app/Contents/MacOS/DailyWelcome" 2>/dev/null || true

# --- 3. build the menu bar app, if we can ----------------------------------

BUILT_APP=0
if [ "$WANT_APP" -eq 1 ]; then
  if command -v swiftc >/dev/null 2>&1; then
    say_step "Building the menu bar app"
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

    swiftc -O -o "$APP_DIR/Contents/MacOS/DailyWelcome" "$ROOT/menubar/main.swift"

    cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>DailyWelcome</string>
    <key>CFBundleDisplayName</key><string>Daily Welcome</string>
    <key>CFBundleIdentifier</key><string>$LABEL</string>
    <key>CFBundleExecutable</key><string>DailyWelcome</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>12.0</string>
    <!-- menu bar only: no Dock icon, no windows -->
    <key>LSUIElement</key><true/>
    <key>DWScriptPath</key><string>$BIN_LINK</string>
</dict>
</plist>
PLIST

    # Ad-hoc signature keeps the app's identity stable, so the Reminders and
    # Calendar permissions you grant once aren't asked for again.
    if command -v codesign >/dev/null 2>&1; then
      codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
    fi
    BUILT_APP=1
  else
    echo
    echo "  swiftc isn't installed, so there'll be no menu bar item."
    echo "  Falling back to a background check every ${INTERVAL}s (works fine)."
    echo "  For the menu bar version: xcode-select --install, then re-run this."
    echo
  fi
fi

# --- 4. launch agent -------------------------------------------------------

say_step "Installing the login agent"
if [ "$BUILT_APP" -eq 1 ]; then
  sed -e "s|@@LABEL@@|$LABEL|g" \
      -e "s|@@PROGRAM@@|$APP_DIR/Contents/MacOS/DailyWelcome|g" \
      -e "s|@@BIN@@|$BIN_LINK|g" \
      -e "s|@@LOG@@|$LOG|g" \
      -e "s|@@PATH@@|$AGENT_PATH|g" \
      "$ROOT/launchd/com.arjun.dailywelcome.app.plist.template" > "$PLIST"
else
  sed -e "s|@@LABEL@@|$LABEL|g" \
      -e "s|@@BIN@@|$BIN_LINK|g" \
      -e "s|@@LOG@@|$LOG|g" \
      -e "s|@@PATH@@|$AGENT_PATH|g" \
      -e "s|@@INTERVAL@@|$INTERVAL|g" \
      "$ROOT/launchd/com.arjun.dailywelcome.script.plist.template" > "$PLIST"
fi

launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

# --- 5. done ---------------------------------------------------------------

echo
say_step "Installed."
if [ "$BUILT_APP" -eq 1 ]; then
  echo "  A sun icon is now in your menu bar. Nothing else needs to be open."
  echo "  It greets you the first time the Mac wakes each day."
else
  echo "  Running in the background; it checks every ${INTERVAL}s."
fi
echo
echo "  Add your voice:  $BIN_LINK --set-key      (ElevenLabs API key)"
echo "  Check the voice: $BIN_LINK --test-voice"
echo "  Hear it all:     $BIN_LINK --force"
echo "  See settings:    $BIN_LINK --status"
echo "  Edit settings:   $CONFIG"
echo "  Uninstall:       $ROOT/uninstall.sh"
echo
echo "  The first run asks for Reminders and Calendar access - say yes once."
echo
echo "  Until an ElevenLabs key is set it speaks with the best built-in macOS"
echo "  voice. Set the key and it switches to the ElevenLabs voice instead."
