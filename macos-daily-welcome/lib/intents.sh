#!/bin/bash
# Turning a spoken sentence into an intent.
#
# Rules first, because they're predictable and instant, and a voice command
# that behaves differently on Tuesday is worse than one that doesn't fire.
# Anything the rules don't recognize can be handed to Claude Code as a
# fallback classifier, if it's installed.
#
# Output is one tab-separated line: intent <TAB> arg1 <TAB> arg2

# ---------------------------------------------------------------- helpers

# Splits "<who> saying <what>" on the first separator that appears.
_split_on() {
  awk -v text="$1" -v seps="$2" 'BEGIN {
    n = split(seps, s, "|")
    lower = tolower(text)
    best = 0; blen = 0
    for (i = 1; i <= n; i++) {
      p = index(lower, tolower(s[i]))
      if (p > 0 && (best == 0 || p < best)) { best = p; blen = length(s[i]) }
    }
    if (best == 0) exit 1
    left = substr(text, 1, best - 1)
    right = substr(text, best + blen)
    gsub(/^[ \t,."]+|[ \t,."]+$/, "", left)
    gsub(/^[ \t,:"]+|[ \t"]+$/, "", right)
    printf "%s\t%s\n", left, right
  }'
}

# Strips a leading verb phrase; fails if the text doesn't start with one.
_strip_prefix() {
  awk -v text="$1" -v pattern="$2" 'BEGIN {
    lower = tolower(text)
    if (match(lower, pattern)) {
      rest = substr(text, RSTART + RLENGTH)
      gsub(/^[ \t,]+/, "", rest)
      print rest
    } else exit 1
  }'
}

_trim_repo_words() {
  printf '%s' "$1" | sed -E 's/^(the|my)[[:space:]]+//I; s/[[:space:]]+(repo|repository|project|chat|codebase)$//I' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

# "that I'm on vacation" reads better as "I'm on vacation".
_trim_that() {
  printf '%s' "$1" | sed -E 's/^(that|saying)[[:space:]]+//I'
}

# ---------------------------------------------------------------- intents

_try_message() {
  local text="$1" rest pair
  rest="$(_strip_prefix "$text" "^[[:space:]]*(please[[:space:]]+)?(can[[:space:]]+you[[:space:]]+)?(send[[:space:]]+(a[[:space:]]+)?)?(message|text|imessage|write)[[:space:]]+(to[[:space:]]+)?")" || return 1
  pair="$(_split_on "$rest" " saying that | saying | that says | telling them | and say |: ")" || return 1
  printf 'message\t%s\n' "$pair"
}

_try_claude() {
  local text="$1" rest pair repo task
  rest="$(_strip_prefix "$text" "^[[:space:]]*(please[[:space:]]+)?(tell|ask|have|get|send)[[:space:]]+claude[[:space:]]+")" || return 1

  # "on the dailyos chat to debug"  ->  repo first, task second
  if pair="$(_strip_prefix "$rest" "^(on|in|about|for)[[:space:]]+")"; then
    if pair="$(_split_on "$pair" " to ")"; then
      repo="$(_trim_repo_words "$(printf '%s' "$pair" | cut -f1)")"
      task="$(printf '%s' "$pair" | cut -f2)"
      printf 'claude\t%s\t%s\n' "$repo" "$task"
      return 0
    fi
  fi

  # "to debug the dailyos repo"  ->  task first, repo second
  if rest="$(_strip_prefix "$rest" "^to[[:space:]]+")"; then
    if pair="$(_split_on_last "$rest" " in the | on the | in | on ")"; then
      task="$(printf '%s' "$pair" | cut -f1)"
      repo="$(_trim_repo_words "$(printf '%s' "$pair" | cut -f2)")"
      printf 'claude\t%s\t%s\n' "$repo" "$task"
      return 0
    fi
    # No repo named: fall back to the default one, if configured.
    if [ -n "$ORBIT_DEFAULT_REPO" ]; then
      printf 'claude\t%s\t%s\n' "$ORBIT_DEFAULT_REPO" "$rest"
      return 0
    fi
  fi
  return 1
}

# Like _split_on but takes the last match, for "<task> in <repo>" where the
# task itself may contain "in".
_split_on_last() {
  awk -v text="$1" -v seps="$2" 'BEGIN {
    n = split(seps, s, "|")
    lower = tolower(text)
    best = 0; blen = 0
    for (i = 1; i <= n; i++) {
      start = 1
      while ((p = index(substr(lower, start), tolower(s[i]))) > 0) {
        abs = start + p - 1
        if (abs > best) { best = abs; blen = length(s[i]) }
        start = abs + 1
      }
    }
    if (best == 0) exit 1
    left = substr(text, 1, best - 1)
    right = substr(text, best + blen)
    gsub(/^[ \t,."]+|[ \t,."]+$/, "", left)
    gsub(/^[ \t,."]+|[ \t,."]+$/, "", right)
    printf "%s\t%s\n", left, right
  }'
}

