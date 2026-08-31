# daily-welcome settings. This file is plain bash, sourced on every run.
# Uncomment what you want to change; anything left alone keeps its default.

# What it calls you, on screen and out loud.
# WELCOME_NAME="Arjun"

# How it addresses you in the spoken briefing. Empty for just your name.
# WELCOME_HONORIFIC="sir"

# --- voice -----------------------------------------------------------------

# WELCOME_SPEAK=1                # 0 turns the voice off entirely
# WELCOME_SPEAK_MAX_ITEMS=3      # how many items get read aloud
# WELCOME_CLOSER="Standing by."  # the sign-off
# WELCOME_VOLUME=1.0             # playback volume, 0.0-1.0

# Which engine: auto (ElevenLabs when a key is set), elevenlabs, or say.
# WELCOME_TTS="auto"

# The ElevenLabs voice, looked up by name in your account. Set the id
# directly to skip the lookup.
# WELCOME_ELEVEN_VOICE_NAME="Veda Sky"
# WELCOME_ELEVEN_VOICE_ID=""

# Delivery. Lower stability is more expressive, higher is steadier and
# more measured. These match the sample the voice was chosen from.
# WELCOME_ELEVEN_STABILITY=0.5
# WELCOME_ELEVEN_SIMILARITY=0.75
# WELCOME_ELEVEN_STYLE=0
# WELCOME_ELEVEN_SPEED=1.0
# WELCOME_ELEVEN_MODEL="eleven_multilingual_v2"

# The API key belongs in the Keychain (daily-welcome --set-key). This file
# is honored too if you would rather keep it on disk.
# WELCOME_ELEVEN_KEY_FILE="$HOME/.config/daily-welcome/elevenlabs-key"

# Fallback macOS voice, used when ElevenLabs can't be reached.
# WELCOME_SPEAK_RATE=170
# WELCOME_VOICE="Ava (Premium)"

# --- what you see ----------------------------------------------------------

# dialog | notification | both | stdout
# WELCOME_PRESENT="dialog"
# WELCOME_DIALOG_TIMEOUT=90      # seconds before the dialog closes itself; 0 waits

# --- what's in the briefing ------------------------------------------------

# WELCOME_SECTIONS="reminders calendar tasks"
# WELCOME_MAX_ITEMS=8
# WELCOME_REMINDERS_INCLUDE_UNDATED=0   # 1 also shows flagged reminders with no due date
# WELCOME_TASKS_FILE="$HOME/todo.md"

# Calendar comes from icalBuddy (brew install ical-buddy) when it's there.
# Without it, set this to 1 to ask Calendar.app directly - correct but slow.
# WELCOME_CALENDAR_APPLESCRIPT=0

# --- when it fires ---------------------------------------------------------

# WELCOME_EARLIEST_HOUR=5        # a 1am session doesn't count as a new day
# WELCOME_REQUIRE_UNLOCKED=1     # wait until you've actually unlocked
