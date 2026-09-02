#!/bin/bash
# Unread iMessages, against a database shaped like the real one.
#
# The query ran for months and returned nothing, every time, and looked
# exactly like an empty inbox. strftime returns TEXT; SQLite sorts every
# integer below every string; so "message date > that string" was false
# for every message that has ever been sent. Nothing errored, nothing
# was logged, and the messages section was simply always absent.
#
# sqlite3 is not on this machine either, so it is stood in for by python,
# which has the same engine underneath. The SQL under test is the real
# SQL, run against real rows.

test_sandbox
load_orbit

stub_dir="$WELCOME_STATE_DIR/bin"
mkdir -p "$stub_dir"
cat > "$stub_dir/sqlite3" <<'STUB'
#!/usr/bin/env python3
"""Enough of the sqlite3 CLI for the query under test: the flags it is
called with, the separator it is asked for, and SQL on stdin."""
import sqlite3, sys
args, sep, db, inline = sys.argv[1:], "|", None, None
i = 0
while i < len(args):
    if args[i] in ("-readonly", "-header", "-noheader"): i += 1
    elif args[i] == "-separator": sep = args[i + 1]; i += 2
    elif db is None: db = args[i]; i += 1
    else: inline = args[i]; i += 1
# SQL can come as an argument or on stdin. Reading stdin regardless meant
# the probe - which passes its query as an argument - waited forever for
# input nobody was going to send.
sql = inline if inline is not None else sys.stdin.read()
sql = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("."))
try:
    conn = sqlite3.connect(db)
    for row in conn.execute(sql):
        print(sep.join("" if v is None else str(v) for v in row))
except sqlite3.Error as error:
    print(str(error), file=sys.stderr)
    raise SystemExit(1)
STUB
chmod +x "$stub_dir/sqlite3"

# A database with the columns the query actually names.
export MESSAGES_DB="$WELCOME_STATE_DIR/chat.db"
python3 - "$MESSAGES_DB" <<'PY'
import sqlite3, sys, time
APPLE = 978307200
db = sqlite3.connect(sys.argv[1])
db.executescript("""
CREATE TABLE handle (ROWID INTEGER PRIMARY KEY, id TEXT);
CREATE TABLE chat (ROWID INTEGER PRIMARY KEY, display_name TEXT);
CREATE TABLE message (ROWID INTEGER PRIMARY KEY, text TEXT, handle_id INTEGER,
                      is_from_me INTEGER, is_read INTEGER, date INTEGER);
CREATE TABLE chat_message_join (chat_id INTEGER, message_id INTEGER);
INSERT INTO handle VALUES (1, '+15551234567'), (2, 'priya@example.com');
INSERT INTO chat VALUES (1, 'Mama'), (2, NULL);
""")
def when(seconds_ago):
    return (int(time.time()) - seconds_ago - APPLE) * 1_000_000_000
rows = [
    (1, 'running late',      1, 0, 0, when(3600)),      # unread, an hour ago
    (2, 'also bring milk',   1, 0, 0, when(3000)),      # unread, same person
    (3, 'see you then',      2, 0, 0, when(7200)),      # unread, someone else
    (4, 'on my way',         1, 1, 0, when(1800)),      # from me
    (5, 'old news',          1, 0, 0, when(86400 * 30)),# too old
    (6, 'already seen',      1, 0, 1, when(600)),       # read
]
db.executemany("INSERT INTO message VALUES (?,?,?,?,?,?)", rows)
db.executemany("INSERT INTO chat_message_join VALUES (?,?)",
               [(1, 1), (1, 2), (2, 3), (1, 4), (1, 5), (1, 6)])
db.commit()
PY

read_messages() { ( export PATH="$stub_dir:$PATH"; src_messages 2>/dev/null ); }
out="$(read_messages)"

# The newest from each sender is the one shown; the rest are counted.
contains "the newest unread from Mama is what is read out" "also bring milk" "$out"
contains "and so is one from somebody else"                  "see you then" "$out"
contains "the sender is named"                               "Mama"         "$out"

lacks "what I sent is not news"          "on my way"    "$out"
lacks "what I have read is not news"     "already seen" "$out"
lacks "a month ago is not news"          "old news"     "$out"

# One line per sender, with the rest counted rather than listed.
contains "a second message from the same person is counted" "(+1 more)" "$out"
lacks "and the older one is not also listed"                 "running late" "$out"
ok "one line per sender" "2" "$(printf '%s\n' "$out" | grep -c .)"

# The shape the briefing expects: time, then text, then an empty field.
ok "each row has three fields" "2" \
   "$(printf '%s\n' "$out" | awk -F'\t' 'NF == 3' | grep -c .)"
ok "the time comes first" "2" \
   "$(printf '%s\n' "$out" | awk -F'\t' '$1 ~ /^[0-9]{1,2}:[0-9]{2}$/' | grep -c .)"

# A window of one day leaves out what is older than a day.
out="$(WELCOME_MESSAGES_SINCE_DAYS=0 read_messages)"
ok "a zero-day window is empty" "" "$(printf '%s' "$out" | tr -d '[:space:]')"
