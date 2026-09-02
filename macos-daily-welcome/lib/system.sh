#!/bin/bash
# Controlling the Mac itself.
#
# Every action is a named entry here rather than a command assembled at
# runtime, so what Orbit can do is a list you can read. Actions are graded:
# the reversible ones happen on the word, the rest get said back and wait
# for a yes.

# ------------------------------------------------------------ classification

# Needs a spoken confirmation first?
system_needs_confirm() {
  case "$1" in
    quit_app|empty_trash|restart|shut_down|sleep_mac|wifi_off|type_text|freeform)
      return 0 ;;
    call_phone|call_audio|call_video)
      # Ringing the wrong person is not something you can take back.
      [ "$ORBIT_CONFIRM_CALLS" = "1" ] && return 0 || return 1 ;;
    *) return 1 ;;
  esac
}

# What Orbit says: a question for the confirm actions, a statement for the rest.
system_describe() {
  local action="$1" arg="${2:-}"
  case "$action" in
    quit_app)     printf 'Quit %s?' "$arg" ;;
    empty_trash)  printf 'Empty the trash?' ;;
    restart)      printf 'Restart the Mac?' ;;
    shut_down)    printf 'Shut the Mac down?' ;;
    sleep_mac)    printf 'Put the Mac to sleep?' ;;
    wifi_off)     printf 'Turn Wi-Fi off?' ;;
    type_text)    printf 'Type "%s" into whatever is in front?' "$arg" ;;
    freeform)     printf '%s Go ahead?' "$arg" ;;
    call_phone)   printf 'Call %s?' "$arg" ;;
    call_audio)   printf 'FaceTime audio %s?' "$arg" ;;
    call_video)   printf 'FaceTime %s?' "$arg" ;;
    *)            printf 'On it.' ;;
  esac
}

# ------------------------------------------------------------------ helpers

_osa() { osascript -e "$1" >/dev/null 2>&1; }

_key_code() { _osa "tell application \"System Events\" to key code $1"; }

# Music first, then Spotify, then the media key as a last resort.
_media() {
  local verb="$1" key="$2"
  if pgrep -xq Music 2>/dev/null && _osa "tell application \"Music\" to $verb"; then return 0; fi
  if pgrep -xq Spotify 2>/dev/null && _osa "tell application \"Spotify\" to $verb"; then return 0; fi
  _key_code "$key"
}

_wifi_device() {
  networksetup -listallhardwareports 2>/dev/null \
    | awk '/Wi-Fi|AirPort/ { getline; print $2; exit }'
}

_wifi_power() {
  local state="$1" device
  device="$(_wifi_device)"
  [ -z "$device" ] && return 1
  networksetup -setairportpower "$device" "$state" >/dev/null 2>&1
}

# --------------------------------------------------------------- the actions

