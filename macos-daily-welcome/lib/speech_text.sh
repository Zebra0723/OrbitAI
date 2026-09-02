#!/bin/bash
# Turning data into words a speech engine reads correctly.
#
# Both Apple's `say` and hosted engines mangle bare digits and clock times
# in their own ways ("9:00 AM" as "nine hundred", "August 31" as "August
# thirty one"). Rather than guess per engine, the briefing is written out
# in words before it ever reaches one.

# num_word 42 -> "forty-two"   (0-99)
num_word() {
  awk -v n="$1" 'BEGIN {
    split("zero one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen nineteen", o, " ")
    split("x x twenty thirty forty fifty sixty seventy eighty ninety", t, " ")
    n = int(n)
    if (n < 0 || n > 99) { printf "%d", n; exit }
    if (n < 20) { printf "%s", o[n + 1]; exit }
    r = n % 10; d = int(n / 10)
    printf "%s%s", t[d + 1], (r ? "-" o[r + 1] : "")
  }'
}

# duration_words 5400 -> "an hour and a half"; 30 -> "thirty seconds".
# The noun phrase, for "Timer set for ___."
duration_words() {
  local secs="${1:-0}" n
  if [ "$secs" -lt 60 ]; then
    printf '%s second%s' "$(num_word "$secs")" "$([ "$secs" = 1 ] || echo s)"
  elif [ "$secs" = 5400 ]; then
    printf 'an hour and a half'
  elif [ $((secs % 3600)) -eq 0 ]; then
    n=$((secs / 3600))
    printf '%s hour%s' "$(num_word "$n")" "$([ "$n" = 1 ] || echo s)"
  else
    n=$((secs / 60))
    printf '%s minute%s' "$(num_word "$n")" "$([ "$n" = 1 ] || echo s)"
  fi
}

# duration_attr 7200 -> "two hour", for "Your ___ timer is up."
duration_attr() {
  local secs="${1:-0}" n
  if [ "$secs" -lt 60 ]; then
    printf '%s second' "$(num_word "$secs")"
  elif [ "$secs" = 5400 ]; then
    printf 'hour and a half'
  elif [ $((secs % 3600)) -eq 0 ]; then
    printf '%s hour' "$(num_word $((secs / 3600)))"
  else
    printf '%s minute' "$(num_word $((secs / 60)))"
  fi
}

# ordinal_word 31 -> "thirty-first"   (1-31)
ordinal_word() {
  awk -v n="$1" 'BEGIN {
    split("first second third fourth fifth sixth seventh eighth ninth tenth eleventh twelfth thirteenth fourteenth fifteenth sixteenth seventeenth eighteenth nineteenth twentieth", o, " ")
    split("x x twenty thirty", t, " ")
    split("x first second third fourth fifth sixth seventh eighth ninth", u, " ")
    n = int(n)
    if (n >= 1 && n <= 20) { printf "%s", o[n]; exit }
    if (n == 30) { printf "thirtieth"; exit }
    d = int(n / 10); r = n % 10
    if (r == 0) { printf "%d", n; exit }
    printf "%s-%s", t[d + 1], u[r + 1]
  }'
}

_day_part() {
  local h24="$1"
  # Half past midnight is not the morning to anyone who is awake for it,
  # and neither is eleven at night.
  if [ "$h24" -lt 5 ]; then printf 'at night'
  elif [ "$h24" -lt 12 ]; then printf 'in the morning'
  elif [ "$h24" -lt 18 ]; then printf 'in the afternoon'
  elif [ "$h24" -lt 22 ]; then printf 'in the evening'
  else printf 'at night'
  fi
}

