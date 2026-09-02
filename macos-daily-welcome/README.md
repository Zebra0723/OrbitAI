# Daily Welcome + Orbit

A menu bar assistant for macOS, in two halves.

**Daily Welcome** greets you once a day, the first time you open your Mac. It
says *"Welcome Arjun"* in your ElevenLabs voice and reads a short briefing —
reminders due, today's calendar, unread messages and mail, and anything Claude
finished overnight.

**Orbit** is the same voice, listening. Say *"Hey Orbit"* and give it a
command: message someone, hand a job to Claude in one of your repos, reply to
a pile of email, or drive the Mac itself.

It lives in the menu bar. No Terminal, no Dock icon, no windows.

This is self-contained and unrelated to the rest of the repo; it just lives here.

## Install

```bash
cd macos-daily-welcome
./install.sh
daily-welcome --set-key      # your ElevenLabs API key, into the Keychain
daily-welcome --force        # hear the briefing now
```

Then say **"Hey Orbit, what time is it"** to check the ears work.

If `swiftc` isn't installed (`xcode-select --install` gets it), the installer
skips the menu bar app and falls back to a background check every two minutes.
The briefing still works; voice commands need the app.

## The voice

**Veda Sky** by default, via ElevenLabs, at the settings your sample was
rendered with (speed 1.00, stability 0.50, similarity 0.75, style 0, speaker
boost on). It's a hosted professional clone, so it needs your API key —
`--set-key` stores it in the login Keychain. The voice is looked up by name in
your account, so add it to your ElevenLabs voices first, or set
`WELCOME_ELEVEN_VOICE_ID` to skip the lookup.

**Without a key it still works.** It falls back to the best built-in macOS
voice, so a missing key, dead network, or API error costs you the voice, never
the briefing. Replies are cached, so replaying today's costs nothing.

```bash
daily-welcome --voices       # which backend and voice are actually in use
daily-welcome --test-voice   # say one line now
```

### Speed

Four things decide how long it takes to answer, and each is dealt with
differently:

| | |
|---|---|
| Waiting for you to stop talking | 0.9s of silence ends the command |
| Working out what you meant | Rule-based, so instant; only unrecognised phrasings go to Claude |
| Making the audio | The **fast model** (`eleven_flash_v2_5`) for replies; the better one only for the daily briefing, which nobody is waiting on |
| Playing it | Cached by phrase, so anything said before plays from disk |

`orbit warm` renders the lines Orbit says constantly — the greeting, "Done",
"Cancelled", "Sent" — so they never cost a network round trip. It runs
automatically on install and after `--set-key`.

Resolved contacts are cached too, since Contacts is slow to answer and slower
to launch.

### Saying things correctly

Speech engines mangle raw data in their own ways — `9:00 AM` as "nine
hundred", `August 31` as "August thirty one" — so nothing reaches the engine as
digits. Times become "nine thirty in the morning", dates "Monday the
thirty-first of August", counts "three reminders". Titles are stripped of
markdown, URLs collapse to "a link", `3pm` becomes `3 PM`.

Pause markup like `[[slnc 400]]` is deliberately unused: older Apple voices
obey it, newer neural ones read it out loud. Pacing comes from sentence
structure, which every engine handles.

### What the briefing sounds like

> *Welcome back, Arjun. Good morning, sir. It's eight forty-two in the morning,
> Monday the thirty-first of August. Three reminders due today, one overdue.
> Two events on the calendar. Four unread messages. Top of the list: Call the
> bank. That one is overdue. Next: Design review, at nine o'clock. Standing by.*

Short declaratives, no hedging. `WELCOME_HONORIFIC=""` drops the "sir",
`WELCOME_CLOSER` changes the sign-off, `WELCOME_SPEAK_MAX_ITEMS` sets how many
items get read.

## Talking to Orbit

Say the wake word, then the command. It chimes when it starts listening, and
the menu bar icon changes so an open microphone is never something you take on
trust. Recognition runs **on-device** — audio doesn't leave the Mac.

