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
# How it signs off. Empty by default: a briefing that simply ends sounds
# like a person finishing a sentence, and one that ends "Standing by."
# every single morning sounds like the computer on a spaceship.
: "${WELCOME_CLOSER:=}"

# How many items get read aloud (the screen still shows all of them).
: "${WELCOME_SPEAK_MAX_ITEMS:=3}"

# Playback volume for the hosted voice, 0.0-1.0.
: "${WELCOME_VOLUME:=1.0}"

# --- ElevenLabs ---
# The voice is looked up by name in your account, so add it to your voices
# in the ElevenLabs library first. Set an id directly to skip the lookup.
# A voice from the ElevenLabs library isn't in your account until you add
# it there, and the name lookup only sees your account - so the id is set
# directly, which works either way.
: "${WELCOME_ELEVEN_VOICE_NAME:=Veda Sky}"
: "${WELCOME_ELEVEN_VOICE_ID:=GWparLcEBJuQc36gyF2J}"
# Two models, because the two jobs have opposite priorities. The briefing
# is a monologue nobody is waiting on, so it uses the better-sounding model;
# a reply to something you just said is judged on how fast it starts, so it
# uses the low-latency one.
: "${WELCOME_ELEVEN_MODEL:=eleven_multilingual_v2}"
: "${WELCOME_ELEVEN_FAST_MODEL:=eleven_flash_v2_5}"

# Matches the settings the sample was rendered with: speed 1.00,
# stability 0.50, similarity 0.75, style 0, speaker boost on.
: "${WELCOME_ELEVEN_SPEED:=1.0}"
: "${WELCOME_ELEVEN_STABILITY:=0.5}"
: "${WELCOME_ELEVEN_SIMILARITY:=0.75}"
: "${WELCOME_ELEVEN_STYLE:=0}"
: "${WELCOME_ELEVEN_SPEAKER_BOOST:=true}"

# Speech at 44kHz/128kbps is four times the bytes of something that sounds
# identical through a laptop speaker, and those bytes are part of the wait.
: "${WELCOME_ELEVEN_FORMAT:=mp3_22050_32}"
: "${WELCOME_ELEVEN_TIMEOUT:=25}"

# The API key lives in the login Keychain (daily-welcome --set-key).
# A plain file is honored too, for anyone who prefers it.
: "${WELCOME_KEYCHAIN_SERVICE:=daily-welcome-elevenlabs}"
: "${WELCOME_ELEVEN_KEY_FILE:=$HOME/.config/daily-welcome/elevenlabs-key}"

# --- Apple `say`, used when ElevenLabs isn't reachable ---
# Expression, for the built-in voices.
#
# `say` is flat because nothing was ever asking it not to be. It takes
# embedded commands the rest of this never used:
#
#   [[pmod N]]  pitch MODULATION - how far the pitch moves across a
#               sentence. This is the expressiveness dial. Default is
#               around 50; higher is livelier, past ~120 is pantomime.
#   [[pbas N]]  pitch baseline - the middle of the voice's range.
#   [[volm N]]  volume, 0 to 1.
#
# Neural and Siri voices may ignore these, since they do their own
# prosody - which is a good sign, not a bad one. Set modulation to
# empty to send nothing at all.
# How much the built-in voice moves in pitch. EMPTY means the voice's own
# setting, which is what it was tuned with. This was pushed to 78 to
# answer "it is so expressionless", and 78 is a lot of swing: the result
# sings rather than speaks. --expression puts it back up if you want it.
: "${WELCOME_SAY_MODULATION:=}"
: "${WELCOME_SAY_PITCH:=}"

