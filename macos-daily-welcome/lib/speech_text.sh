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
  if [ "$h24" -lt 12 ]; then printf 'in the morning'
  elif [ "$h24" -lt 18 ]; then printf 'in the afternoon'
  else printf 'in the evening'
  fi
}

# time_words 8 42 [with_part] -> "eight forty-two in the morning"
time_words() {
  local h24="$1" min="$2" with_part="${3:-1}"
  local h12=$((h24 % 12)); [ "$h12" -eq 0 ] && h12=12
  local out

  if [ "$min" -eq 0 ]; then
    out="$(num_word "$h12") o'clock"
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
    | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//' \
    | cut -c1-120
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
