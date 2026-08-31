#!/bin/bash
# Configuration defaults for daily-welcome.
# Override any of these in ~/.config/daily-welcome/config.sh

: "${WELCOME_NAME:=Arjun}"

# Where state, the voice cache, and logs live.
: "${WELCOME_STATE_DIR:=$HOME/.local/state/daily-welcome}"

# How the greeting is shown: dialog | notification | both | stdout
: "${WELCOME_PRESENT:=dialog}"

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

# Max items shown per section on screen.
: "${WELCOME_MAX_ITEMS:=8}"

# Include reminders that have no due date but are flagged.
: "${WELCOME_REMINDERS_INCLUDE_UNDATED:=0}"

# Plain-text task list. Markdown checkboxes ("- [ ] thing") or bare lines.
: "${WELCOME_TASKS_FILE:=$HOME/todo.md}"

# Calendar via AppleScript is slow and can hang; off unless you ask for it.
# Install icalBuddy (`brew install ical-buddy`) for the fast path.
: "${WELCOME_CALENDAR_APPLESCRIPT:=0}"

# Seconds any single data source gets before it's abandoned.
: "${WELCOME_SOURCE_TIMEOUT:=15}"

# --------------------------------------------------------------- speech

: "${WELCOME_SPEAK:=1}"

# elevenlabs | say | auto  (auto = ElevenLabs when a key is set, else say)
: "${WELCOME_TTS:=auto}"

# How the spoken briefing addresses you. "sir" gets you the full Jarvis;
# set to empty for just your name.
: "${WELCOME_HONORIFIC:=sir}"

# How it signs off.
: "${WELCOME_CLOSER:=Standing by.}"

# How many items get read aloud (the screen still shows all of them).
: "${WELCOME_SPEAK_MAX_ITEMS:=3}"

# Playback volume for the hosted voice, 0.0-1.0.
: "${WELCOME_VOLUME:=1.0}"

# --- ElevenLabs ---
# The voice is looked up by name in your account, so add it to your voices
# in the ElevenLabs library first. Set an id directly to skip the lookup.
: "${WELCOME_ELEVEN_VOICE_NAME:=Veda Sky}"
: "${WELCOME_ELEVEN_VOICE_ID:=}"
: "${WELCOME_ELEVEN_MODEL:=eleven_multilingual_v2}"

# Matches the settings the sample was rendered with: speed 1.00,
# stability 0.50, similarity 0.75, style 0, speaker boost on.
: "${WELCOME_ELEVEN_SPEED:=1.0}"
: "${WELCOME_ELEVEN_STABILITY:=0.5}"
: "${WELCOME_ELEVEN_SIMILARITY:=0.75}"
: "${WELCOME_ELEVEN_STYLE:=0}"
: "${WELCOME_ELEVEN_SPEAKER_BOOST:=true}"

: "${WELCOME_ELEVEN_FORMAT:=mp3_44100_128}"
: "${WELCOME_ELEVEN_TIMEOUT:=25}"

# The API key lives in the login Keychain (daily-welcome --set-key).
# A plain file is honored too, for anyone who prefers it.
: "${WELCOME_KEYCHAIN_SERVICE:=daily-welcome-elevenlabs}"
: "${WELCOME_ELEVEN_KEY_FILE:=$HOME/.config/daily-welcome/elevenlabs-key}"

# --- Apple `say`, used when ElevenLabs isn't reachable ---
: "${WELCOME_SPEAK_RATE:=170}"
: "${WELCOME_VOICE:=}"
: "${WELCOME_VOICES:=Ava (Premium)|Zoe (Premium)|Allison (Premium)|Samantha (Enhanced)|Ava (Enhanced)|Zoe|Allison|Samantha|Susan}"

welcome_load_user_config() {
  local cfg="${WELCOME_CONFIG:-$HOME/.config/daily-welcome/config.sh}"
  if [ -f "$cfg" ]; then
    # shellcheck disable=SC1090
    . "$cfg"
  fi
}