# The built-in voices are not all the same. The default one that ships
# turned on is the worst of them; the Premium downloads are markedly
# better, and the Siri voices better still.
#
#   WELCOME_VOICE=""            pick the best installed, from the list below
#   WELCOME_VOICE="system"      use the System Settings voice - the only
#                               way to reach a Siri voice, which `say`
#                               will not select by name
#   WELCOME_VOICE="Ava (Premium)"   a specific one
#
# daily-welcome --mac-voices shows what is installed and how to get more.
: "${WELCOME_SPEAK_RATE:=175}"
# "system" means whatever you have set in System Settings > Accessibility
# > Spoken Content > System Voice, and that is the default on purpose:
# it is the only way to reach the Siri voices, which are neural and are
# far and away the best thing `say` can produce. `say -v` cannot name
# one, so the only route to them is to not name a voice at all.
#
# Set a name here to override it - daily-welcome --use-voice "Ava (Premium)" -
# or leave it empty to fall back to searching WELCOME_VOICES.
: "${WELCOME_VOICE:=system}"
: "${WELCOME_VOICES:=Ava (Premium)|Zoe (Premium)|Allison (Premium)|Nicky (Enhanced)|Ava (Enhanced)|Zoe (Enhanced)|Samantha (Enhanced)|Ava|Zoe|Allison|Nicky|Samantha|Susan}"

# ------------------------------------------------------- voice commands

# Listening for "Hey Orbit". 0 keeps the daily briefing but never opens
# the microphone.
: "${ORBIT_LISTEN:=1}"
: "${ORBIT_WAKE_WORD:=hey orbit}"

# Other things the recogniser hears when you say the wake word. A made-up
# name isn't in any language model, so it comes back as whatever real words
# it resembled; these are the usual ones, separated by |. If doctor shows
# it hearing something else consistently, add that here.
: "${ORBIT_WAKE_ALIASES:=orbit|or bit|orbid|orbits|arbit|hey robot|okay orbit|hey or|hey orb|hey ork|hey orbits}"

# What it says when you use the wake word on its own, with no command
# after it. $WELCOME_NAME is filled in.
: "${ORBIT_GREETING:=Hi $WELCOME_NAME. What can I do for you today?}"
# What it says to the wake word when it does not yet know who said it.
# Two words is rarely enough voice to identify anybody, so this is the
# ordinary case and not a refusal - it acknowledges without using a name,
# and the command that follows is long enough to actually check.
: "${ORBIT_GREETING_UNKNOWN:=Yes?}"

# How long it keeps listening after that greeting before going quiet again.
: "${ORBIT_FOLLOWUP_SECONDS:=9}"

# Nicknames -> people. Lines like:  mama = +15551234567
: "${ORBIT_CONTACTS_FILE:=$HOME/.config/daily-welcome/contacts.conf}"

# Where your repos live, for "tell Claude to ... in the <name> repo".
# $HOME is included because plenty of people just clone into their home
# directory; Library, Applications and dotfolders are pruned during the
# search so that stays quick.
: "${ORBIT_REPO_ROOTS:=$HOME/projects $HOME/code $HOME/dev $HOME/src $HOME/Developer $HOME/repos $HOME}"
: "${ORBIT_REPO_DEPTH:=2}"
: "${ORBIT_DEFAULT_REPO:=}"

# Claude Code runs headless here, so it can't answer a permission prompt.
# Narrow this if you'd rather it only ever read.
: "${ORBIT_CLAUDE_FLAGS:=--permission-mode acceptEdits}"

# Which inbox mail counts as "awaiting reply", and how many one command may
# touch. The cap is a blast radius, not a performance setting.
: "${ORBIT_MAIL_AWAITING_DAYS:=7}"
: "${ORBIT_MAIL_MAX_BATCH:=25}"
: "${ORBIT_MAIL_TIMEOUT:=25}"

# How many of the newest messages to scan per mailbox. Filtering the whole
# mailbox is what made every mail question answer "your inbox is clear":
# the query outlived its timeout and came back empty.
: "${ORBIT_MAIL_SCAN:=60}"

# How many of the newest drafts to look through when sending the one just
# written. It was made seconds ago, so it is at the top; walking a mailbox
# with hundreds of drafts asking each for its recipients is the same stall
# in a worse place - right after you have said yes.
: "${ORBIT_MAIL_DRAFT_SCAN:=40}"

# Macros: one phrase, several commands.
: "${ORBIT_MACROS_FILE:=$HOME/.config/daily-welcome/macros.conf}"

# Speaking first: a meeting about to start, a job Claude finished, mail
# from someone on the list. Quiet hours are shared with tone.
: "${ORBIT_PROACTIVE:=1}"
: "${ORBIT_PROACTIVE_GAP_SECONDS:=600}"
: "${ORBIT_MEETING_WARNING_MINUTES:=5}"
: "${ORBIT_VIPS:=}"