_try_mail_reply() {
  local text="$1" lower body
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    *repl*) ;;
    *) return 1 ;;
  esac
  case "$lower" in
    *email*|*mail*|*inbox*) ;;
    *) return 1 ;;
  esac
  case "$lower" in
    *awaiting*|*waiting*|*unanswered*|*"haven't answered"*|*"need a reply"*) ;;
    *) return 1 ;;
  esac

  body="$(_split_on "$text" " saying " | cut -f2)"
  [ -z "$body" ] && return 1
  printf 'mail_reply\t%s\n' "$(_trim_that "$body")"
}

# Everything after the first match of any of these words.
_after() {
  awk -v text="$1" -v key="$2" 'BEGIN {
    p = index(tolower(text), tolower(key))
    if (p == 0) exit 1
    rest = substr(text, p + length(key))
    gsub(/^[ \t,:."]+|[ \t,."]+$/, "", rest)
    if (rest == "") exit 1
    print rest
  }'
}

_first_number() {
  printf '%s' "$1" | sed -nE 's/.*[^0-9]([0-9]{1,3})([^0-9].*|$)/\1/p; t; s/^([0-9]{1,3})([^0-9].*|$)/\1/p' | head -1
}

# Calls. Anchored to the start of the sentence so "remind me to call the
# dentist" stays a reminder.
_try_call() {
  local text="$1" lower rest kind="call_phone"
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    "call "*|"phone "*|"ring "*)                      kind="call_phone" ;;
    "facetime "*|"face time "*)                       kind="call_video" ;;
    "video call "*|"video chat "*)                    kind="call_video" ;;
    "audio call "*)                                   kind="call_audio" ;;
    *) return 1 ;;
  esac

  rest="$(printf '%s' "$text" | sed -E 's/^[[:space:]]*(call|phone|ring|facetime|face time|video call|video chat|audio call)[[:space:]]+//I')"

  # A trailing "on FaceTime" / "on video" picks the kind instead.
  case "$(printf '%s' "$rest" | tr '[:upper:]' '[:lower:]')" in
    *"on facetime audio"*) kind="call_audio" ;;
    *"on facetime"*|*"on video"*) kind="call_video" ;;
    *"on the phone"*|*"on their cell"*|*"on his cell"*|*"on her cell"*) kind="call_phone" ;;
  esac
  rest="$(printf '%s' "$rest" | sed -E 's/[[:space:]]+on (facetime audio|facetime|video|the phone|their cell|his cell|her cell)$//I')"
  rest="$(printf '%s' "$rest" | sed -E 's/^(back[[:space:]]+)?//I; s/[[:space:]]+$//')"

  [ -z "$rest" ] && return 1
  printf 'call\t%s\t%s\n' "$rest" "$kind"
}

