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

# Sections to include, in order.
# Any of: reminders calendar messages mail claude tasks
: "${WELCOME_SECTIONS:=reminders calendar messages mail claude tasks}"

# Max items shown per section on screen.
: "${WELCOME_MAX_ITEMS:=8}"

# Include reminders that have no due date but are flagged.
: "${WELCOME_REMINDERS_INCLUDE_UNDATED:=0}"

# Plain-text task list. Markdown checkboxes ("- [ ] thing") or bare lines.
: "${WELCOME_TASKS_FILE:=$HOME/todo.md}"

# How far back unread Messages count as news, and how much of each to show.
: "${WELCOME_MESSAGES_SINCE_DAYS:=2}"
: "${WELCOME_MESSAGE_PREVIEW:=60}"

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

# ------------------------------------------------------- voice commands

# Listening for "Hey Orbit". 0 keeps the daily briefing but never opens
# the microphone.
: "${ORBIT_LISTEN:=1}"
: "${ORBIT_WAKE_WORD:=hey orbit}"

# What it says when you use the wake word on its own, with no command
# after it. $WELCOME_NAME is filled in.
: "${ORBIT_GREETING:=Hi $WELCOME_NAME. What can I do for you today?}"

# How long it keeps listening after that greeting before going quiet again.
: "${ORBIT_FOLLOWUP_SECONDS:=9}"

# Nicknames -> people. Lines like:  mama = +15551234567
: "${ORBIT_CONTACTS_FILE:=$HOME/.config/daily-welcome/contacts.conf}"

# Where your repos live, for "tell Claude to ... in the <name> repo".
: "${ORBIT_REPO_ROOTS:=$HOME/projects $HOME/code $HOME/dev $HOME/src $HOME/Developer $HOME/repos}"
: "${ORBIT_REPO_DEPTH:=3}"
: "${ORBIT_DEFAULT_REPO:=}"

# Claude Code runs headless here, so it can't answer a permission prompt.
# Narrow this if you'd rather it only ever read.
: "${ORBIT_CLAUDE_FLAGS:=--permission-mode acceptEdits}"

# Which inbox mail counts as "awaiting reply", and how many one command may
# touch. The cap is a blast radius, not a performance setting.
: "${ORBIT_MAIL_AWAITING_DAYS:=7}"
: "${ORBIT_MAIL_MAX_BATCH:=25}"
: "${ORBIT_MAIL_TIMEOUT:=45}"

# A confirmed action expires; a "yes" twenty minutes late shouldn't send.
: "${ORBIT_PLAN_TTL_MINUTES:=10}"

# How many items get read back for "what's on my calendar".
: "${ORBIT_READBACK_ITEMS:=3}"

# Hand phrasings the rules miss to Claude Code to classify.
: "${ORBIT_NLU_FALLBACK:=1}"
: "${ORBIT_NLU_TIMEOUT:=25}"

# Where "search for..." goes.
: "${ORBIT_SEARCH_URL:=https://duckduckgo.com/?q=}"

# Calls go out through FaceTime; a plain phone call is relayed by your
# iPhone. FaceTime asks "call this number?" - autoconfirm presses Return
# for you. Set to 0 to click it yourself.
: "${ORBIT_CALL_AUTOCONFIRM:=1}"

# Say the name back and wait for a yes before dialling. Ringing the wrong
# person isn't something you can take back.
: "${ORBIT_CONFIRM_CALLS:=1}"

# The catch-all: for anything the action catalog doesn't cover, Claude
# writes a one-line command, Orbit reads it back, and it runs only on your
# yes. Whole categories (sudo, disk tools, piping the network to a shell)
# are refused outright regardless. Set to 0 to allow only the catalog.
: "${ORBIT_FREEFORM:=1}"
: "${ORBIT_FREEFORM_TIMEOUT:=20}"

# Absolute path to the orbit command, for actions that outlive the run
# that started them (timers).
: "${ORBIT_BIN:=$HOME/.local/bin/orbit}"

welcome_load_user_config() {
  local cfg="${WELCOME_CONFIG:-$HOME/.config/daily-welcome/config.sh}"
  if [ -f "$cfg" ]; then
    # shellcheck disable=SC1090
    . "$cfg"
  fi
}
