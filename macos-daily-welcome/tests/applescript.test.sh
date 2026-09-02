#!/bin/bash
# The AppleScript, as it actually comes out.
#
# These scripts are built by shell heredocs, and the two kinds of heredoc
# behave in opposite ways: <<SCRIPT expands $variables, <<'SCRIPT' leaves
# them alone. Pick the wrong one and the script Mail receives contains a
# literal "$limit" - which is a syntax error at the far end of an Apple
# Event, reported as nothing much and seen from here as "Mail took too
# long" or an empty answer.
#
# osascript is not on this machine, so it is stood in for by something
# that prints what it was handed. That is enough to check the script that
# would have been sent.

test_sandbox
load_orbit

stub_dir="$WELCOME_STATE_DIR/bin"
mkdir -p "$stub_dir"
cat > "$stub_dir/osascript" <<'STUB'
#!/bin/sh
# Prints the script it was given, so a test can look at it.
cat
STUB
chmod +x "$stub_dir/osascript"

script_of() { ( export PATH="$stub_dir:$PATH"; "$@" 2>/dev/null ); }

check_script() {
  local name="$1" body="$2"

  # An unexpanded shell variable. AppleScript has no $, so any that
  # survives is a heredoc quoted when it should not have been.
  local leftover
  leftover="$(printf '%s' "$body" | grep -oE '\$[A-Za-z_][A-Za-z0-9_]*' | sort -u | tr '\n' ' ')"
  ok "$name has no unexpanded shell variables" "" "$leftover"

  # And it is not empty, or the check above proves nothing.
  ok "$name produced a script" "yes" "$([ ${#body} -gt 40 ] && echo yes || echo no)"

  # Blocks that open and never close.
  local opens closes
  for pair in "tell:end tell" "repeat:end repeat" "try:end try" "on run:end run"; do
    opens="$(printf '%s\n' "$body" | grep -cE "^[[:space:]]*${pair%%:*}( |$)")"
    closes="$(printf '%s\n' "$body" | grep -cE "^[[:space:]]*${pair##*:}([[:space:]]|$)")"
    ok "$name balances ${pair%%:*}" "$opens" "$closes"
  done
}

check_script "unread count"  "$(script_of _mail_unread_count)"
check_script "unread scan"   "$(script_of _mail_unread_applescript 16)"
check_script "unread deep"   "$(script_of _mail_unread_deep 16)"
check_script "awaiting"      "$(script_of _mail_awaiting_applescript 7 25)"
check_script "recent"        "$(script_of _mail_recent_applescript 10)"
check_script "draft reply"   "$(script_of _mail_draft_reply 1234 "on my way")"
check_script "compose"       "$(script_of _mail_compose a@b.c Subject Body)"
check_script "send composed" "$(script_of _mail_send_composed a@b.c Subject)"

# The limits really do reach the script, rather than the script quietly
# scanning everything.
body="$(script_of _mail_unread_applescript 16)"
contains "the row limit is in the script" "16" "$body"
contains "and so is the scan window" "$ORBIT_MAIL_SCAN" "$body"

body="$(script_of _mail_send_composed a@b.c Subject)"
lacks "sending does not walk every draft" "repeat with d in (messages of drafts mailbox)" "$body"

# Messages, the same way.
if declare -f _messages_applescript >/dev/null 2>&1; then
  check_script "messages" "$(script_of _messages_applescript 2 60)"
fi