# time_words 8 42 [with_part] -> "eight forty-two in the morning"
time_words() {
  local h24="$1" min="$2" with_part="${3:-1}"
  local h12=$((h24 % 12)); [ "$h12" -eq 0 ] && h12=12
  local out

  if [ "$min" -eq 0 ]; then
    # "Nine in the morning", not "nine o'clock in the morning". On the
    # hour with no other marker, "o'clock" is what stops "nine" sounding
    # like a stray number; with a part of the day after it, it is just
    # two extra syllables in the middle of a list.
    if [ "$with_part" = "1" ]; then out="$(num_word "$h12")"
    else out="$(num_word "$h12") o'clock"; fi
  elif [ "$min" -lt 10 ]; then
    out="$(num_word "$h12") oh $(num_word "$min")"
  else
    out="$(num_word "$h12") $(num_word "$min")"
  fi

  [ "$with_part" = "1" ] && out="$out $(_day_part "$h24")"
  printf '%s' "$out"
}

# Parses whatever the system handed us - "9:30:00 AM", "09:30", "9:00AM" -
# and returns spoken words. Unparseable input comes back unchanged.
time_words_from_string() {
  local raw="$1" h m ampm
  h="$(printf '%s' "$raw" | sed -nE 's/^[[:space:]]*([0-9]{1,2}):([0-9]{2}).*/\1/p')"
  m="$(printf '%s' "$raw" | sed -nE 's/^[[:space:]]*([0-9]{1,2}):([0-9]{2}).*/\2/p')"
  if [ -z "$h" ]; then printf '%s' "$raw"; return 0; fi

  ampm="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]' | sed -nE 's/.*([AP])\.?M\.?.*/\1/p')"
  h=$((10#$h)); m=$((10#$m))
  case "$ampm" in
    P) [ "$h" -lt 12 ] && h=$((h + 12)) ;;
    A) [ "$h" -eq 12 ] && h=0 ;;
  esac
  time_words "$h" "$m"
}

# Same as time_words_from_string, but drops the "in the morning" tail when
# it matches the current part of day - at 8am, "at nine thirty" is plenty.
time_words_relative() {
  local raw="$1" h m ampm now_part item_part
  h="$(printf '%s' "$raw" | sed -nE 's/^[[:space:]]*([0-9]{1,2}):([0-9]{2}).*/\1/p')"
  m="$(printf '%s' "$raw" | sed -nE 's/^[[:space:]]*([0-9]{1,2}):([0-9]{2}).*/\2/p')"
  if [ -z "$h" ]; then printf '%s' "$raw"; return 0; fi

  ampm="$(printf '%s' "$raw" | tr '[:lower:]' '[:upper:]' | sed -nE 's/.*([AP])\.?M\.?.*/\1/p')"
  h=$((10#$h)); m=$((10#$m))
  case "$ampm" in
    P) [ "$h" -lt 12 ] && h=$((h + 12)) ;;
    A) [ "$h" -eq 12 ] && h=0 ;;
  esac

  now_part="$(_day_part "$(date '+%-H')")"
  item_part="$(_day_part "$h")"
  if [ "$now_part" = "$item_part" ]; then
    time_words "$h" "$m" 0
  else
    time_words "$h" "$m" 1
  fi
}

# today_words -> "Monday, the thirty-first of August"
today_words() {
  printf '%s the %s of %s' \
    "$(date '+%A')" "$(ordinal_word "$(date '+%-d')")" "$(date '+%B')"
}

# now_words -> "eight forty-two in the morning"
now_words() {
  time_words "$(date '+%-H')" "$((10#$(date '+%M')))"
}

# Makes a reminder or event title safe and sensible to read aloud: no
# markup, no URLs, no emoji soup, no half-hour-long titles.
speech_clean() {
  printf '%s' "$1" \
    | sed -E 's#https?://[^[:space:]]+# a link #g' \
    | sed -E 's/[][*_`~|<>#]+/ /g' \
    | sed -E 's/&/ and /g; s/(^| )w\/( |$)/\1with\2/g; s/(^| )@( |$)/\1at\2/g' \
    | sed -E 's/(^| )vs\.?( |$)/\1versus\2/g' \
    | sed -E 's/([0-9]{1,2}(:[0-9]{2})?)[[:space:]]*[Pp]\.?[Mm]\.?/\1 PM/g' \
    | sed -E 's/([0-9]{1,2}(:[0-9]{2})?)[[:space:]]*[Aa]\.?[Mm]\.?/\1 AM/g' \
    | tr -cd '[:print:]' \
    | sed -E 's/[[:space:]]+/ /g' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' \
    | cut -c1-120
}

