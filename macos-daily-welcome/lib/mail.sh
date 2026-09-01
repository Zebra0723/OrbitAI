#!/bin/bash
# Apple Mail: what's unread, what's still awaiting a reply, and replying
# to a batch of it.
#
# Everything here is a two-step: build the list first, act on it second,
# with a spoken confirmation in between. Nothing in this file sends mail
# without having been asked twice.

_mail_unread_applescript() {
  local limit="$1"
  osascript <<APPLESCRIPT
on run
  set outText to ""
  set shown to 0
  tell application "Mail"
    repeat with m in (messages of inbox whose read status is false)
      if shown >= $limit then exit repeat
      set shown to shown + 1
      try
        set theSender to extract name from (sender of m)
      on error
        set theSender to (sender of m)
      end try
      set outText to outText & (time string of (date received of m)) & tab & theSender & ": " & (subject of m) & tab & linefeed
    end repeat
  end tell
  return outText
end run
APPLESCRIPT
}

src_mail() {
  have_cmd osascript || return 0

  local raw rc
  raw="$(run_with_timeout "$WELCOME_SOURCE_TIMEOUT" \
    _mail_unread_applescript "$((WELCOME_MAX_ITEMS * 2))")"
  rc=$?

  if [ "$rc" -eq 124 ]; then _note "Mail took too long to answer"; return 0; fi
  if [ "$rc" -ne 0 ]; then
    _note "Mail: $(last_error) (daily-welcome --doctor)"; return 0
  fi
  printf '%s\n' "$raw" | awk -F'\t' 'NF >= 2 && $2 != "" { print }' | tidy_time_field
}

# --------------------------------------------------------- awaiting reply

# Messages sent to me, not from me, that I haven't replied to. Mail tracks
# "was replied to" itself, which beats guessing from thread contents.
_mail_awaiting_applescript() {
  local days="$1" limit="$2"
  osascript <<APPLESCRIPT
on run
  set cutoff to (current date) - ($days * days)
  set outText to ""
  set shown to 0
  tell application "Mail"
    repeat with m in (messages of inbox whose was replied to is false and date received > cutoff)
      if shown >= $limit then exit repeat
      try
        set theAddress to extract address from (sender of m)
      on error
        set theAddress to (sender of m)
      end try
      try
        set theName to extract name from (sender of m)
      on error
        set theName to theAddress
      end try
      if theAddress is not "" then
        set shown to shown + 1
        set outText to outText & (id of m) & tab & theName & tab & theAddress & tab & (subject of m) & linefeed
      end if
    end repeat
  end tell
  return outText
end run
APPLESCRIPT
}

# Prints: id <TAB> name <TAB> address <TAB> subject
mail_awaiting_reply() {
  local days="${1:-$ORBIT_MAIL_AWAITING_DAYS}" limit="${2:-$ORBIT_MAIL_MAX_BATCH}"
  run_with_timeout "$ORBIT_MAIL_TIMEOUT" _mail_awaiting_applescript "$days" "$limit" \
    | awk -F'\t' 'NF >= 4 && $1 != ""'
}

# mail_draft_reply MESSAGE_ID BODY - saves a reply in Drafts, unsent.
mail_draft_reply() {
  local msg_id="$1" body="$2"
  osascript - "$msg_id" "$body" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set theId to (item 1 of argv) as integer
  set theBody to item 2 of argv
  tell application "Mail"
    set matches to (messages of inbox whose id is theId)
    if (count of matches) is 0 then error "message not found"
    set theMessage to item 1 of matches
    set theReply to reply theMessage opening window false
    tell theReply
      set content to theBody & return & return & (content of theReply)
    end tell
    save theReply
  end tell
end run
APPLESCRIPT
}

# mail_send_draft SUBJECT ADDRESS - sends the draft matching both, and
# reports what happened. A draft the user deleted is treated as a
# deliberate opt-out, not an error.
mail_send_draft() {
  local subject="$1" address="$2"
  osascript - "$subject" "$address" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set wantSubject to item 1 of argv
  set wantAddress to item 2 of argv
  tell application "Mail"
    repeat with d in (messages of drafts mailbox)
      set matched to false
      try
        repeat with r in (to recipients of d)
          if (address of r) is wantAddress then set matched to true
        end repeat
      end try
      if matched and (subject of d) contains wantSubject then
        send d
        return "sent"
      end if
    end repeat
  end tell
  return "missing"
end run
APPLESCRIPT
}
