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

Out of the box it uses the best American female voice you have installed,
preferring the neural "Premium" ones, which sound markedly more real than the
old defaults:

```bash
daily-welcome --voices     # what's installed, and what it will use
```

If it reports plain `Samantha`, install a better one: **System Settings →
Accessibility → Spoken Content → System Voice → Manage Voices**, then download
**Ava (Premium)** or **Zoe (Premium)**. No config change needed — it picks the
best available one automatically.

What it actually says:

> *Welcome back, Arjun. Good morning, sir. It's 8:42 AM on Monday, August 31.
> You have 4 reminders due today, 1 of them overdue, and 2 events on the
> calendar. First up: Call the bank, which is overdue. Then, Design review, at
> 9:00 AM. Standing by.*

Drop the `sir` by setting `WELCOME_HONORIFIC=""` in your settings.

## The menu bar item

| Item | What it does |
|---|---|
| Play Today's Briefing | Replay the whole thing, voice and all |
| Show Briefing Only | The panel, silently |
| Speak Briefing Only | Just the voice |
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
| `WELCOME_SPEAK_RATE` | `168` | words per minute |
| `WELCOME_VOICE` | *(auto)* | pin one voice by name |
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
daily-welcome --voices     installed voices and the chosen one
daily-welcome --mute-today skip the rest of today
daily-welcome --reset      forget today's greeting
```

## Troubleshooting

**Nothing happened this morning.** `daily-welcome --status` shows the last
greeting date. Check the agent is loaded with
`launchctl list | grep dailywelcome`, and read `~/.local/state/daily-welcome/agent.log`.

**It shows reminders but says nothing.** `daily-welcome --voices` — if `say`
has no usable voice it falls back to the system default. Check that Spoken
Content has a voice downloaded.

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
lib/voice.sh            records -> spoken sentences, voice selection
menubar/main.swift      the menu bar agent (wake/unlock triggers)
launchd/*.template      login agent, one per install mode
install.sh              build, install, load
```