# Controlling the Mac. Ordered so the specific phrasings win: "read my
# clipboard" is a clipboard command, not a request to read something out.
_try_system() {
  local text="$1" lower arg
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    "set volume to "*|"set the volume to "*|"volume "[0-9]*)
      arg="$(_first_number "$lower")"
      [ -n "$arg" ] && { printf 'system\tvolume_set\t%s\n' "$arg"; return 0; } ;;
  esac

  case "$lower" in
    *"volume up"*|*louder*|*"turn it up"*|*"turn up the volume"*) printf 'system\tvolume_up\t\n'; return 0 ;;
    *"volume down"*|*quieter*|*"turn it down"*|*"turn down the volume"*) printf 'system\tvolume_down\t\n'; return 0 ;;
    "mute"*|*"mute the"*|*"be quiet"*|*"shut up"*) printf 'system\tmute\t\n'; return 0 ;;
    *unmute*|*"sound back"*) printf 'system\tunmute\t\n'; return 0 ;;

    *brighter*|*"brightness up"*|*"turn up the brightness"*) printf 'system\tbrightness_up\t\n'; return 0 ;;
    *dimmer*|*"brightness down"*|*"turn down the brightness"*) printf 'system\tbrightness_down\t\n'; return 0 ;;

    *"dark mode"*) printf 'system\tdark_mode_on\t\n'; return 0 ;;
    *"light mode"*) printf 'system\tdark_mode_off\t\n'; return 0 ;;

    *"next track"*|*"next song"*|*"skip this"*|"skip"*) printf 'system\tnext_track\t\n'; return 0 ;;
    *"previous track"*|*"previous song"*|*"go back a song"*) printf 'system\tprev_track\t\n'; return 0 ;;
    "play"|"pause"|*"play music"*|*"pause the music"*|*"resume music"*) printf 'system\tplaypause\t\n'; return 0 ;;

    *"take a screenshot"*|"screenshot"*|*"screen shot"*) printf 'system\tscreenshot\t\n'; return 0 ;;
    *"lock the screen"*|*"lock my mac"*|*"lock the mac"*|"lock"*) printf 'system\tlock\t\n'; return 0 ;;
    *"turn off the display"*|*"turn off the screen"*|*"screen off"*) printf 'system\tsleep_display\t\n'; return 0 ;;
    *"go to sleep"*|*"sleep the mac"*|*"put the mac to sleep"*) printf 'system\tsleep_mac\t\n'; return 0 ;;
    *"restart the mac"*|*"reboot"*) printf 'system\trestart\t\n'; return 0 ;;
    *"shut down the mac"*|*"shutdown the mac"*|*"power off"*) printf 'system\tshut_down\t\n'; return 0 ;;

    *"wifi on"*|*"wi-fi on"*|*"turn on wifi"*|*"turn on the wifi"*|*"turn wifi on"*) printf 'system\twifi_on\t\n'; return 0 ;;
    *"wifi off"*|*"wi-fi off"*|*"turn off wifi"*|*"turn off the wifi"*|*"turn wifi off"*) printf 'system\twifi_off\t\n'; return 0 ;;
    *"bluetooth on"*|*"turn on bluetooth"*) printf 'system\tbluetooth_on\t\n'; return 0 ;;
    *"bluetooth off"*|*"turn off bluetooth"*) printf 'system\tbluetooth_off\t\n'; return 0 ;;

    *"empty the trash"*|*"empty trash"*) printf 'system\tempty_trash\t\n'; return 0 ;;
    *battery*) printf 'system\tbattery\t\n'; return 0 ;;
    *"what time is it"*|*"what's the time"*|*"whats the time"*|*"what's the date"*|*"what day is it"*)
      printf 'system\ttime_now\t\n'; return 0 ;;

    *minimi[sz]e*) printf 'system\tminimize\t\n'; return 0 ;;
    *"full screen"*|*fullscreen*) printf 'system\tfullscreen\t\n'; return 0 ;;
    *"close this window"*|*"close the window"*) printf 'system\tclose_window\t\n'; return 0 ;;
    *"hide everything"*|*"hide the others"*|*"hide other"*) printf 'system\thide_others\t\n'; return 0 ;;

    *"read my clipboard"*|*"what's on my clipboard"*|*"whats on my clipboard"*|*"read the clipboard"*)
      printf 'system\tread_clipboard\t\n'; return 0 ;;

    *"hang up"*|*"end the call"*|*"end call"*) printf 'system\tend_call\t\n'; return 0 ;;

    *"new tab"*)                          printf 'system\tnew_tab\t\n'; return 0 ;;
    *"close tab"*|*"close this tab"*)     printf 'system\tclose_tab\t\n'; return 0 ;;
    *"reload"*|*"refresh the page"*|*"refresh this"*) printf 'system\treload_page\t\n'; return 0 ;;
    *"go back"*)                          printf 'system\tgo_back\t\n'; return 0 ;;
    *"save this"*|*"save the file"*)      printf 'system\tsave\t\n'; return 0 ;;
  esac

  # "in Safari click New Private Window" - the general lever for app control.
  if printf '%s' "$lower" | grep -qE '^in [a-z0-9 .]+ (click|choose|select|hit|press) '; then
    local app_part item_part
    app_part="$(printf '%s' "$text" | sed -E 's/^[Ii]n[[:space:]]+//; s/[[:space:]]+(click|choose|select|hit|press)[[:space:]]+.*$//')"
    item_part="$(printf '%s' "$text" | sed -E 's/^.*[[:space:]](click|choose|select|hit|press)[[:space:]]+//')"
    if [ -n "$app_part" ] && [ -n "$item_part" ]; then
      printf 'system\tapp_menu\t%s|%s\n' "$app_part" "$item_part"; return 0
    fi
  fi
  # "click New Private Window in Safari" - the same thing, said the other way.
  if printf '%s' "$lower" | grep -qE '^(click|choose|select) .+ in [a-z0-9 .]+$'; then
    local app_part item_part
    item_part="$(printf '%s' "$text" | sed -E 's/^(click|choose|select)[[:space:]]+//I; s/[[:space:]]+in[[:space:]]+[^[:space:]]+$//')"
    app_part="$(printf '%s' "$text" | sed -E 's/^.*[[:space:]]in[[:space:]]+//')"
    if [ -n "$app_part" ] && [ -n "$item_part" ]; then
      printf 'system\tapp_menu\t%s|%s\n' "$app_part" "$item_part"; return 0
    fi
  fi

  if arg="$(_after "$text" "play ")"; then
    case "$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')" in
      *"on spotify"*)
        arg="$(printf '%s' "$arg" | sed -E 's/[[:space:]]+on spotify$//I')"
        printf 'system\tplay_spotify\t%s\n' "$arg"; return 0 ;;
    esac
  fi

  # Commands with an argument.
  if arg="$(_after "$text" "set a timer for ")" || arg="$(_after "$text" "timer for ")"; then
    arg="$(_first_number "$arg")"
    [ -n "$arg" ] && { printf 'system\ttimer\t%s\n' "$arg"; return 0; }
  fi
  if arg="$(_after "$text" "remind me to ")"; then
    printf 'system\tadd_reminder\t%s\n' "$arg"; return 0
  fi
  if arg="$(_after "$text" "make a note saying ")" || arg="$(_after "$text" "note that ")" \
     || arg="$(_after "$text" "take a note ")"; then
    printf 'system\tnew_note\t%s\n' "$arg"; return 0
  fi
  if arg="$(_after "$text" "type ")"; then
    printf 'system\ttype_text\t%s\n' "$arg"; return 0
  fi
  if arg="$(_after "$text" "copy to the clipboard ")" || arg="$(_after "$text" "copy this ")"; then
    printf 'system\tcopy_text\t%s\n' "$arg"; return 0
  fi
  if arg="$(_after "$text" "search for ")" || arg="$(_after "$text" "google ")" \
     || arg="$(_after "$text" "look up ")"; then
    printf 'system\tweb_search\t%s\n' "$arg"; return 0
  fi
  if arg="$(_after "$text" "find the file ")" || arg="$(_after "$text" "where is the file ")"; then
    printf 'system\tfind_file\t%s\n' "$arg"; return 0
  fi
  if arg="$(_after "$text" "switch to ")"; then
    printf 'system\tswitch_app\t%s\n' "$arg"; return 0
  fi
  if arg="$(_after "$text" "quit ")" || arg="$(_after "$text" "close ")"; then
    case "$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]')" in
      window*|"this"*|"that"*) : ;;
      *) printf 'system\tquit_app\t%s\n' "$arg"; return 0 ;;
    esac
  fi
  if arg="$(_after "$text" "open ")" || arg="$(_after "$text" "launch ")"; then
    case "$arg" in
      http*|www.*) printf 'system\topen_url\t%s\n' "$arg"; return 0 ;;
      *) printf 'system\topen_app\t%s\n' "$arg"; return 0 ;;
    esac
  fi

  return 1
}

