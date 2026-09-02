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

# The email address, specifically. contact_handle prefers a phone number,
# which is right for a message and wrong for mail.
_contacts_email_applescript() {
  local name="$1"
  osascript - "$name" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set wantName to item 1 of argv
  tell application "Contacts"
    launch
    set matches to (every person whose name contains wantName)
    if (count of matches) is 0 then return ""
    set thePerson to item 1 of matches
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

contact_email() {
  local want="$1" resolved found

  # An alias that is already an address needs no lookup at all.
  resolved="$(_contacts_alias "$want")" && [ -n "$resolved" ] || resolved="$want"
  case "$resolved" in
    *@*.*) printf '%s' "$resolved"; return 0 ;;
  esac

  found="$(run_with_timeout 10 _contacts_email_applescript "$resolved")"
  found="$(printf '%s' "$found" | tr -d '\n\r' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  case "$found" in
    *@*.*) printf '%s' "$found"; return 0 ;;
  esac
  return 1
}

# Contacts is slow to answer and slower to launch, and the same few people
# get messaged over and over, so a resolved name is remembered.
_contacts_cache_file() { printf '%s/contacts-cache' "$WELCOME_STATE_DIR"; }

_contacts_cached() {
  local want="$1"
  [ -f "$(_contacts_cache_file)" ] || return 1
  awk -F'\t' -v want="$(printf '%s' "$want" | tr '[:upper:]' '[:lower:]')" '
    tolower($1) == want { print $2; found = 1; exit }
    END { exit(found ? 0 : 1) }' "$(_contacts_cache_file)"
}

_contacts_remember() {
  mkdir -p "$WELCOME_STATE_DIR" 2>/dev/null
  printf '%s\t%s\n' "$1" "$2" >> "$(_contacts_cache_file)"
}

# contact_handle "mama" -> "+15551234567" (empty and non-zero if unknown)
contact_handle() {
  local want="$1" resolved cached

  if cached="$(_contacts_cached "$want")"; then
    printf '%s' "$cached"
    return 0
  fi

  resolved="$(_contacts_alias "$want")" && [ -n "$resolved" ] || resolved=""

  # An alias may itself be a real name to look up rather than a number.
  case "$resolved" in
    "" ) resolved="$want" ;;
    *[0-9@]* ) _contacts_remember "$want" "$resolved"; printf '%s' "$resolved"; return 0 ;;
  esac

  local found
  found="$(run_with_timeout 10 _contacts_lookup_applescript "$resolved")"
  found="$(printf '%s' "$found" | tr -d '\n\r' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"
  [ -z "$found" ] && return 1
  _contacts_remember "$want" "$found"
  printf '%s' "$found"
}
