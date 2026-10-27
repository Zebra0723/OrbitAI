# Orbit.app

A window onto Orbit: talk to it by typing, read every conversation and what Orbit
did along the way, manage what it remembers, see how you use it, and edit macros,
nicknames, and settings.

It reads Orbit's own files (`~/.local/state/daily-welcome`, `~/.config/daily-welcome`)
and runs the same `orbit` commands the menu bar app does, so it never drifts from
the voice side. The menu bar app is still what listens for "Hey Orbit"; this app
only adds a place to look and type.

Orbit only speaks when someone speaks to it. Typing in Talk counts; nothing else does.

## Design

Orbit looks like an instrument, not an app: graphite and off-white, hairline rules
instead of boxes, SF Pro Display for headlines and SF Mono for every label, time,
and index. There is one colour, the red on-air light, and it means exactly one
thing: Orbit is hearing you or working. The mark is a single ring with one body on
it, which travels the ring while Orbit is live.

## Build

Install Orbit first (`./install.sh` in `macos-daily-welcome`), then:

```sh
cd macos-daily-welcome/app
./build-app.sh --install
```

Requires Xcode (or the Swift toolchain) and macOS 14 or later. Signs with
`$ORBIT_SIGN_IDENTITY`, else `$NOVA_SIGN_IDENTITY`, else ad hoc.

## Pages

- **Talk**: type a command; anything Orbit would confirm out loud gets Do it / Cancel.
  "Speak" plays the answer in Orbit's voice.
- **Conversations**: every conversation, searchable, with "Show what Orbit did".
- **Memory**: the facts Orbit carries into conversations. Add, forget, or clear.
- **Stats**: how often and when you talk to it, and what it does for you.
- **Macros** and **People**: `macros.conf` and `contacts.conf` as editable rows.
- **Settings**: microphone on and off, a voice check, and the settings file.
