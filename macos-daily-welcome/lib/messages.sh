#!/bin/bash
# Messages: reading unread iMessages, and sending one.
#
# Reading goes straight at the local chat.db, because Messages.app exposes
# almost nothing useful to AppleScript. That database needs Full Disk
# Access for whatever process opens it - the installer says so, and a
# refusal here degrades to a note rather than an error.

MESSAGES_DB="${MESSAGES_DB:-$HOME/Library/Messages/chat.db}"

# Apple stores message dates as nanoseconds since 2001-01-01.
_APPLE_EPOCH=978307200

_messages_query() {
  local since_days="$1" limit="$2"
  sqlite3 -readonly -separator "$(printf '\t')" "$MESSAGES_DB" <<SQL 2>/dev/null
.timeout 3000
SELECT
  COALESCE(NULLIF(c.display_name, ''), h.id, 'Unknown') AS who,
  COALESCE(NULLIF(m.text, ''), '(attachment)') AS body,
  strftime('%H:%M', m.date / 1000000000 + $_APPLE_EPOCH, 'unixepoch', 'localtime') AS at
FROM message m
LEFT JOIN handle h ON m.handle_id = h.ROWID
LEFT JOIN chat_message_join cmj ON cmj.message_id = m.ROWID
LEFT JOIN chat c ON c.ROWID = cmj.chat_id
WHERE m.is_from_me = 0
  AND m.is_read = 0
  -- CAST, and not for tidiness. strftime returns TEXT, and SQLite orders
  -- every integer below every string, so "a number > that string" was
  -- false for every message ever sent. The section was not empty because
  -- there was nothing unread; it was empty because the question could
  -- not be answered yes.
  AND m.date / 1000000000 + $_APPLE_EPOCH >
      CAST(strftime('%s', 'now', '-$since_days days') AS INTEGER)
ORDER BY m.date DESC
LIMIT $limit;
SQL
}

# Records: HH:MM <TAB> "Who: message" <TAB> ""
src_messages() {
  [ -f "$MESSAGES_DB" ] || return 0
  have_cmd sqlite3 || return 0

  local raw rc
  raw="$(run_with_timeout "$WELCOME_SOURCE_TIMEOUT" \
    _messages_query "$WELCOME_MESSAGES_SINCE_DAYS" "$((WELCOME_MAX_ITEMS * 3))")"
  rc=$?

  if [ "$rc" -eq 124 ]; then
    _note "Messages database is busy"; return 0
  fi
  if [ -z "$raw" ]; then
    # Empty is ambiguous: no unread, or the database wouldn't open. A probe
    # tells them apart, and its own words are more use than a guess -
    # "unable to open database file" is Full Disk Access, but a locked WAL
    # or a missing table is not, and they were all reported the same way.
    local probe
    probe="$(sqlite3 -readonly "$MESSAGES_DB" 'SELECT 1 FROM message LIMIT 1;' 2>&1 >/dev/null)"
    if [ -n "$probe" ]; then
      case "$probe" in
        *"unable to open"*|*"authorization denied"*|*"not permitted"*)
          _note "Messages needs Full Disk Access for whatever is running this ($probe)" ;;
        *)
          _note "Messages: $probe" ;;
      esac
    fi
    return 0
  fi

  # One line per sender: "Mom: ... (+2 more)" beats three lines from Mom.
  printf '%s\n' "$raw" | awk -F'\t' -v max="$WELCOME_MESSAGE_PREVIEW" '
    NF >= 2 {
      who = $1; body = $2; at = $3
      gsub(/\r/, " ", body)
      if (length(body) > max) body = substr(body, 1, max - 1) "..."
      if (!(who in seen)) { order[++n] = who; first[who] = body; when[who] = at }
      seen[who]++
    }
    END {
      for (i = 1; i <= n; i++) {
        w = order[i]
        extra = (seen[w] > 1) ? sprintf(" (+%d more)", seen[w] - 1) : ""
        printf "%s\t%s: %s%s\t\n", when[w], w, first[w], extra
      }
    }'
}

# messages_send HANDLE TEXT - handle is a phone number or iMessage address.
messages_send() {
  local handle="$1" text="$2"
  have_cmd osascript || return 1
  osascript - "$handle" "$text" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set theHandle to item 1 of argv
  set theText to item 2 of argv
  tell application "Messages"
    set targetService to 1st account whose service type = iMessage
    set theBuddy to participant theHandle of targetService
    send theText to theBuddy
  end tell
end run
APPLESCRIPT
}