Say just **"Hey Orbit"** and it answers *"Hi Arjun. What can I do for you
today?"*, then keeps listening for about nine seconds so you can carry on
without saying the wake word again. Say nothing and it goes quiet without
comment. `ORBIT_GREETING` changes the line, `ORBIT_FOLLOWUP_SECONDS` the
window.

### Messages, Claude, Mail

```
Hey Orbit, message Mama saying I'm running late
Hey Orbit, text Priya saying dinner at eight

Hey Orbit, tell Claude to debug the flaky test in the dailyos repo
Hey Orbit, tell Claude on the dailyos mvp chat to fix the login flow

Hey Orbit, send an automated reply to all emails awaiting reply
             saying that I'm on vacation
```

Nicknames live in `~/.config/daily-welcome/contacts.conf` (`mama =
+15551234567`); anything not listed is looked up in Contacts by name. A name
that resolves to nobody stops the command — guessing who you meant is the one
failure worth refusing.

Claude jobs run detached in the repo you named, matched loosely, so "the
dailyos mvp development chat" finds `~/projects/dailyos-mvp`. The result waits
for you in the next briefing: *"Claude finished fixing the login flow in
dailyos."*

Email replies are **drafted first**. Orbit writes them into Mail, tells you how
many, and sends only on your yes. Delete a draft before answering and that one
stays unsent.

### Running it for free

Nothing here needs a paid account.

**Understanding and answering** already run through Claude Code, which is
covered by your Claude subscription. With no OpenAI key set at all, every
question, every bit of conversation and every command still works.

For something faster, any service speaking the OpenAI chat-completions
shape can stand in - two of them have free tiers:

```
ORBIT_OPENAI_BASE="https://api.groq.com/openai/v1"      console.groq.com
ORBIT_OPENAI_MODEL="llama-3.3-70b-versatile"

ORBIT_OPENAI_BASE="https://generativelanguage.googleapis.com/v1beta/openai"
ORBIT_OPENAI_MODEL="gemini-2.0-flash"                   aistudio.google.com

ORBIT_OPENAI_BASE="http://localhost:11434/v1"           entirely offline
ORBIT_OPENAI_MODEL="llama3.2"
```

The key goes in the same place whichever you pick: `daily-welcome
--set-openai-key`.

**The voice** has a free option too - `daily-welcome --setup-piper` fetches
a neural voice that runs on this Mac, with no key and no per-word cost.

### Remembering what happened

The transcript recorded what was *said*. It never recorded what was *done*,
so "who did I message earlier" had nothing to look at even though Orbit was
the one who sent it. Both are kept now, with timestamps.

```
you    who did I message earlier
orbit  Mama, about half an hour ago - you said you were running late.

you    what did we say about Priya
orbit  You asked what to get her for her birthday, and I emailed her about
       dinner at eight.
```

Only questions that point backwards - "did I", "earlier", "yesterday",
"remember", "last time" - go looking. Everything else is answered without
dragging history into it.

```
orbit memory events      what it has done for you
orbit memory show        what it remembers about you, and recent turns
orbit memory clear       forget all of it
```

### The web

```
search the web for the F1 results
google the weather in London
look up the population of Peru
what is the latest on the election
```

Paste or say a link and it reads the page instead:

```
summarise https://example.com
what does https://news.site/article say
```

Both take longer than an ordinary answer because they are doing real work.
"Open <link>" still just opens it in the browser.

### Which voice speaks

Two hosted services and a local fallback. `auto` prefers ElevenLabs, drops
to OpenAI, then to the best built-in macOS voice - so a service having a bad
day costs you the voice and never the briefing.

```
daily-welcome --voice-provider openai       speak through OpenAI
daily-welcome --voices                      what each service offers
daily-welcome --use-voice nova              pick one
daily-welcome --test-voice                  hear it, and see which said it
```

### Free voices that are not the default one

The voice macOS ships turned on is the worst one it has. Better ones are a
free download, no account:

```
daily-welcome --mac-voices                  what you have, and how to get more
daily-welcome --use-voice "Ava (Premium)"   pick one
daily-welcome --use-voice system            use the System Settings voice
```

System Settings > Accessibility > Spoken Content > System Voice > Manage
Voices. Ava, Zoe and Allison are the young expressive ones in English (US).
The Siri voices in that same list are the best of the lot, but `say` cannot
select them by name - set one as your System Voice and use
`--use-voice system`.