# Written English and spoken English are not the same language.
#
# "It is eight o'clock and you have three reminders" is correct and no
# person has ever said it. Uncontracted forms are most of what makes a
# synthetic voice sound like it is reading rather than talking, and the
# voice cannot fix it - the problem arrives before the voice does.
#
# Done on word PAIRS in awk rather than with \b, which BSD sed does not
# have and macOS ships BSD sed. Capitalisation carries over from the
# first word and punctuation from the second, so "It is." at the start of
# a sentence becomes "It's." and not "it'S".
speech_natural() {
  printf '%s' "$1" | awk '
    BEGIN {
      # Built up rather than written as one string: a table this long
      # spread over backslash continuations is one deleted line away from
      # breaking the quoting of the whole file.
      r = "it is|it@s,that is|that@s,there is|there@s,what is|what@s"
      r = r ",he is|he@s,she is|she@s,who is|who@s,here is|here@s"
      r = r ",you are|you@re,we are|we@re,they are|they@re"
      r = r ",i am|I@m,i will|I@ll,you will|you@ll,it will|it@ll"
      r = r ",do not|don@t,does not|doesn@t,did not|didn@t,is not|isn@t"
      r = r ",are not|aren@t,was not|wasn@t,were not|weren@t"
      r = r ",have not|haven@t,has not|hasn@t,had not|hadn@t"
      r = r ",will not|won@t,would not|wouldn@t,could not|couldn@t"
      r = r ",should not|shouldn@t,let us|let@s,you would|you@d,i would|I@d"
      # No "you have" -> "you@ve". Before a noun that is British and
      # dated - "you@ve three reminders" - and a briefing is all nouns.

      n = split(r, rules, ",")
      for (i = 1; i <= n; i++) {
        split(rules[i], parts, "|")
        short[parts[1]] = parts[2]
      }
    }
    function bare(w,   s) { s = tolower(w); gsub(/[^a-z]/, "", s); return s }
    {
      count = split($0, w, " ")
      out = ""
      i = 1
      while (i <= count) {
        used = 0
        if (i < count) {
          key = bare(w[i]) " " bare(w[i+1])

          # "I will not" is "I won@t", never "I@ll not". When the word
          # after a pair is "not", the negation is the contraction that
          # matters and this pair steps aside for it.
          skip = 0
          if (i + 2 <= count && bare(w[i+2]) == "not") {
            second = bare(w[i+1])
            if (second ~ /^(will|is|are|was|were|have|has|had|do|does|did|would|could|should)$/) skip = 1
          }

          # Only when the first word is nothing but letters: an opening
          # bracket or a quote in front of it means it is not a plain
          # sentence and is better left alone.
          if (!skip && (key in short) && w[i] ~ /^[A-Za-z]+$/) {
            joined = short[key]
            gsub(/@/, "\047", joined)
            if (w[i] ~ /^[A-Z]/) joined = toupper(substr(joined, 1, 1)) substr(joined, 2)
            tail = w[i+1]
            sub(/^[A-Za-z]+/, "", tail)     # a comma, a full stop, a question mark
            out = out (out == "" ? "" : " ") joined tail
            i += 2
            used = 1
          }
        }
        if (!used) {
          out = out (out == "" ? "" : " ") w[i]
          i++
        }
      }
      print out
    }'
}

