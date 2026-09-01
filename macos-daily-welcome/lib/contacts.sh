#!/bin/bash
# Turning "mama" into something Messages can actually send to.
#
# Nicknames first (yours, in contacts.conf), then Contacts.app. A name
# that resolves to nothing stops the command - guessing at who you meant
# is the one failure mode worth refusing outright.

# contacts.conf lines: "mama = +15551234567"  or  "mama = Mom"
_contacts_alias() {
  local want="$1" file="$ORBIT_CONTACTS_FILE"
  [ -f "$file" ] || return 1
  awk -F'=' -v want="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" '
    /^[[:space:]]*#/ { next }
    NF >= 2 {
      key = $1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
      val = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
      if (tolower(key) == want) { print val; found = 1; exit }
    }
    END { exit(found ? 0 : 1) }' "$file"
}

_contacts_lookup_applescript() {
  local name="$1"
  osascript - "$name" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set wantName to item 1 of argv
  tell application "Contacts"
    -- Contacts answers nothing at all (-600) unless it's running, and it
    -- won't start itself just to be queried.
    launch
    set matches to (every person whose name contains wantName)
    if (count of matches) is 0 then return ""
    set thePerson to item 1 of matches
    try
      if (count of phones of thePerson) > 0 then
        return (value of first phone of thePerson)
      end if
    end try
    try
      if (count of emails of thePerson) > 0 then
        return (value of first email of thePerson)
      end if
    end try
  end tell
  return ""
end run
APPLESCRIPT
}

# contact_handle "mama" -> "+15551234567" (empty and non-zero if unknown)
contact_handle() {
  local want="$1" resolved

  resolved="$(_contacts_alias "$want")" && [ -n "$resolved" ] || resolved=""

  # An alias may itself be a real name to look up rather than a number.
  case "$resolved" in
    "" ) resolved="$want" ;;
    *[0-9@]* ) printf '%s' "$resolved"; return 0 ;;
  esac

  local found
  found="$(run_with_timeout 10 _contacts_lookup_applescript "$resolved")"
  found="$(printf '%s' "$found" | tr -d '\n\r' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [ -z "$found" ] && return 1
  printf '%s' "$found"
}