### Knowing who is speaking

Off by default, because it means keeping a few seconds of microphone audio
on disk - nothing is uploaded, but it is written down, which it was not
before.

```
daily-welcome --setup-speaker      installs it and turns it on
orbit voice enroll Arjun           say a couple of sentences when it asks
orbit voice who                    who was that last voice
orbit voice list                   everyone it knows
orbit voice ban Sam                refuse commands in that voice
orbit voice unban Sam
orbit voice forget Sam
```

Enrolling happens by talking, reusing the audio the listener already
keeps, so there is no recorder to install and the sample comes through the
same microphone as every command it will later be matched against. Enrol
two or three times, on different days, for a better match.

Once someone is enrolled it addresses them by name and knows that "my" and
"I" mean them, not the owner of the Mac.

Once somebody has enrolled, a voice it does not recognise is turned away:

> Hi! To continue using OrbitAI, please verify your voice with the DailyOS
> Team. Thank you!

Until the first person enrols it lets everyone through, or nobody could
ever enrol. And being unable to VERIFY is not the same as failing
verification - if the recording is missing or the recogniser is broken,
the command goes through anyway. A locked assistant with no way back in is
a worse failure than an unrecognised command getting answered.

```
ORBIT_SPEAKER_REQUIRE_ENROLLED=0    label voices, but let anyone speak
ORBIT_SPEAKER_UNKNOWN="..."         what a stranger hears
```

It is a recogniser, not a lock. Voices drift with a cold or a bad
microphone, and a recording of you sounds like you - so a ban refuses a
request, it does not secure anything. It answers "I don't know" rather
than guessing: below the confidence threshold it simply says nothing.

### Dropping a subject

"Forget that", "anyway", "new topic", "moving on", "forget about the
dentist" - and it is gone. The recent turns that ride along with every
question are cut at that point, so the subject cannot come back on its
own. The full record stays on disk, so "what did we say about X" can still
find it if you ask for it deliberately.

### Expression

The built-in voices are flat because nothing was asking them not to be.
`say` takes prosody commands nothing here used:

```
daily-welcome --expression 78     livelier  (the default)
daily-welcome --expression 115    animated
daily-welcome --expression 0      monotone
```

That is pitch modulation - how far the voice moves across a sentence, which
is the difference between reading and speaking. A neural or Siri voice does
its own prosody and may ignore it; that is a good sign, not a bad one.

### Pauses

A comma tells a reader to breathe and tells a speech engine to stop, and
they stop hard - which is most of what makes a synthetic voice sound
synthetic. The comma stays; the pause is shortened, using whatever each
engine offers (`[[slnc]]` for `say`, a break tag for ElevenLabs, and the
delivery instructions for OpenAI, which has no pause control).

```
WELCOME_PAUSE=short      default
WELCOME_PAUSE=natural    leave the text exactly as written
WELCOME_PAUSE=none       remove the commas altogether
WELCOME_PAUSE_MS=110     how long the shortened pause is
```
 A comma is
punctuation for a reader; a speech model treats it as a full stop, and the
constant pausing is most of what makes a synthetic voice sound synthetic.
What you see on screen keeps them. `WELCOME_TIGHTEN_SPEECH=0` turns it off.

OpenAI reuses the key already set for understanding what you say, so
switching costs nothing extra. Its voices are `alloy ash ballad coral echo
fable nova onyx sage shimmer`; `nova`, `coral` and `shimmer` are the
American female ones. `WELCOME_OPENAI_TTS_INSTRUCTIONS` steers the delivery
in plain English.

### While you're on a call

Orbit shuts the microphone the moment another app starts using it, and opens
it again when that app stops. Nothing is announced either way - an assistant
that says "going quiet" over your call has rather missed the point. If it was
mid-sentence when the call started, it stops talking.

It asks the only question that generalises: **is another process recording
right now**. That covers a relayed iPhone call, FaceTime, Zoom, Meet in a
browser tab, Teams, Discord, WhatsApp, a Slack huddle, and whatever gets
written next - where a list of app names would have been out of date the week
it was written. On macOS below 14.4 there is no per-process audio API, so it
falls back to a list of known call apps, which is less exact.

