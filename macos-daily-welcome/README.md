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

### Driving the Mac

| | |
|---|---|
| Sound | volume up / down / set volume to 40 / mute / louder |
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
daily-welcome --hush       stop talking right now

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
menubar/main.swift      the menu bar app, wake and unlock triggers
menubar/listener.swift  wake word, command capture, yes/no loop
launchd/*.template      login agent, one per install mode
install.sh              build, install, load
```