# The things people say to a person that aren't instructions. Answering
# them is most of the difference between a command line with a microphone
# and something you can talk to.
_try_social() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[[:punct:]]+$//')"

  case "$lower" in
    "thank you"*|"thanks"*|"thankyou"*|"cheers"|"much appreciated"|"appreciate it"|\
    "that's all"|"thats all"|"that will be all"|"that is all"|"nothing else"|\
    "we're done"|"were done"|"i'm done"|"im done"|"goodbye"|"bye"|"bye bye"|"see you"|\
    "go away"|"dismissed")
      printf 'social\tthanks\n' ;;
    "hello"|"hi"|"hey"|"good morning"|"morning"|"good afternoon"|"good evening"|"yo")
      printf 'social\thello\n' ;;
    "how are you"*|"how's it going"*|"hows it going"*|"you good"*|"how are we"*)
      printf 'social\thowareyou\n' ;;
    "good night"|"goodnight"|"night"|"i'm going to bed"|"im going to bed")
      printf 'social\tgoodnight\n' ;;
    "sorry"*|"my bad"|"never mind"|"nevermind"|"forget it")
      printf 'social\tnevermind\n' ;;
    "nice"|"cool"|"great"|"perfect"|"lovely"|"awesome"|"good job"|"well done"|"nice one")
      printf 'social\tpraise\n' ;;
    "are you there"|"you there"|"can you hear me"|"hello?"|"you awake")
      printf 'social\tpresent\n' ;;
    *) return 1 ;;
  esac
}