The daily briefing and the proactive alerts hold off too, so nothing talks
over the call. A briefing you were owed is given once the call ends.

Pressing Option-Space during a call overrides all of it for a minute: an
explicit ask always beats a guess about what you are doing.

```
ORBIT_PAUSE_ON_CALL=0     never mind, keep listening through calls
ORBIT_CALL_IGNORE=...     bundle ids that shouldn't count, comma separated
```

### Driving the Mac

| | |
|---|---|
| Sound | volume up / down / set volume to 40 / mute / louder |
| Quiet | stop talking / be quiet / shut up - stops the voice, not the Mac's sound |
| Ears | stop listening / leave me alone / go away, then wake up or listen again |
| Calls | nothing to say - it stops listening on its own while you're on one |
| Display | brighter, dimmer, dark mode, light mode |
| Music | play, pause, next song, previous track |
| Calls | call Mama, facetime Priya, call Mom on facetime audio, hang up |
| Apps | open Spotify, quit Slack, switch to Safari |
| Inside apps | in Safari click New Private Window, click Export in Keynote |
| Tabs & docs | new tab, close tab, reload, go back, save this |
| Windows | minimise, full screen, close this window, hide everything |
| System | lock my Mac, go to sleep, turn off the display, restart, shut down |
| Network | turn wifi on / off, bluetooth on / off (needs `blueutil`) |
| Files | take a screenshot, empty the trash, find the file taxes 2025 |
| Web | search for flights to Delhi, open https://… |
| Bits | what time is it, how much battery, read my clipboard, type hello |
| Making things | remind me to call the dentist, make a note saying buy milk, set a timer for 10 minutes |
| Reading back | brief me, what's on my calendar, read my messages, any new email, what did Claude do |
| Questions | how long do I boil an egg, what's the capital of Peru, explain this error |
| The screen | what's on my screen, what does this say, what's this error |
| Macros | whatever you name in macros.conf: "good night", "focus" |
| Emoji | message Mama saying happy birthday with a party emoji |

`orbit examples` prints this list on the machine.

**Calls** go out through FaceTime, and a plain phone call is relayed by your
iPhone (same as clicking a number in Contacts — the phone has to be nearby and
on the same Apple ID). FaceTime's "call this number?" panel is confirmed for
you; set `ORBIT_CALL_AUTOCONFIRM=0` to press it yourself. Orbit can't *answer*
an incoming call — macOS doesn't expose that.

**Inside apps**, "in Safari click New Private Window" clicks the actual menu
item, which is the general lever: anything an app puts in its menu bar can be
driven without a special case for that app.

### Anything else

If none of the above matches, Claude Code writes a one-line command for it,
Orbit reads back what it would do, and it runs only on your yes.

Two things bound that. Whole categories are refused outright no matter how the
sentence was phrased — `sudo`, disk utilities, `rm -rf`, piping the network
into a shell, keychain dumps — and nothing without a catalog entry ever runs
unconfirmed. Set `ORBIT_FREEFORM=0` to allow only the catalog.

### What gets confirmed

Reversible things happen on the word: volume, brightness, opening an app,
screenshots, timers. Confirming "volume up" out loud is slower than the key
would have been.

These are said back and wait for a yes: **sending a message**, **sending
email**, **dispatching Claude**, quitting an app, emptying the trash, turning
Wi-Fi off, sleep, restart, shut down, typing into whatever's focused, and every
freeform command. Say *no*, *cancel*, or *never mind* to drop it; say nothing
for twelve seconds and it drops itself. A confirmation also expires after ten
minutes, so a late "yes" can't fire an old command.

## The console

```bash
orbit console
```

Opens **OrbitAI** at `127.0.0.1:7717`: status of the app and the ears, every
setting worth changing, your people and macros, the ElevenLabs key and voice
list, a box to make it say something, and a box to run a command as though you
had said it out loud.

It binds to localhost only, and it reads and writes the same files the
assistant itself uses, so the console and the voice can never disagree about
what the settings are. Settings the app only reads at launch restart it for
you when changed.

## The menu bar item

