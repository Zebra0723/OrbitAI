"""A variable nobody declared is a crash waiting for the right command.

Every script here runs under `set -u`, so reading a variable that was
never set does not give an empty string - it ends the shell, on the spot,
usually without printing anything anybody sees. WELCOME_PIPER_BIN was
like that: `tts_backend` asks `piper_available` whether piper is there,
`piper_available` reads it, and on a Mac the whole run died in the middle
of working out how to speak.

So: every uppercase variable read in bin/ or lib/ has to be one that
config.sh declares, or that the same file assigns, or that the
environment provides. Anything else is reported.

Prints failures and a TALLY line for tests/run.
"""
import re, pathlib, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
config = (ROOT/"lib/config.sh").read_text()
defaults = set(re.findall(r':\s*"\$\{([A-Z_][A-Z0-9_]*):[=-]', config))
defaults |= set(re.findall(r'^([A-Z_][A-Z0-9_]*)=', config, re.M))

ENV = set("""HOME PATH USER SHELL TMPDIR LANG LC_ALL PWD OLDPWD TERM
LOGNAME EDITOR SSH_AUTH_SOCK DISPLAY HOSTNAME BASH_SOURCE FUNCNAME
IFS RANDOM SECONDS LINENO PPID UID EUID BASH_VERSION OSTYPE REPLY
PIPESTATUS BASH_REMATCH COLUMNS LINES""".split())

# Set by the entry point before it sources anything.
SET_BY_ENTRY = {"ROOT", "SELF"}
bad = []

files = sorted(list((ROOT/"lib").glob("*.sh")) + [p for p in (ROOT/"bin").iterdir() if p.is_file()])
COMMENT = re.compile(r'(?m)(?<![\\$])(?:^|(?<=\s))#.*$')

def strip(text):
    """Comments are not code. `$KEY` in a note about how to pipe a key in
    is not a variable anything reads."""
    return COMMENT.sub("", text)

allsrc = {p: strip(p.read_text()) for p in files}

for p, src in allsrc.items():
    # Reads without a default: "$FOO" or ${FOO} but not ${FOO:-...} etc.
    reads = set()
    for m in re.finditer(r'\$\{?([A-Z_][A-Z0-9_]*)\}?', src):
        after = src[m.end():m.end()+2]
        if m.group(0).startswith("${") and after.startswith(":"): continue
        reads.add(m.group(1))
    for m in re.finditer(r'\$\{([A-Z_][A-Z0-9_]*)[:#%/+-]', src):
        reads.discard(m.group(1))
    # Assigned somewhere in the same file, or exported, or a local.
    assigned = set(re.findall(r'^\s*(?:export\s+|local\s+|declare\s+)?([A-Z_][A-Z0-9_]*)=', src, re.M))
    assigned |= set(re.findall(r'local\s+((?:[A-Z_][A-Z0-9_]*[= ]?[^\n;]*))', src))
    assigned |= set(re.findall(r'\b([A-Z_][A-Z0-9_]*)=', src))
    assigned |= set(re.findall(r'for\s+([A-Z_][A-Z0-9_]*)\s+in', src))
    assigned |= set(re.findall(r'read\s+(?:-r\s+)?([A-Z_][A-Z0-9_]*)', src))
    missing = sorted(reads - assigned - defaults - ENV - SET_BY_ENTRY)
    for name in missing:
        bad.append((p, name))

for p, name in bad:
    print("  unbound: %s reads $%s, which nothing declares\n"
          "    add a default to lib/config.sh, or set it in %s\n"
          % (p.relative_to(ROOT).as_posix(), name,
             p.relative_to(ROOT).as_posix()))
print("TALLY %d %d" % (0 if bad else 1, len(bad)))
sys.exit(1 if bad else 0)