_try_readback() {
  local lower
  lower="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    *"brief me"*|*"my briefing"*|*"what's my day"*|*"whats my day"*|*"how's my day"*)
      printf 'readback\tbriefing\n' ;;
    *message*|*imessage*|*text*)
      printf 'readback\tmessages\n' ;;
    *email*|*inbox*|*mail*)
      printf 'readback\tmail\n' ;;
    *calendar*|*schedule*|*meeting*)
      printf 'readback\tcalendar\n' ;;
    *reminder*|*"due today"*|*todo*|*"to do"*)
      printf 'readback\treminders\n' ;;
    # Only a question about Claude, so a mis-parsed "tell Claude to..."
    # doesn't quietly turn into a status report.
    "what did claude"*|"what's claude"*|"whats claude"*|"how's claude"*|*"claude status"*|*"from claude"*|*"claude finish"*)
      printf 'readback\tclaude\n' ;;
    *) return 1 ;;
  esac
}

# Claude Code as a last-resort classifier. Off unless `claude` is installed
# and ORBIT_NLU_FALLBACK is on; the rules above cover the daily phrasings.
_try_claude_nlu() {
  local text="$1" out
  [ "$ORBIT_NLU_FALLBACK" = "1" ] || return 1
  local claude_cmd
  claude_cmd="$(claude_bin)" || return 1

  out="$(run_with_timeout "$ORBIT_NLU_TIMEOUT" "$claude_cmd" -p "$(cat <<PROMPT
Classify this voice command into exactly one line, no explanation, no code fences.
Allowed forms:
message<TAB><person><TAB><what to say>
claude<TAB><repo name><TAB><task>
mail_reply<TAB><reply text>
readback<TAB>one of: briefing messages mail calendar reminders claude
none
Use a real tab between fields. Command: $text
PROMPT
)" 2>/dev/null)" || return 1

  out="$(printf '%s' "$out" | sed -E 's/<TAB>/\t/g' | grep -E '^(message|claude|mail_reply|readback)' | head -1)"
  [ -z "$out" ] && return 1
  printf '%s\n' "$out"
}