# Voice commands only while the Mac is unlocked - the nearest thing to
# knowing who is speaking that doesn't involve guessing.
: "${ORBIT_REQUIRE_UNLOCKED:=1}"

# A word that must appear in the command before anything is sent, called,
# or dispatched. Empty means no passphrase.
: "${ORBIT_PASSPHRASE:=}"

# A confirmed action expires; a "yes" twenty minutes late shouldn't send.
: "${ORBIT_PLAN_TTL_MINUTES:=10}"

# How many items get read back for "what's on my calendar".
: "${ORBIT_READBACK_ITEMS:=3}"

# Conversation: after the first exchange the wake word isn't needed again
# until you end it ("thanks", "that's all") or say nothing for a while.
: "${ORBIT_CONVERSATION:=1}"
: "${ORBIT_CONVERSATION_SECONDS:=25}"
: "${ORBIT_SIGNOFF:=Any time.}"

# How close a heard word must be to the name to count as the wake word.
# Lower catches more mishearings and more false alarms.
: "${ORBIT_WAKE_THRESHOLD:=0.6}"

# On-device recognition keeps audio on this Mac, but is markedly worse at
# words it has never seen - and a made-up name is always one. On-device it
# hears "hey Orbit" as things like "pay your back oh my", which no amount
# of fuzzy matching can rescue, so the default is Apple's server
# recognition. Set to 1 to keep audio local and accept the misses.
: "${ORBIT_ONDEVICE:=0}"

# Option-Space starts listening without the wake word. The wake word is
# the part most likely to fail; a key never mishears you.
: "${ORBIT_HOTKEY:=1}"

# Stop listening while another app is using the microphone - which is what
# being on a call looks like from here, whether that is a relayed iPhone
# call, FaceTime, Zoom, Meet in a browser tab, Teams or a Slack huddle.
# Nothing is announced when it happens: an assistant that says "going
# quiet" over your call has missed the point.
# How long a half-finished request waits for its missing piece. Long
# enough to think, short enough that an abandoned question never finishes
# itself an hour later.
# Which service speaks. "auto" prefers ElevenLabs, then OpenAI, then the
# best built-in macOS voice - so a failing provider costs you the voice
# and never the briefing. Set it explicitly to pin one:
#   WELCOME_TTS=openai       use OpenAI, reusing your existing key
#   WELCOME_TTS=elevenlabs   ElevenLabs only
#   WELCOME_TTS=say          no network at all
# How long the voice rests at a comma.
#
#   short    (default) keep the comma, shorten the pause - the engines
#            stop hard at one, and that is what sounds synthetic
#   natural  leave the text exactly as written
#   none     remove the commas altogether
: "${WELCOME_PAUSE:=short}"
# How long the comma rest is, in milliseconds. The engines' own rest is
# somewhere near 400 and sounds like dictation; 110 was the other extreme
# and ran the words together. A person resting at a comma is about 200.
: "${WELCOME_PAUSE_MS:=210}"

# Lean on the words that mean "act on this" - overdue, unread, late.
#
# Off by default. `say` understands [[emph +]], but what it does with it
# is blunt: the word jumps in pitch and stretches, and stacked on top of
# any pitch modulation it lurches. Worth trying, not worth defaulting to.
: "${WELCOME_SAY_EMPHASIS:=0}"

: "${WELCOME_OPENAI_VOICE:=nova}"
: "${WELCOME_OPENAI_TTS_MODEL:=gpt-4o-mini-tts}"
# Delivery notes, for the models that accept them. Empty is fine.
: "${WELCOME_OPENAI_TTS_INSTRUCTIONS:=Speak with calm confidence, like a capable assistant who is already halfway through the task. Keep phrases connected and do not pause between them; run clauses together the way people do in conversation. Brisk, even pace. No rising intonation at the end of statements.}"

# Piper, the free neural voice that runs on this Mac. These have to be
# declared even when piper is not installed: tts_backend asks
# piper_available whether it is there, piper_available reads these, and
# under set -u reading one that was never declared ends the shell where
# it stands - silently, in the middle of working out how to speak.
# daily-welcome --setup-piper downloads a voice and points the model at it.
: "${WELCOME_PIPER_BIN:=}"
: "${WELCOME_PIPER_MODEL:=$HOME/.config/daily-welcome/piper/voice.onnx}"
# Above 1 is slower and steadier; below 1 is quicker.
: "${WELCOME_PIPER_LENGTH:=1.0}"

