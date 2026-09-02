#!/bin/bash
# Apple Mail: what's unread, what's still awaiting a reply, and replying
# to a batch of it.
#
# Everything here is a two-step: build the list first, act on it second,
# with a spoken confirmation in between. Nothing in this file sends mail
# without having been asked twice.

# How many unread messages Mail thinks there are. One Apple Event, instant,
# and the only trustworthy answer to "is my inbox clear".
#
# The scan below looks at the newest N messages, which is fast but assumes
# the unread ones are near the top. If you triage on your phone, they are
# not - the newest are all read and the unread sit further down. The scan
# then found nothing and Orbit said "your inbox is clear", which was a
# confident wrong answer. Asking for the count first makes that
# impossible: a count above zero with an empty scan means widen the net,
# not "clear".
_mail_unread_count() {
  osascript <<'APPLESCRIPT' 2>/dev/null
on run
  set n to 0
  tell application "Mail"
    try
      set n to unread count of inbox
    end try
    repeat with acct in accounts
      try
        if enabled of acct then set n to n + (unread count of (mailbox "INBOX" of acct))
      end try
    end repeat
  end tell
  return n as string
end run
APPLESCRIPT
}

# The slow but exhaustive query, used only when the fast scan comes back
# empty on a mailbox that says it has unread mail.
_mail_unread_deep() {
  local limit="$1"
  osascript <<APPLESCRIPT
on run
  set outText to ""
  tell application "Mail"
    try
      set found to (messages of inbox whose read status is false)
      set total to (count of found)
      if total > $limit then set total to $limit
      if total > 0 then
        set msgs to (items 1 thru total of found)
        set subjList to subject of msgs
        set sendList to sender of msgs
        set dateList to date received of msgs
        set idList to id of msgs
        repeat with i from 1 to (count of msgs)
          set theSender to (item i of sendList)
          try
            set theSender to extract name from theSender
          end try
          set outText to outText & (time string of (item i of dateList)) & tab & theSender & ": " & (item i of subjList) & tab & (item i of idList) & linefeed
        end repeat
      end if
    end try
  end tell
  return outText
end run
APPLESCRIPT
}

_mail_unread_applescript() {
  local limit="$1"
  osascript <<APPLESCRIPT
on run
  set outText to ""
  set shown to 0
  tell application "Mail"
    -- Properties are fetched for the WHOLE list at once. Asking message by
    -- message costs one Apple Event per property per message: sixty
    -- messages across a handful of mailboxes ran to a couple of thousand
    -- round trips, which is why this reliably ran past its timeout and
    -- came back as "Mail took too long to answer". A list request is one
    -- round trip for the lot.
    set boxes to {}
    try
      set end of boxes to inbox
    end try
    -- One mailbox per account, not two: asking for both "INBOX" and the
    -- account's inbox doubled the work to find the same mail twice.
    repeat with acct in accounts
      try
        if enabled of acct then set end of boxes to (mailbox "INBOX" of acct)
      end try
    end repeat

    repeat with theBox in boxes
      if shown >= $limit then exit repeat
      try
        set total to (count of messages of theBox)
        if total > $ORBIT_MAIL_SCAN then set total to $ORBIT_MAIL_SCAN
        if total > 0 then
          set msgs to (messages 1 thru total of theBox)
          set readList to read status of msgs
          set subjList to subject of msgs
          set sendList to sender of msgs
          set idList to id of msgs
          set dateList to date received of msgs

          repeat with i from 1 to (count of readList)
            if shown >= $limit then exit repeat
            if (item i of readList) is false then
              set shown to shown + 1
              set theSender to (item i of sendList)
              try
                set theSender to extract name from theSender
              end try
              set outText to outText & (time string of (item i of dateList)) & tab & theSender & ": " & (item i of subjList) & tab & (item i of idList) & linefeed
            end if
          end repeat
        end if
      end try
    end repeat
  end tell
  return outText
end run
APPLESCRIPT
}