| Item | |
|---|---|
| Listen Now | Skip the wake word, talk immediately |
| Listening for "hey orbit" | Toggle the microphone off entirely |
| Play Today's Briefing | Replay it, voice and all |
| Show / Speak Briefing Only | One half or the other |
| Stop Talking | Cuts playback immediately |
| Mute for Today | Nothing more until tomorrow |
| Greet Me Again Today | Forget that today's greeting happened |
| Edit Settings… / Open Log | `~/.config/daily-welcome/config.sh`, agent log |

## Permissions

macOS asks for each of these once, the first time it's needed:

| | For |
|---|---|
| Microphone, Speech Recognition | hearing "Hey Orbit" |
| Reminders, Calendar, Contacts | reading them, and adding to them |
| Mail, Messages, Notes, Music | reading and acting on your behalf |
| Accessibility | typing, window commands, media keys |

One it can't ask for: **reading Messages needs Full Disk Access**, added by
hand under System Settings → Privacy & Security → Full Disk Access → +
→ `~/Applications/DailyWelcome.app`. Without it, everything else still works
and the Messages section says so.

### "I allowed Reminders and it still says no"

Three things trip this up, all of them macOS rather than Orbit:

- **Look under Automation, not Reminders.** The Reminders switch governs apps
  reading the database directly. Driving the Reminders *app* through
  AppleScript is a separate grant, listed under Privacy & Security →
  Automation → *the app doing the asking* → Reminders.
- **Grants are per-asking-app.** Running `daily-welcome` in Terminal means
  Terminal is asking, so the approval attaches to Terminal. The menu bar app
  asks for its own, separately. Approving one does nothing for the other.
- **A refusal is remembered as firmly as an approval** — and a refused app
  often vanishes from the Automation list entirely, leaving no switch to flip
  back. `daily-welcome --reset-permissions` clears the remembered answers so
  the prompts come back.

Rebuilding the app also resets its permissions: an ad-hoc signature changes on
every build, and macOS reasonably treats that as a different app. `install.sh`
therefore only rebuilds when the sources actually changed; `--rebuild` forces
it, at the cost of re-approving.

## Settings

`~/.config/daily-welcome/config.sh`, plain bash, created on install from
`config.example.sh`.

| Setting | Default | |
|---|---|---|
| `WELCOME_NAME` | `Arjun` | what it calls you |
| `WELCOME_SECTIONS` | reminders calendar messages mail claude tasks | which sections, in order |
| `WELCOME_PRESENT` | `dialog` | `dialog`, `notification`, `both`, `stdout` |
| `WELCOME_EARLIEST_HOUR` | `5` | a 1am session isn't a new day |
| `WELCOME_ELEVEN_VOICE_NAME` | `Veda Sky` | looked up in your account |
| `ORBIT_LISTEN` | `1` | `0` never opens the microphone |
| `ORBIT_WAKE_WORD` | `hey orbit` | what wakes it |
| `ORBIT_REPO_ROOTS` | `~/projects ~/code …` | where Claude jobs look for repos |
| `ORBIT_CLAUDE_FLAGS` | `--permission-mode acceptEdits` | Claude runs headless, so it can't answer a prompt |
| `ORBIT_MAIL_AWAITING_DAYS` | `7` | how far back "awaiting reply" reaches |
| `ORBIT_MAIL_MAX_BATCH` | `25` | blast radius for one mail command |
| `ORBIT_FREEFORM` | `1` | `0` allows only the catalog |

## Commands

```
daily-welcome              the daily check (greets only once a day)
daily-welcome --force      greet now regardless
daily-welcome --print      the briefing as text, no voice
daily-welcome --status     what it thinks, and when it last ran
daily-welcome --set-key    ElevenLabs key into the Keychain
daily-welcome --test-voice speak one line, report which voice said it
daily-welcome --test       run the test suite (four seconds, no network)
daily-welcome --hush       stop talking right now

orbit console              the management console in a browser
orbit selftest             check every feature where it actually runs
orbit listen status        what the ears are doing
orbit listen heard         the last things it heard while waiting
orbit listen wake "..."    change the wake word
orbit listen alias "..."   accept another mishearing as the wake word
orbit listen pause         close the microphone (same as saying "stop listening")
orbit listen resume        open it again
orbit listen status        also says when a call has it on hold

orbit plan "<command>"     what it would do, as JSON
orbit run <token>          carry out a planned action
orbit say "<text>"         speak something in the Orbit voice
orbit examples             every phrasing it knows
```