# A question, rather than an order. Checked late, so "what time is it"
# and "what's on my calendar" stay local and instant.
_try_ask() {
  local text="$1" lower
  lower="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"

  case "$lower" in
    "what's on my screen"*|"whats on my screen"*|"what am i looking at"*|\
    "read my screen"*|"what does this say"*|"what's this error"*|"whats this error"*|\
    "what does this error mean"*|"explain this"*|"what is this on screen"*)
      printf 'screen\t%s\t\n' "$text"; return 0 ;;
  esac

  case "$lower" in
    what*|who*|when*|where*|why*|how*|which*|\
    "is "*|"are "*|"was "*|"were "*|"can "*|"could "*|"should "*|"do "*|"does "*|\
    "did "*|"will "*|"would "*|"tell me about "*|"explain "*|"ask claude "*|\
    "look up "*|"define "*|"what if "*)
      printf 'ask\t%s\t\n' "$text"; return 0 ;;
  esac
  return 1
}

# parse_intent "<transcript>" -> intent <TAB> arg1 <TAB> arg2
parse_intent() {
  local text
  text="$(printf '%s' "$1" \
    | tr '()[]' '    ' \
    | sed -E 's/(saying|says|say|tell(ing)? (them|him|her))[[:space:]]*:/\1/Ig' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:space:]]+/ /g')"
  [ -z "$text" ] && { printf 'none\n'; return 0; }

  # Drop the wake word if the recognizer kept it.
  text="$(printf '%s' "$text" | sed -E 's/^(hey|hi|ok|okay)[[:space:]]+orbit[[:space:]]*[,.]?[[:space:]]*//I')"

  # A macro phrase is user-defined, so it outranks every built-in reading.
  if macro_steps "$text" >/dev/null 2>&1; then
    printf 'macro\t%s\t\n' "$text"
    return 0
  fi

  _try_social "$text"      && return 0
  _try_message "$text"     && return 0
  _try_claude "$text"      && return 0
  _try_mail_reply "$text"  && return 0
  _try_call "$text"        && return 0
  _try_system "$text"      && return 0
  _try_readback "$text"    && return 0
  _try_ask "$text"         && return 0
  _try_claude_nlu "$text"  && return 0

  # Nothing recognised it: let Claude write the command, to be confirmed
  # out loud before anything happens.
  local free
  if free="$(freeform_plan "$text")"; then
    printf 'system\tfreeform\t%s\t%s\n' \
      "$(printf '%s' "$free" | cut -f2)" "$(printf '%s' "$free" | cut -f1)"
    return 0
  fi

  printf 'none\n'
}

intent_examples() {
  cat <<'EXAMPLES'
Things Orbit understands (after "Hey Orbit"):

  Messages
    message Mama saying I'm running late
    text Priya saying dinner at eight
    send a message to Mom: landed safely

  Claude
    tell Claude to debug the flaky test in the dailyos repo
    ask Claude on the vortex repo to update the README
    have Claude to write tests for the parser        (uses your default repo)

  Calls
    call Mama
    facetime Priya
    call Mom on facetime audio
    hang up

  Mail
    send an automated reply to all emails awaiting reply saying I'm on vacation
    reply to all unanswered emails saying I'll get back to you Monday

  Driving apps
    in Safari click New Private Window
    click Export in Keynote
    new tab / close tab / reload / go back / save this
    play bohemian rhapsody on spotify

  Reading things out
    brief me
    what's on my calendar
    read my messages
    any new email
    what did Claude do
EXAMPLES
}