src_mail() {
  have_cmd osascript || return 0

  local raw rc unread
  unread="$(run_with_timeout 8 _mail_unread_count)"
  unread="$(printf '%s' "$unread" | tr -cd '0-9')"

  # Mail itself says there is nothing unread. That is the one case where
  # "your inbox is clear" is a fact rather than a guess.
  [ -n "$unread" ] && [ "$unread" = "0" ] && return 0

  raw="$(run_with_timeout "$ORBIT_MAIL_TIMEOUT" \
    _mail_unread_applescript "$((WELCOME_MAX_ITEMS * 2))")"
  rc=$?

  if [ "$rc" -eq 124 ]; then
    _note "Mail took longer than ${ORBIT_MAIL_TIMEOUT}s (lower ORBIT_MAIL_SCAN, or raise ORBIT_MAIL_TIMEOUT)"
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    _note "Mail: $(last_error) (daily-welcome --doctor)"; return 0
  fi

  # Field 3 is the message id, used only to drop the duplicates that come
  # from asking both the unified inbox and each account's own.
  local rows
  rows="$(printf '%s\n' "$raw" \
    | awk -F'\t' 'NF >= 2 && $2 != "" && !seen[$3]++ { printf "%s\t%s\t\n", $1, $2 }')"

  # The window missed them. Ask the exhaustive question rather than
  # reporting an empty inbox that Mail has just said is not empty.
  if [ -z "$(printf '%s' "$rows" | tr -d '[:space:]')" ] && [ -n "$unread" ] && [ "$unread" != "0" ]; then
    raw="$(run_with_timeout "$ORBIT_MAIL_TIMEOUT" _mail_unread_deep "$((WELCOME_MAX_ITEMS * 2))")"
    if [ $? -eq 124 ]; then
      _note "$unread unread, but Mail was too slow to list them (raise ORBIT_MAIL_TIMEOUT)"
      return 0
    fi
    rows="$(printf '%s\n' "$raw" \
      | awk -F'\t' 'NF >= 2 && $2 != "" && !seen[$3]++ { printf "%s\t%s\t\n", $1, $2 }')"
  fi

  printf '%s\n' "$rows" | tidy_time_field
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
    set total to (count of messages of inbox)
    if total > $ORBIT_MAIL_SCAN then set total to $ORBIT_MAIL_SCAN
    if total > 0 then
      set msgs to (messages 1 thru total of inbox)
      set repliedList to was replied to of msgs
      set dateList to date received of msgs
      set sendList to sender of msgs
      set subjList to subject of msgs
      set idList to id of msgs

      repeat with i from 1 to (count of msgs)
        if shown >= $limit then exit repeat
        if (item i of dateList) < cutoff then exit repeat
        if (item i of repliedList) is false then
          set theRaw to (item i of sendList)
          set theAddress to theRaw
          set theName to theRaw
          try
            set theAddress to extract address from theRaw
          end try
          try
            set theName to extract name from theRaw
          end try
          if theAddress is not "" then
            set shown to shown + 1
            set outText to outText & (item i of idList) & tab & theName & tab & theAddress & tab & (item i of subjList) & linefeed
          end if
        end if
      end repeat
    end if
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

# mail_compose ADDRESS SUBJECT BODY - a new message, saved to Drafts and
# left there. Nothing in this file sends without a second ask.
mail_compose() {
  local address="$1" subject="$2" body="$3"
  osascript - "$address" "$subject" "$body" <<'APPLESCRIPT' >/dev/null 2>&1
on run argv
  set theAddress to item 1 of argv
  set theSubject to item 2 of argv
  set theBody to item 3 of argv
  tell application "Mail"
    set msg to make new outgoing message with properties {subject:theSubject, content:theBody, visible:false}
    tell msg
      make new to recipient at end of to recipients with properties {address:theAddress}
    end tell
    save msg
  end tell
end run
APPLESCRIPT
}

# mail_send_composed ADDRESS SUBJECT - sends the draft matching both.
mail_send_composed() {
  local address="$1" subject="$2"
  osascript - "$address" "$subject" <<'APPLESCRIPT' 2>/dev/null
on run argv
  set wantAddress to item 1 of argv
  set wantSubject to item 2 of argv
  tell application "Mail"
    repeat with d in (messages of drafts mailbox)
      set matched to false
      try
        repeat with r in (to recipients of d)
          if (address of r) is wantAddress then set matched to true
        end repeat
      end try
      if matched and (subject of d) is wantSubject then
        send d
        return "sent"
      end if
    end repeat
  end tell
  return "missing"
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

# The newest messages, read or not. "Summarise my last five emails" is a
# different question from "what is unread", and was being answered from
# the unread list - which is why it kept saying the inbox was clear.
_mail_recent_applescript() {
  local limit="$1"
  osascript <<APPLESCRIPT
on run
  set outText to ""
  tell application "Mail"
    set total to (count of messages of inbox)
    if total > $limit then set total to $limit
    if total > 0 then
      set msgs to (messages 1 thru total of inbox)
      set dateList to date received of msgs
      set sendList to sender of msgs
      set subjList to subject of msgs

      repeat with i from 1 to (count of msgs)
        set theSender to (item i of sendList)
        try
          set theSender to extract name from theSender
        end try
        set outText to outText & (time string of (item i of dateList)) & tab & theSender & ": " & (item i of subjList) & tab & linefeed
      end repeat
    end if
  end tell
  return outText
end run
APPLESCRIPT
}

src_mail_recent() {
  have_cmd osascript || return 0
  local raw rc
  raw="$(run_with_timeout "$ORBIT_MAIL_TIMEOUT" _mail_recent_applescript "${1:-5}")"
  rc=$?
  [ "$rc" -eq 124 ] && {
    _note "Mail took longer than ${ORBIT_MAIL_TIMEOUT}s (lower ORBIT_MAIL_SCAN, or raise ORBIT_MAIL_TIMEOUT)"
    return 0
  }
  [ "$rc" -ne 0 ] && { _note "Mail: $(last_error)"; return 0; }
  printf '%s\n' "$raw" | awk -F'\t' 'NF >= 2 && $2 != ""' | tidy_time_field
}