## How "first time of the day" works

The app watches system wake, screen unlock, and a five-minute backstop timer.
Each asks the script whether today's greeting is still owed; a date stamp and a
lock file mean the three overlapping triggers still greet exactly once. It
waits until you've actually unlocked, so the greeting isn't spent on the lock
screen.

## Troubleshooting

**Start here:**

```bash
daily-welcome --doctor
```

It checks every part of the install — the app bundle, the login agent, the
running process, each permission, the voice, your repos — and prints the exact
command or click that fixes anything broken.

**There's no app and nothing ever asked for permissions.** Almost always
`swiftc` is missing, so the menu bar app was never built — and with no app,
there's nothing for macOS to prompt about. `xcode-select --install`, then
`./install.sh` again. Note the app is a menu bar item: it deliberately has no
Dock icon, doesn't appear in Launchpad, and lives in `~/Applications`, not
`/Applications`. Look for a small sun icon at the top right.

**Nothing happened this morning.** `daily-welcome --status` shows the last
greeting date; `launchctl list | grep dailywelcome` shows the agent;
`~/.local/state/daily-welcome/agent.log` has the rest.

**It used the wrong voice.** `daily-welcome --voices` names the backend in use.
If it says `say`, the key isn't readable or the voice name isn't in your
account — `--test-voice` prints the reason.

**It isn't hearing me.** Check the menu bar item says Listening, and that
Privacy & Security → Microphone and Speech Recognition both list DailyWelcome.
"Listen Now" skips the wake word, which separates a hearing problem from a
wake-word problem.

**It heard me but did the wrong thing.** `orbit plan "what you said"` prints
the interpretation without running it.

## Tests

```
tests/run              everything, about ten seconds
tests/run intents      just the suites whose names match
daily-welcome --test   the same thing, from anywhere
```

No network, no keys, no Mac: everything runs against a throwaway state
directory with the rules-only parser, so it is quick enough to run without
thinking about it. The website is driven in a real browser when Playwright
is installed, and skipped with a note when it is not. Every case in there is something that actually went
wrong once - `"did the pain go away?"` used to close the microphone, and
`"set a timer for two hours"` used to run for two minutes. `tests/README.md`
covers what each suite protects and how to add one.

## Uninstall

```bash
./uninstall.sh           # app, agent, commands
./uninstall.sh --purge   # also settings and state
```

## Layout

```
bin/daily-welcome       the briefing: gather, speak, show
bin/orbit               voice commands: plan, confirm, run
lib/config.sh           defaults, then your ~/.config override
lib/common.sh           timeouts, lock-screen check, small helpers
lib/sources.sh          reminders, calendar, tasks -> records
lib/messages.sh         unread iMessages (chat.db), and sending one
lib/mail.sh             unread mail, awaiting-reply, drafting, sending
lib/claude_jobs.sh      repo lookup, dispatching Claude, reporting back
lib/contacts.sh         nicknames and Contacts lookup
lib/system.sh           the Mac control catalog, graded by reversibility
lib/freeform.sh         Claude-written commands, denylist, confirmation
lib/intents.sh          sentence -> intent
lib/speech_text.sh      numbers, times, dates -> words a voice reads right
lib/tts_eleven.sh       ElevenLabs synthesis, caching, soft failure
lib/voice.sh            records -> spoken sentences, backend choice
lib/present.sh          records -> screen text, dialog, notification
lib/memory.sh           what was said and done, and dropping a subject
lib/slots.sh            the half-finished request, and its one question
lib/speaker.py          who is speaking: embeddings, matching, banning
tests/run               the whole test suite; see tests/README.md
menubar/main.swift      the menu bar app, wake and unlock triggers
menubar/listener.swift  wake word, command capture, yes/no loop
launchd/*.template      login agent, one per install mode
install.sh              build, install, load
```
