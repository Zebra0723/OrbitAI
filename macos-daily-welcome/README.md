# Daily Welcome

A menu bar agent for macOS that greets you **once a day**, the first time you
open your Mac. It says *"Welcome Arjun"* in an American female synthetic voice
and reads you a short briefing — reminders due today, what's on the calendar,
open tasks — while showing the same thing on screen.

It runs in the background from the menu bar. Nothing has to be open, no
Terminal window, no Dock icon. Close the lid, open it tomorrow morning, and it
speaks.

This is self-contained and unrelated to the rest of the repo; it just lives
here.

## Install

```bash
cd macos-daily-welcome
./install.sh
```

Then, to hear it immediately:

```bash
~/.local/bin/daily-welcome --force
```

The first run asks for a few permissions — Reminders, Calendar, and
controlling System Events so it can put the panel on screen. Allow them once
and it won't ask again.

If `swiftc` isn't installed (`xcode-select --install` gets it), the installer
skips the menu bar app and falls back to a background check every two minutes.
Same greeting, no icon.

## The voice

It speaks with your ElevenLabs voice — **Veda Sky** by default, at the same
settings your sample was rendered with (speed 1.00, stability 0.50, similarity
0.75, style 0, speaker boost on).

That voice is a hosted professional clone, so it needs your API key. Store it
once in the login Keychain:

```bash
daily-welcome --set-key      # paste the key; input is hidden
daily-welcome --test-voice   # confirms which voice actually spoke
```

The voice is looked up by name in your account, so add Veda Sky to your voices
in ElevenLabs first. To skip the lookup, put the id straight in your settings
as `WELCOME_ELEVEN_VOICE_ID`.

**Without a key it still works** — it falls back to the best built-in macOS
voice, so a missing key, dead network, or API error costs you the voice, never
the briefing. Each briefing is one short request, cached in
`~/.local/state/daily-welcome/cache`, so replaying today's costs nothing.

### Saying things correctly

Speech engines mangle raw data in their own ways — `9:00 AM` as "nine
hundred", `August 31` as "August thirty one" — so nothing reaches the engine
as digits. The briefing is written out in words first: times become "nine
thirty in the morning", dates "Monday the thirty-first of August", counts
"three reminders". Titles get cleaned too: markdown stripped, URLs collapsed
to "a link", `w/` to "with", `3pm` to "3 PM".

Pause markup like `[[slnc 400]]` is deliberately not used. Older Apple voices
obey it; the newer neural ones read it out loud. Pacing comes from sentence
structure instead, which every engine handles.

### What it actually says

> *Welcome back, Arjun. Good morning, sir. It's eight forty-two in the
> morning, Monday the thirty-first of August. Three reminders due today, one
> overdue. Two events on the calendar. Top of the list: Call the bank. That one
> is overdue. Next: Design review, at nine o'clock. Standing by.*

Short declaratives, no hedging. Times drop the "in the morning" tail when
it's already obvious from the current hour.

Tune the wording without touching code: `WELCOME_HONORIFIC=""` drops the
"sir", `WELCOME_CLOSER="Let's get to it."` changes the sign-off, and
`WELCOME_SPEAK_MAX_ITEMS` sets how many items get read.

## The menu bar item

| Item | What it does |
|---|---|
| Play Today's Briefing | Replay the whole thing, voice and all |
| Show Briefing Only | The panel, silently |
| Speak Briefing Only | Just the voice |
| Stop Talking | Cuts playback immediately |
| Mute for Today | Nothing more until tomorrow |
| Greet Me Again Today | Forget that today's greeting happened |
| Edit Settings… | Opens `~/.config/daily-welcome/config.sh` |
| Open Log | The agent log |

## Settings

Everything lives in `~/.config/daily-welcome/config.sh` (plain bash, created on
install from `config.example.sh`). The ones worth knowing:

| Setting | Default | |
|---|---|---|
| `WELCOME_NAME` | `Arjun` | what it calls you |
| `WELCOME_HONORIFIC` | `sir` | how the voice addresses you |
| `WELCOME_SPEAK` | `1` | `0` for silent |
| `WELCOME_CLOSER` | `Standing by.` | the sign-off |
| `WELCOME_TTS` | `auto` | `elevenlabs`, `say`, or `auto` |
| `WELCOME_ELEVEN_VOICE_NAME` | `Veda Sky` | looked up in your account |
| `WELCOME_ELEVEN_STABILITY` | `0.5` | lower is more expressive, higher steadier |
| `WELCOME_VOICE` | *(auto)* | pin the fallback macOS voice |
| `WELCOME_PRESENT` | `dialog` | `dialog`, `notification`, `both`, `stdout` |
| `WELCOME_SECTIONS` | `reminders calendar tasks` | which sections, in order |
| `WELCOME_TASKS_FILE` | `~/todo.md` | markdown checkboxes; unchecked ones show up |
| `WELCOME_EARLIEST_HOUR` | `5` | a 1am session doesn't count as a new day |

Calendar events come from [`icalBuddy`](https://hasseg.org/icalBuddy/) when
it's installed (`brew install ical-buddy`) — it's much faster than asking
Calendar.app. Without it, that section is quietly skipped unless you set
`WELCOME_CALENDAR_APPLESCRIPT=1`.

## How "first time of the day" works

The menu bar app watches three signals: system wake, screen unlock, and a
five-minute backstop timer for anything it misses. Each one asks the script
whether today's greeting is still owed. The script keeps a date stamp in
`~/.local/state/daily-welcome/last-run` and refuses to greet twice, so the
triple coverage never means a double greeting.

Two guards keep it from firing at the wrong moment: it waits until you've
actually unlocked the screen, so the greeting isn't spent on the lock screen,
and it won't treat a session before 5am as a new day.

## Commands

```
daily-welcome              run the daily check (greets only once a day)
daily-welcome --force      greet now regardless
daily-welcome --preview    greet now without using up today's greeting
daily-welcome --print      print the briefing as text, no voice, no dialog
daily-welcome --status     what it thinks, and when it last ran
daily-welcome --set-key    store your ElevenLabs key in the Keychain
daily-welcome --test-voice speak one line and report which voice said it
daily-welcome --voices     available voices and the chosen one
daily-welcome --hush       stop talking right now
daily-welcome --mute-today skip the rest of today
daily-welcome --reset      forget today's greeting
```

## Troubleshooting

**Nothing happened this morning.** `daily-welcome --status` shows the last
greeting date. Check the agent is loaded with
`launchctl list | grep dailywelcome`, and read `~/.local/state/daily-welcome/agent.log`.

**It used the wrong voice.** `daily-welcome --voices` shows the backend in
use. If it says `say`, the key isn't readable or the voice name isn't in your
account — `--test-voice` prints the reason, and the agent log has the HTTP
status from ElevenLabs.

**"No access to Reminders yet."** macOS asked and got a no. Re-allow under
System Settings → Privacy & Security → Reminders (and Calendars), enabling
`DailyWelcome`.

## Uninstall

```bash
./uninstall.sh           # removes the app, agent, and command
./uninstall.sh --purge   # also removes settings and state
```

## Layout

```
bin/daily-welcome       the briefing itself: gather, speak, show
lib/config.sh           defaults, then your ~/.config override
lib/common.sh           timeouts, lock-screen check, small helpers
lib/sources.sh          reminders, calendar, tasks -> tab-separated records
lib/present.sh          records -> screen text, dialog, notification
lib/speech_text.sh      numbers, times and dates -> words a voice reads right
lib/tts_eleven.sh       ElevenLabs synthesis, caching, and soft failure
lib/voice.sh            records -> spoken sentences, backend choice
menubar/main.swift      the menu bar agent (wake/unlock triggers)
launchd/*.template      login agent, one per install mode
install.sh              build, install, load
```
