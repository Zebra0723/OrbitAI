#!/bin/bash
# Macros: one phrase, several actions.
#
# ~/.config/daily-welcome/macros.conf, one per line:
#
#   good night = dark mode; turn off wifi; set a timer for 5 minutes
#   focus      = quit Slack; hide everything; dark mode
#   heads down = do not disturb; quit Mail; full screen
#
# The right-hand side is ordinary Orbit commands, so a macro can do
# anything you could say, and nothing you couldn't.

macros_file() { printf '%s' "$ORBIT_MACROS_FILE"; }

# The phrase Orbit would match, for every macro defined.
macros_list() {
  [ -f "$(macros_file)" ] || return 0
  awk -F'=' '
    /^[[:space:]]*#/ { next }
    NF >= 2 {
      name = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", name)
      body = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", body)
      if (name != "" && body != "") printf "%s\t%s\n", name, body
    }' "$(macros_file)"
}

# macro_steps "<phrase>" -> one command per line, or non-zero if no macro
macro_steps() {
  local want body
  want="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g; s/[[:punct:]]+$//')"
  [ -z "$want" ] && return 1

  body="$(macros_list | awk -F'\t' -v want="$want" '
    tolower($1) == want { print $2; found = 1; exit }
    END { exit(found ? 0 : 1) }')" || return 1

  # Steps are separated by ";" or " then ".
  printf '%s' "$body" \
    | sed -E 's/[[:space:]]+then[[:space:]]+/;/Ig' \
    | tr ';' '\n' \
    | sed -E 's/^[[:space:]]+|[[:space:]]+$//g' \
    | grep -v '^$'
}