# Punctuation for the ear, not the page.
#
# A comma tells a reader to breathe and tells a speech engine to STOP,
# and they stop hard - which is most of what makes a synthetic voice
# sound synthetic. Deleting the commas fixed the pausing and cost the
# phrasing, so instead the pause is SHORTENED and the comma kept.
#
# Each engine has a different lever, so this takes the backend:
#   say          [[slnc N]] - an exact pause in milliseconds
#   elevenlabs   <break time="..."/> - the same idea, their syntax
#   openai       no such control, so the comma stays and the delivery
#                instructions carry it
#
# WELCOME_PAUSE: short (default) | natural | none
speech_pace() {
  # speech_text.sh is sourced before voice.sh in some entry points, so
  # the backend cannot be assumed to be askable yet. Falling back to the
  # local voice is right: it is the one that always exists.
  local text="$1" backend="${2:-}"
  if [ -z "$backend" ]; then
    if command -v tts_backend >/dev/null 2>&1; then backend="$(tts_backend)"
    else backend="say"; fi
  fi

  case "$WELCOME_PAUSE" in
    natural) printf '%s' "$text"; return 0 ;;
  esac

  # Tidy first, whatever the setting: a semicolon is a full stop out loud,
  # a spaced dash and an ellipsis are both dead air.
  text="$(printf '%s' "$text" \
    | sed -E 's/ +[-–—] +/ /g; s/\.\.\.+/ /g; s/;/./g' \
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

  if [ "$WELCOME_PAUSE" = "none" ]; then
    # The old behaviour, kept for anyone who preferred it: no commas at
    # all. A comma between digits still stays, or 1,000 loses its zero.
    printf '%s' "$text" | sed -E 's/,([^0-9])/\1/g; s/,$//'
    return 0
  fi

  case "$backend" in
    say)
      # Not one pause repeated.
      #
      # Every comma getting the same number of milliseconds is itself
      # most of what makes a list sound like a list being read out. A
      # person breathes differently at different joins: barely at all
      # before "and then", properly at a comma that opens a clause, and
      # fully at the end of a sentence. Three numbers instead of one.
      local short_ms
      short_ms=$(( WELCOME_PAUSE_MS * 55 / 100 ))

      # The words that mean "this is the part to act on". Understated on
      # purpose: a voice that leans on every number sounds like a
      # different kind of machine, not less of one.
      if [ "$WELCOME_SAY_EMPHASIS" = "1" ]; then
        text="$(printf '%s' "$text" | sed -E \
          's/(^|[^A-Za-z])(overdue|unread|urgent|late)($|[^A-Za-z])/\1[[emph +]]\2[[emph -]]\3/g')"
      fi

      # No extra pause at a full stop: `say` already stops there, and
      # adding to it made every sentence land with a thud. The commas
      # were the complaint; the full stops never were.
      printf '%s' "$text" | sed -E "
        s/, (and then|then|and|but|so) / [[slnc $short_ms]] \1 /g
        s/,([^0-9])/ [[slnc $WELCOME_PAUSE_MS]]\1/g
      " ;;
    elevenlabs)
      printf '%s' "$text" \
        | sed -E "s#,([^0-9])#<break time=\"$(printf '%s' "$WELCOME_PAUSE_MS" | awk '{printf "%.2f", $1/1000}')s\" />\1#g" ;;
    *)
      # OpenAI has no pause control. The comma stays and the delivery
      # instructions do the work - deleting it here would cost the
      # phrasing for nothing.
      printf '%s' "$text" ;;
  esac
}

# Sentence case. The briefing is assembled from fragments, and a voice
# reading "three reminders due today" as a sentence opener sounds like it
# lost its place.
capitalize_sentences() {
  awk '{
    n = split($0, ch, "")
    cap = 1
    out = ""
    for (i = 1; i <= n; i++) {
      c = ch[i]
      if (cap && c ~ /[a-z]/) { c = toupper(c); cap = 0 }
      else if (c ~ /[A-Za-z0-9]/) { cap = 0 }
      if (c == "." || c == "?" || c == "!" || c == ":") cap = 1
      out = out c
    }
    print out
  }'
}
