#!/bin/bash
# Removes daily-welcome. Leaves your settings file alone unless you ask.

set -euo pipefail

LABEL="${DAILY_WELCOME_LABEL:-com.arjun.dailywelcome}"
APP_DIR="$HOME/Applications/DailyWelcome.app"
BIN_LINK="$HOME/.local/bin/daily-welcome"
ORBIT_LINK="$HOME/.local/bin/orbit"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
STATE_DIR="$HOME/.local/state/daily-welcome"
CONFIG="$HOME/.config/daily-welcome/config.sh"

PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
pkill -f "DailyWelcome.app/Contents/MacOS/DailyWelcome" 2>/dev/null || true

rm -f "$PLIST"
rm -rf "$APP_DIR"
[ -L "$BIN_LINK" ] && rm -f "$BIN_LINK"
[ -L "$ORBIT_LINK" ] && rm -f "$ORBIT_LINK"

echo "Removed the agent, the menu bar app, and the daily-welcome and orbit commands."

if [ "$PURGE" -eq 1 ]; then
  rm -rf "$STATE_DIR"
  rm -f "$CONFIG"
  echo "Removed settings and state too."
else
  echo "Kept your settings ($CONFIG) and state ($STATE_DIR)."
  echo "Pass --purge to remove those as well."
fi
