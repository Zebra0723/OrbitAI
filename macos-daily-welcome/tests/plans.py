"""A plan is written by one half of orbit and read by the other.

`orbit plan` works out what you meant and writes it down; `orbit run`
picks it up after you say yes. They agree on the field names by
convention and nothing checks it, so when plan_mail_send started writing
ADDRESS and SUBJECT and the reader was never taught about them, the
result was `"$ADDRESS"` as an unbound variable - which under `set -u`
kills the run. No email, no error anybody heard, and a bug report that
said mail "isn't really working".

Prints failures and a TALLY line for tests/run.
"""
import re, pathlib, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = (ROOT / "bin" / "orbit").read_text()
PASS = FAIL = 0


def check(what, want, got):
    global PASS, FAIL
    if want == got:
        PASS += 1
    else:
        FAIL += 1
        print("  plans: %s\n    wanted: %r\n    got:    %r\n" % (what, want, got))


# Every "KEY=..." handed to save_plan. A call can be wrapped over several
# lines with backslashes, so the statement is taken to the first line that
# does not continue.
written = set()
lines = SRC.splitlines()
for i, line in enumerate(lines):
    if "save_plan " not in line:
        continue
    statement = line
    while statement.rstrip().endswith("\\") and i + 1 < len(lines):
        i += 1
        statement += lines[i]
    written |= set(re.findall(r'"([A-Z_]+)=', statement))

# Every "KEY=*)" the reader knows how to take back out.
read = set(re.findall(r'^\s*([A-Z_]+)=\*\)', SRC, re.M))

check("plans are written and read by the same names", set(), written - read)
check("and nothing is read that is never written", set(), read - written)

# There is no point checking the names match if we found none of them.
check("the writers were found", True, len(written) >= 6)
check("the reader was found", True, len(read) >= 6)

# Anything the reader unpacks has to be declared, or `set -u` turns the
# first use into a fatal error rather than an empty string.
declared = set()
for m in re.finditer(r'^\s*local\s+((?:[A-Z_]+=""\s*)+)$', SRC, re.M):
    declared |= set(re.findall(r'([A-Z_]+)=""', m.group(1)))
check("every field the reader unpacks is declared first", set(), read - declared)

print("TALLY %d %d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
