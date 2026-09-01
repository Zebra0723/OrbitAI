#!/bin/bash
# Installs daily-welcome: a menu bar agent that greets you the first time
# you open your Mac each day. Safe to re-run - it replaces what's there.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="${DAILY_WELCOME_LABEL:-com.arjun.dailywelcome}"
APP_DIR="$HOME/Applications/DailyWelcome.app"
BIN_LINK="$HOME/.local/bin/daily-welcome"
ORBIT_LINK="$HOME/.local/bin/orbit"
CONTACTS="$HOME/.config/daily-welcome/contacts.conf"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="$HOME/.local/state/daily-welcome"
LOG="$STATE_DIR/agent.log"
CONFIG="$HOME/.config/daily-welcome/config.sh"
INTERVAL="${DAILY_WELCOME_INTERVAL:-120}"
WAKE_WORD="${ORBIT_WAKE_WORD:-hey Orbit}"
AGENT_PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
WANT_APP=1
FORCE_REBUILD=0
NEW_BUILD=0

for arg in "$@"; do
  case "$arg" in
    --no-app) WANT_APP=0 ;;         # skip the menu bar app, poll instead
    --rebuild) FORCE_REBUILD=1 ;;   # rebuild even if nothing changed
    -h|--help)
      sed -n '2,4p' "$0"
      echo
      echo "  ./install.sh            menu bar app if swiftc is available"
      echo "  ./install.sh --no-app   background polling only, no menu bar item"
      echo "  ./install.sh --rebuild  force a rebuild (resets app permissions)"
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
ln -sfn "$ROOT/bin/orbit" "$ORBIT_LINK"
chmod +x "$ROOT/bin/daily-welcome" "$ROOT/bin/orbit"

if [ ! -f "$CONTACTS" ]; then
  cat > "$CONTACTS" <<'CONTACTS_EOF'
# Nicknames for the people you message by voice.
# Anything not listed here is looked up in Contacts by name.
#
#   mama = +15551234567
#   priya = priya@example.com
#   boss = Alex Chen
CONTACTS_EOF
fi

# --- 2. stop anything already running --------------------------------------

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "DailyWelcome.app/Contents/MacOS/DailyWelcome" 2>/dev/null || true

# --- 3. build the menu bar app, if we can ----------------------------------

BUILT_APP=0

