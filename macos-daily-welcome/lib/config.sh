#!/bin/bash
# Configuration defaults for daily-welcome.
# Override any of these in ~/.config/daily-welcome/config.sh

: "${WELCOME_NAME:=Arjun}"

# Where state (last-run stamp) and logs live.
: "${WELCOME_STATE_DIR:=$HOME/.local/state/daily-welcome}"

# How the greeting is shown: dialog | notification | both | stdout
: "${WELCOME_PRESENT:=dialog}"

# Speak the briefing out loud with `say`.
: "${WELCOME_SPEAK:=1}"

# Voice, in preference order: the first one actually installed wins.
# American female, aiming for the composed synthetic-assistant register.
# Ava and Zoe Premium are the Siri-grade neural voices and sound markedly
# more real than plain Samantha - install them under System Settings >
# Accessibility > Spoken Content > System Voice > Manage Voices.
: "${WELCOME_VOICES:=Ava (Premium)|Zoe (Premium)|Allison (Premium)|Samantha (Enhanced)|Ava (Enhanced)|Zoe|Allison|Samantha|Susan}"

# Explicit voice; set this and WELCOME_VOICES is ignored.
: "${WELCOME_VOICE:=}"

# Words per minute. Slightly under the 175 default reads as composed
# rather than chirpy.
: "${WELCOME_SPEAK_RATE:=168}"

# How the spoken briefing addresses you. "sir" gets you the full Jarvis;
# set to empty for just your name.
: "${WELCOME_HONORIFIC:=sir}"

# Cap on how many items get read aloud (the screen shows all of them).
: "${WELCOME_SPEAK_MAX_ITEMS:=3}"

# Auto-dismiss the dialog after N seconds (0 = wait for a click).
: "${WELCOME_DIALOG_TIMEOUT:=90}"

# Don't greet before this hour (0-23). Late-night sessions past midnight
# shouldn't trigger "tomorrow's" welcome at 00:01.
: "${WELCOME_EARLIEST_HOUR:=5}"

# Skip while the screen is locked, so the greeting isn't spent behind the
# lock screen. It fires on the next check after you unlock.
: "${WELCOME_REQUIRE_UNLOCKED:=1}"

# Sections to include, in order. Any of: reminders calendar tasks
: "${WELCOME_SECTIONS:=reminders calendar tasks}"

# Max items shown per section.
: "${WELCOME_MAX_ITEMS:=8}"

# Include reminders that have no due date but are flagged/high priority.
: "${WELCOME_REMINDERS_INCLUDE_UNDATED:=0}"

# Plain-text task list. Markdown checkboxes ("- [ ] thing") or bare lines.
: "${WELCOME_TASKS_FILE:=$HOME/todo.md}"

# Calendar via AppleScript is slow and can hang; off unless you ask for it.
# Install icalBuddy (`brew install ical-buddy`) for the fast path.
: "${WELCOME_CALENDAR_APPLESCRIPT:=0}"

# Seconds any single data source gets before it's abandoned.
: "${WELCOME_SOURCE_TIMEOUT:=15}"

welcome_load_user_config() {
  local cfg="${WELCOME_CONFIG:-$HOME/.config/daily-welcome/config.sh}"
  if [ -f "$cfg" ]; then
    # shellcheck disable=SC1090
    . "$cfg"
  fi
}