# system_run ACTION ARG -> prints the sentence to say back
system_run() {
  local action="$1" arg="${2:-}"
  case "$action" in
    volume_set)
      _osa "set volume output volume $arg"
      printf 'Volume %s.' "$(num_word "$arg")" ;;
    volume_up)
      _osa 'set volume output volume (output volume of (get volume settings) + 12)'
      printf 'Volume up.' ;;
    volume_down)
      _osa 'set volume output volume (output volume of (get volume settings) - 12)'
      printf 'Volume down.' ;;
    mute)   _osa 'set volume with output muted';    printf 'Muted.' ;;
    unmute) _osa 'set volume without output muted'; printf 'Sound back on.' ;;

    brightness_up)   _key_code 144; printf 'Brighter.' ;;
    brightness_down) _key_code 145; printf 'Dimmer.' ;;

    dark_mode_on)
      _osa 'tell application "System Events" to tell appearance preferences to set dark mode to true'
      printf 'Dark mode on.' ;;
    dark_mode_off)
      _osa 'tell application "System Events" to tell appearance preferences to set dark mode to false'
      printf 'Light mode on.' ;;

    playpause)  _media playpause 16;         printf 'Done.' ;;
    next_track) _media "next track" 17;      printf 'Next.' ;;
    prev_track) _media "previous track" 18;  printf 'Back one.' ;;

    open_app)
      if open -a "$arg" 2>/dev/null; then printf '%s is open.' "$arg"
      else printf "I couldn't find an app called %s." "$arg"; fi ;;
    quit_app)
      _osa "tell application \"$arg\" to quit"; printf 'Quit %s.' "$arg" ;;
    switch_app)
      _osa "tell application \"$arg\" to activate"; printf '%s is in front.' "$arg" ;;

    open_url)
      open "$arg" >/dev/null 2>&1; printf 'Opened.' ;;
    web_search)
      open "$ORBIT_SEARCH_URL$(printf '%s' "$arg" | sed -e 's/ /+/g')" >/dev/null 2>&1
      printf 'Searching for %s.' "$arg" ;;

    screenshot)
      screencapture -x "$HOME/Desktop/Screenshot $(date '+%Y-%m-%d at %H.%M.%S').png" 2>/dev/null
      printf 'Saved to your desktop.' ;;

    lock)
      _osa 'tell application "System Events" to keystroke "q" using {command down, control down}'
      printf 'Locked.' ;;
    sleep_display) pmset displaysleepnow 2>/dev/null; printf 'Display off.' ;;
    sleep_mac)     pmset sleepnow 2>/dev/null;        printf 'Good night.' ;;
    restart)       _osa 'tell application "System Events" to restart';   printf 'Restarting.' ;;
    shut_down)     _osa 'tell application "System Events" to shut down'; printf 'Shutting down.' ;;

    wifi_on)  _wifi_power on  && printf 'Wi-Fi on.'  || printf "I couldn't find the Wi-Fi adapter." ;;
    wifi_off) _wifi_power off && printf 'Wi-Fi off.' || printf "I couldn't find the Wi-Fi adapter." ;;

    bluetooth_on|bluetooth_off)
      if have_cmd blueutil; then
        if [ "$action" = "bluetooth_on" ]; then
          blueutil --power 1 >/dev/null 2>&1; printf 'Bluetooth on.'
        else
          blueutil --power 0 >/dev/null 2>&1; printf 'Bluetooth off.'
        fi
      else
        printf 'Bluetooth needs blueutil. Install it with brew install blueutil.'
      fi ;;

    empty_trash)
      _osa 'tell application "Finder" to empty trash'; printf 'Trash emptied.' ;;

    battery)
      local pct state
      pct="$(pmset -g batt 2>/dev/null | grep -o '[0-9]\{1,3\}%' | head -1 | tr -d '%')"
      if pmset -g batt 2>/dev/null | grep -q 'AC Power'; then state="and charging"; else state="on battery"; fi
      if [ -n "$pct" ]; then printf 'Battery is at %s percent, %s.' "$(num_word "$pct")" "$state"
      else printf "I couldn't read the battery."; fi ;;

    time_now)
      printf "It's %s, %s." "$(now_words)" "$(today_words)" ;;

    new_note)
      arg="$(emoji_expand "$arg")"
      osascript - "$arg" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  tell application "Notes"
    make new note at folder 1 of account 1 with properties {body:(item 1 of argv)}
  end tell
end run
APPLESCRIPT
      printf 'Noted.' ;;

    add_reminder)
      arg="$(emoji_expand "$arg")"
      osascript - "$arg" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  tell application "Reminders"
    make new reminder with properties {name:(item 1 of argv)}
  end tell
end run
APPLESCRIPT
      printf 'Added to your reminders.' ;;

    timer)
      # A backgrounded subshell keeps the parent's command substitution
      # open until it finishes - so a five-minute timer meant a five-minute
      # wait for the reply confirming it. nohup on a separate process image
      # detaches properly.
      # The argument is seconds. It used to be minutes, which made "two
      # hours" a two minute timer and "thirty seconds" a thirty minute one.
      if [ -x "$ORBIT_BIN" ]; then
        nohup "$ORBIT_BIN" timer-fire "$arg" </dev/null >/dev/null 2>&1 &
      else
        nohup /bin/bash -c "sleep $arg" </dev/null >/dev/null 2>&1 &
      fi
      printf 'Timer set for %s.' "$(duration_words "$arg")" ;;

    type_text)
      arg="$(emoji_expand "$arg")"
      osascript - "$arg" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  tell application "System Events" to keystroke (item 1 of argv)