: "${ORBIT_SLOT_TTL_SECONDS:=120}"

# How many past events and matched history lines a turn may carry into
# the model's prompt when you ask about something that already happened.
# Recognising who is speaking. Off by default: it means keeping a few
# seconds of microphone audio on disk, which is not something to switch
# on quietly. daily-welcome --setup-speaker turns it on deliberately.
: "${ORBIT_SPEAKER_ID:=0}"
: "${ORBIT_SPEAKER_STORE:=$HOME/.config/daily-welcome/voices.json}"
# How close a voice must be to count as a match, and how far clear of
# the runner-up it must be. Higher admits fewer people and says "I don't
# know" more often, which is the safer error. `orbit voice test` prints
# the actual numbers for the last thing said, so these can be set from
# evidence rather than from a guess.
: "${ORBIT_SPEAKER_THRESHOLD:=0.78}"
: "${ORBIT_SPEAKER_MARGIN:=0.06}"
# How much real speech - silence already removed - a clip needs before it
# is worth embedding. A second of voice embeds badly, and a wandering
# vector is what lands a stranger next to somebody real.
: "${ORBIT_SPEAKER_MIN_SECONDS:=1.6}"

# Letting somebody in for one conversation.
#
# Saying "bypass <code>" waves through the voice that was just turned
# away, for a few minutes. It has to be said by a voice that IS
# recognised - the whole point is that the person being let in cannot
# let themselves in - and `orbit voice bypass` does the same thing from
# a terminal, so a bad day for the recogniser cannot lock anybody out.
#
# Change the code. This one is written in a public repository.
: "${ORBIT_BYPASS_CODE:=727590}"
: "${ORBIT_BYPASS_MINUTES:=10}"
# How long it keeps listening after turning somebody away, so the code
# can be said straight back without the wake word. Quietly: the insult is
# not repeated at every sentence during it.
: "${ORBIT_BYPASS_LISTEN_SECONDS:=25}"
: "${ORBIT_SPEAKER_TIMEOUT:=12}"
: "${ORBIT_SPEAKER_PYTHON:=}"
# Who is speaking, for whatever is about to be asked. Set by orbit before
# it plans a turn; declared here so that everything else that reads it -
# the prompt builder above all - has something to read when it was not.
: "${ORBIT_SPEAKER_NAME:=}"
# Whether an unrecognised voice is REFUSED, as opposed to simply not
# greeted by name.
#
# Off. Recognising a voice is a guess with a confidence attached, and
# turning a guess into a gate means every time the guess is wrong the
# assistant stops working for the person who owns it - including, if the
# wrong guess lands on a ban, for everybody at once. Names, greetings and
# refusing a voice you have deliberately banned all work without it.
#
# `orbit voice gate on` turns it on once you have enrolled properly and
# `orbit voice test` shows scores you believe.
: "${ORBIT_SPEAKER_REQUIRE_ENROLLED:=0}"
# What an unrecognised voice hears, and what a banned one hears.
#
# Empty means the built-in lines in lib/speaker.sh, which are a rotating
# set rather than one sentence: being told no in exactly the same words
# every single time is the most machine-like thing a machine can do. Set
# either of these to a line of your own and it is used instead, every
# time - including the polite version this used to ship with:
#   ORBIT_SPEAKER_UNKNOWN="Hi! To continue using OrbitAI, please verify
#   your voice with the DailyOS Team. Thank you!"
#
# No apostrophes in a value set here: inside ${VAR:=word} bash treats a
# lone quote as opening one, even within double quotes, and the whole
# file stops parsing. The built-in lines live in a function, where they
# can have all the apostrophes they like.
: "${ORBIT_SPEAKER_UNKNOWN:=}"
: "${ORBIT_SPEAKER_REFUSAL:=}"

: "${ORBIT_MEMORY_EVENTS:=12}"
: "${ORBIT_MEMORY_MATCHES:=10}"

: "${ORBIT_PAUSE_ON_CALL:=1}"

# Bundle identifiers that should never count as a call, separated by
# commas - a recorder you leave running, say.
: "${ORBIT_CALL_IGNORE:=}"

