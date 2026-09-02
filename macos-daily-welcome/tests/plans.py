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

# save_plan adds fields of its own - who asked for the plan - so the
# function body counts as a writer too.
body = re.search(r'^save_plan\(\) \{(.*?)^\}', SRC, re.S | re.M)
if body:
    written |= set(re.findall(r'"([A-Z_]+)=', body.group(1)))

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

# ---------------------------------------------------- who is allowed to say yes
#
# A turn has two halves and the speaker check only guarded the first.
# `orbit run` is what a spoken "yes" reaches, and it never asked who had
# said it - so anybody in the room could confirm somebody else's message
# while they were still deciding.
plan_body = re.search(r'^\s*plan\)(.*?)^\s*run\)', SRC, re.S | re.M)
run_body = re.search(r'^run_plan\(\) \{(.*?)^\}', SRC, re.S | re.M)

check("there is one speaker check, not two copies of it", 1,
      len(re.findall(r'^speaker_check\(\) \{', SRC, re.M)))
check("planning a turn checks who is speaking", True,
      bool(plan_body) and "speaker_check" in plan_body.group(1))
check("and so does confirming one", True,
      bool(run_body) and "speaker_check" in run_body.group(1))

# The refusal must not also cancel what the real person asked for.
if run_body:
    guard = run_body.group(1)
    before_rm = guard.split("rm -f")[0] if "rm -f" in guard else guard
    check("the check comes before the plan is consumed", True,
          "speaker_check" in before_rm)

# A plan remembers who asked for it, and only they can confirm it.
save_body = re.search(r'^save_plan\(\) \{(.*?)^\}', SRC, re.S | re.M)
check("a plan records who asked", True,
      bool(save_body) and "BY=" in save_body.group(1))
check("and confirming compares against it", True,
      bool(run_body) and '"$BY" != "$SPEAKER"' in run_body.group(1))

# SPEAKER has to exist before anything reads it: under set -u an unset
# variable is not an empty one, it is the end of the run.
check("SPEAKER is declared up front", True,
      bool(re.search(r'^SPEAKER=""', SRC, re.M)))

print("TALLY %d %d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
