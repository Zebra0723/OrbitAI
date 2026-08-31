# daily-welcome settings. This file is plain bash, sourced on every run.
# Uncomment what you want to change; anything left alone keeps its default.

# What it calls you, on screen and out loud.
# WELCOME_NAME="Arjun"

# How it addresses you in the spoken briefing. Empty for just your name.
# WELCOME_HONORIFIC="sir"

# --- voice -----------------------------------------------------------------

# WELCOME_SPEAK=1                # 0 turns the voice off entirely
# WELCOME_SPEAK_RATE=168         # words per minute; 150 is slower and calmer
# WELCOME_SPEAK_MAX_ITEMS=3      # how many items get read aloud

# Force one specific voice (see: daily-welcome --voices).
# WELCOME_VOICE="Ava (Premium)"

# Or leave WELCOME_VOICE empty and let it pick the first of these that's
# installed. Premium voices are the realistic ones - add them under System
# Settings > Accessibility > Spoken Content > System Voice > Manage Voices.
# WELCOME_VOICES="Ava (Premium)|Zoe (Premium)|Samantha (Enhanced)|Samantha"

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