end run
APPLESCRIPT
      printf 'Typed.' ;;

    copy_text)
      arg="$(emoji_expand "$arg")"
      printf '%s' "$arg" | pbcopy 2>/dev/null; printf 'Copied.' ;;
    read_clipboard)
      local clip
      clip="$(pbpaste 2>/dev/null | head -c 400)"
      if [ -n "$clip" ]; then printf 'Clipboard says: %s' "$(speech_clean "$clip")"
      else printf 'The clipboard is empty.'; fi ;;

    find_file)
      local hits count
      hits="$(mdfind -name "$arg" 2>/dev/null | head -3)"
      count="$(printf '%s' "$hits" | grep -c .)"
      if [ "$count" -eq 0 ]; then
        printf 'Nothing found for %s.' "$arg"
      else
        open -R "$(printf '%s' "$hits" | head -1)" >/dev/null 2>&1
        printf 'Found %s. The first one is showing in Finder.' "$(num_word "$count")"
      fi ;;

    # --- calls ---
    # macOS dials through FaceTime; a phone call is handed to your iPhone.
    # FaceTime puts up a confirmation panel, which is dismissed with Return
    # unless you'd rather press it yourself (ORBIT_CALL_AUTOCONFIRM=0).
    call_phone|call_audio|call_video)
      local scheme
      case "$action" in
        call_phone) scheme="tel:" ;;
        call_audio) scheme="facetime-audio:" ;;
        call_video) scheme="facetime:" ;;
      esac
      open "$scheme$arg" >/dev/null 2>&1
      if [ "$ORBIT_CALL_AUTOCONFIRM" = "1" ]; then
        sleep 3
        _osa 'tell application "System Events" to key code 36'
      fi
      printf 'Calling.' ;;

    drop_subject)
      # Everything that could carry the old topic into the next turn.
      memory_drop_subject 2>/dev/null
      context_forget 2>/dev/null
      slot_clear 2>/dev/null
      printf "Dropped. What's next?" ;;

    stop_talking)
      hush
      printf '' ;;   # nothing to say; saying it would defeat the point

    stop_listening)
      # A file the listener watches, rather than killing the app: the
      # menu, the hot key and the console all still work, so there is
      # always a way back.
      mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
      : > "$WELCOME_STATE_DIR/paused"
      printf 'Going quiet. Option Space when you want me.' ;;

    start_listening)
      rm -f "$WELCOME_STATE_DIR/paused"
      printf 'Listening again.' ;;

    end_call)
      if pgrep -xq FaceTime 2>/dev/null; then
        _osa 'tell application "FaceTime" to quit'
        printf 'Hung up.'
      else
        printf "There's no call to end."
      fi ;;

    # --- app control ---
    # Clicking a named menu item is the general lever: anything an app puts
    # in its menu bar can be driven without a per-app special case.
    app_menu)
      local app_name menu_item
      app_name="${arg%%|*}"
      menu_item="${arg#*|}"
      if osascript - "$app_name" "$menu_item" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set appName to item 1 of argv
  set wanted to item 2 of argv
  tell application appName to activate
  delay 0.4
  tell application "System Events"
    tell process appName
      repeat with m in menu bar items of menu bar 1
        try
          repeat with i in menu items of menu 1 of m
            if (name of i as string) is wanted then
              click i
              return
            end if
          end repeat
        end try
      end repeat
      error "no such menu item"
    end tell
  end tell
end run
APPLESCRIPT
      then
        printf '%s in %s.' "$menu_item" "$app_name"
      else
        printf "I couldn't find a %s item in %s's menus." "$menu_item" "$app_name"
      fi ;;

    new_tab)      _osa 'tell application "System Events" to keystroke "t" using command down'; printf 'New tab.' ;;
    close_tab)    _osa 'tell application "System Events" to keystroke "w" using command down'; printf 'Closed.' ;;
    reload_page)  _osa 'tell application "System Events" to keystroke "r" using command down'; printf 'Reloading.' ;;
    go_back)      _osa 'tell application "System Events" to keystroke "[" using command down'; printf 'Back.' ;;
    save)         _osa 'tell application "System Events" to keystroke "s" using command down'; printf 'Saved.' ;;

    play_spotify)
      open "spotify:search:$(printf '%s' "$arg" | sed -e 's/ /%20/g')" >/dev/null 2>&1
      printf 'Looking up %s in Spotify.' "$arg" ;;

    minimize)     _osa 'tell application "System Events" to keystroke "m" using command down'; printf 'Minimised.' ;;
    fullscreen)   _osa 'tell application "System Events" to keystroke "f" using {command down, control down}'; printf 'Full screen.' ;;
    close_window) _osa 'tell application "System Events" to keystroke "w" using command down'; printf 'Closed.' ;;
    hide_others)  _osa 'tell application "System Events" to keystroke "h" using {command down, option down}'; printf 'Hidden.' ;;

    freeform)
      local out
      out="$(run_with_timeout "$ORBIT_FREEFORM_TIMEOUT" /bin/bash -c "$arg" 2>&1 | head -c 300)"
      if [ -n "$out" ]; then printf 'Done. %s' "$(speech_clean "$out")"
      else printf 'Done.'; fi ;;

    *) printf "I don't know how to do that one yet." ;;
  esac
}