# Rebuilding changes the app's ad-hoc signature, and macOS ties permissions
# to that signature - so an unnecessary rebuild silently throws away every
# Reminders, Calendar and Microphone approval you have given. Only rebuild
# when the sources are actually newer than the binary.
app_is_current() {
  local binary="$APP_DIR/Contents/MacOS/DailyWelcome" src
  [ -x "$binary" ] || return 1
  for src in "$ROOT"/menubar/*.swift; do
    [ "$src" -nt "$binary" ] && return 1
  done
  return 0
}

if [ "$WANT_APP" -eq 1 ]; then
  if command -v swiftc >/dev/null 2>&1; then
    if [ "$FORCE_REBUILD" -eq 0 ] && app_is_current; then
      say_step "Menu bar app is already up to date (keeping its permissions)"
      BUILT_APP=1
    else
    say_step "Building the menu bar app"
    rm -rf "$APP_DIR"
    mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

    swiftc -O -o "$APP_DIR/Contents/MacOS/DailyWelcome" \
      "$ROOT/menubar/main.swift" "$ROOT/menubar/listener.swift"

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
    <key>DWOrbitPath</key><string>$ORBIT_LINK</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Orbit listens for "$WAKE_WORD" so you can give it commands out loud.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>Orbit turns what you say into commands. Recognition runs on this Mac.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Orbit controls apps like Mail, Messages and Music on your behalf.</string>
</dict>
</plist>
PLIST

    # Ad-hoc signature keeps the app's identity stable, so the Reminders and
    # Calendar permissions you grant once aren't asked for again.
    if command -v codesign >/dev/null 2>&1; then
      codesign --force --sign - "$APP_DIR" >/dev/null 2>&1 || true
    fi
    BUILT_APP=1
    NEW_BUILD=1
    fi
  else
    cat <<'NOSWIFT'

  ------------------------------------------------------------------
  swiftc is not installed, so THE MENU BAR APP CANNOT BE BUILT.

  Without it there is no menu bar icon, no "Hey Orbit" listening, and
  macOS never asks for any permissions - there's no app to ask for them.
  The daily briefing still works, on a timer.

  To get the whole thing:

      xcode-select --install       (a few minutes, ~1GB)
      ./install.sh                 (run this again afterwards)
  ------------------------------------------------------------------

NOSWIFT
  fi
fi

# --- 4. launch agent -------------------------------------------------------

say_step "Installing the login agent"
if [ "$BUILT_APP" -eq 1 ]; then
  sed -e "s|@@LABEL@@|$LABEL|g" \
      -e "s|@@PROGRAM@@|$APP_DIR/Contents/MacOS/DailyWelcome|g" \
      -e "s|@@BIN@@|$BIN_LINK|g" \
      -e "s|@@ORBIT@@|$ORBIT_LINK|g" \
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

if ! launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null; then
  echo "  (launchctl wouldn't load it; trying the older command)"
  launchctl load -w "$PLIST" 2>/dev/null || true
fi
launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true

sleep 2
if [ "$BUILT_APP" -eq 1 ] && ! pgrep -f "DailyWelcome.app/Contents/MacOS/DailyWelcome" >/dev/null 2>&1; then
  echo
  echo "  The app was built but isn't running. $ROOT/bin/doctor will say why."
fi

# --- 5. done ---------------------------------------------------------------

echo
say_step "Installed."
if [ "$BUILT_APP" -eq 1 ]; then
  echo "  A sun icon is now in your menu bar (top right). It has no Dock icon"
  echo "  and doesn't appear in Launchpad - the menu bar is where it lives."
  echo "  It greets you the first time the Mac wakes each day."
else
  echo "  Running in the background on a timer; no menu bar item, no voice"
  echo "  commands. Install swiftc as above and re-run to get those."
fi
echo
echo "  Something wrong:  $ROOT/bin/doctor"

case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *)
    echo
    echo "  Note: ~/.local/bin isn't on your PATH, so typing 'daily-welcome'"
    echo "  or 'orbit' won't find them. Either use the full paths above, or:"
    echo
    echo "      echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"
    echo "      source ~/.zshrc"
    ;;
esac

if [ "$NEW_BUILD" -eq 1 ]; then
  echo
  echo "  The app was rebuilt, which macOS treats as a new app, so it will"
  echo "  ask for its permissions again. That's expected, not a fault."
fi
echo
echo "  Add your voice:  $BIN_LINK --set-key      (ElevenLabs API key)"
echo "  Check the voice: $BIN_LINK --test-voice"
echo "  Hear it all:     $BIN_LINK --force"
echo "  See settings:    $BIN_LINK --status"
echo "  Edit settings:   $CONFIG"
echo "  Uninstall:       $ROOT/uninstall.sh"
echo
echo "  Say hello:       \"$WAKE_WORD, what time is it\""
echo "  What it knows:   $ORBIT_LINK examples"
echo
echo "  Permissions it will ask for, once each:"
echo "    Microphone + Speech Recognition   listening for \"$WAKE_WORD\""
echo "    Reminders, Calendar, Mail,        reading and acting on your things"
echo "    Messages, Contacts, Notes"
echo "    Accessibility                     typing and window commands"
echo
echo "  One it can't ask for: reading Messages needs Full Disk Access, which"
echo "  you add by hand - System Settings > Privacy & Security > Full Disk"
echo "  Access > + > $APP_DIR"
echo
echo "  Until an ElevenLabs key is set it speaks with the best built-in macOS"
echo "  voice. Set the key and it switches to the ElevenLabs voice instead."