# Answering questions, and reading the screen.
: "${ORBIT_ASK_TIMEOUT:=30}"
: "${ORBIT_ASK_SENTENCES:=2}"
: "${ORBIT_SCREEN_TIMEOUT:=45}"

# Match the tone of the request: a clipped order gets a clipped answer, a
# frustrated one gets no cheerfulness, late at night gets quieter.
: "${ORBIT_MATCH_TONE:=1}"
: "${ORBIT_QUIET_FROM_HOUR:=22}"
: "${ORBIT_QUIET_UNTIL_HOUR:=7}"
: "${ORBIT_TONE:=neutral}"

# How long "who and what we were just talking about" survives.
: "${ORBIT_CONTEXT_TTL_SECONDS:=120}"

# How commands are understood.
#   rules  - only the built-in patterns, no network, no key, instant
#   auto   - rules first, then OpenAI for anything they miss (default)
#   openai - OpenAI first, which understands more and costs a round trip
#
# In auto, a command the rules know answers without touching the network;
# only the sentences they miss pay for a model. That one request now both
# reads the sentence and writes the reply, rather than classifying and then
# asking again.
# claude: Claude Code works out what you meant. No key, no account, no
# per-word cost, and nothing to sign up for - which is the whole reason
# it is the default.
#
#   claude   Claude Code (the default)
#   openai   any service speaking the OpenAI chat-completions shape -
#            Groq and Gemini both do, and both have free tiers. Set it
#            up with `daily-welcome --brain groq`.
#   rules    the built-in rules only. No model, no network, no key.
#   auto     rules first, then whichever of the above is configured.
: "${ORBIT_NLU:=claude}"

# gpt-4o-mini is the fast one. A larger model understands more and takes
# noticeably longer to start talking, which on a voice assistant is the
# thing you feel.
# Any service that speaks the OpenAI chat-completions shape works here,
# which includes two with free tiers that are far faster than booting
# Claude Code for every sentence:
#
#   Groq    console.groq.com        free, and the quickest of them
#   Gemini  aistudio.google.com     free tier
#   Ollama  ollama.com              entirely on this Mac, no account
#
# Do not set these by hand. Providers retire models - the one recommended
# here for months was decommissioned out from under it - and a config
# file naming a dead model fails at the moment you speak, with an error
# nobody sees. This asks the endpoint instead:
#
#   daily-welcome --brain groq        endpoint, and a model it serves today
#   daily-welcome --set-openai-key    the key
#   daily-welcome --brain test        one real question, and the answer
#   daily-welcome --brain models      everything it offers
# Searching the web and reading a page are real work, so they get a longer
# leash than an ordinary answer.
: "${ORBIT_WEB_TIMEOUT:=45}"

: "${ORBIT_OPENAI_BASE:=https://api.openai.com/v1}"
: "${ORBIT_OPENAI_MODEL:=gpt-4o-mini}"
# A model that has not answered in this long is not going to save the
# conversation - falling through to Claude or to the rules is quicker than
# waiting. The log showed every unrecognised sentence costing the full
# twelve seconds before saying "none".
: "${ORBIT_OPENAI_TIMEOUT:=7}"
: "${ORBIT_OPENAI_KEYCHAIN:=daily-welcome-openai}"
: "${ORBIT_OPENAI_KEY_FILE:=$HOME/.config/daily-welcome/openai-key}"

# "with a fire emoji" becomes an actual emoji in messages, notes and mail.
: "${ORBIT_EMOJI:=1}"

# How many previous exchanges the chat replies can see.
: "${ORBIT_CHAT_TURNS:=8}"

# Memory. The transcript is everything ever said, trimmed only when it gets
# genuinely large; facts are the durable things worth carrying into next
# week, written by the same request that answers you.
: "${ORBIT_MEMORY_MAX_LINES:=4000}"
: "${ORBIT_MEMORY_FACTS_MAX:=60}"

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
  # Do this before anything looks for a tool: the app's PATH is not yours.
  command -v orbit_widen_path >/dev/null 2>&1 && orbit_widen_path

  local cfg="${WELCOME_CONFIG:-$HOME/.config/daily-welcome/config.sh}"
  if [ -f "$cfg" ]; then
    # shellcheck disable=SC1090
    . "$cfg"
  fi
}
