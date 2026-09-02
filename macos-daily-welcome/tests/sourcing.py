"""Does every entry point load the libraries its libraries need?

The libraries call each other freely, and nothing checks that the script
at the top actually sourced all of them. When it has not, the failure is a
command that quietly does nothing at the one moment it was asked for -
`daily-welcome` calling `memory_events` that was never defined, say. Bash
finds that at the instant of the call and not a second sooner.

This walks each entry point, works out every function it can reach through
what it sources, and reports any call to a function that exists in this
repo but is not in that set.

Exit code is 1 when something is missing, so tests/run can fail on it.
"""
import re, pathlib, subprocess, sys
ROOT = pathlib.Path(__file__).resolve().parent.parent
# Indented too: a function can be defined inside another one.
DEFN = re.compile(r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*\(\)\s*\{', re.M)
SOURCE = re.compile(r'^\s*\.\s+"\$ROOT/(lib/[a-z_]+\.sh)"', re.M)
ALL_LIB = {p.name: p for p in sorted((ROOT / "lib").glob("*.sh"))}

def defs(p): return set(DEFN.findall(p.read_text()))
SQUOTE = re.compile(r"'[^']*'")

def calls(p):
    text, out = p.read_text(), set()
    # A name inside single quotes is help text, an awk program or a
    # printf format - never a call. Leaving them in reported the word
    # "pause_on_call" out of a usage message as a missing function.
    text = SQUOTE.sub("''", text)
    for line in text.splitlines():
        line = line.split('#')[0]
        for m in re.finditer(r'(?:^|[;&|(]|\bthen\b|\bdo\b|\belse\b|\bif\b|\!|\$\()\s*([a-z_][a-z0-9_]{2,})\s', line):
            out.add(m.group(1))
    for m in re.finditer(r'\$\(\s*([a-z_][a-z0-9_]{2,})[\s)]', text):
        out.add(m.group(1))
    return out

builtins = set("""cd echo printf read local return exit test true false set shift eval exec
export trap unset source break continue declare command builtin getopts type
then else elif fi done esac case for while until function time""".split())

# Commands that exist on a Mac and not on whatever this is running on.
MACOS = set("""sw_vers osascript afplay say pbcopy pbpaste tccutil launchctl
softwareupdate networksetup diskutil defaults open sqlite3 security
plutil codesign xcrun swiftc caffeinate mdfind system_profiler""".split())

def variables(text):
    """Names used as variables here, which are therefore not calls."""
    return (set(re.findall(r'\b([a-z_][a-z0-9_]*)=', text))
            | set(re.findall(r'\$\{?([a-z_][a-z0-9_]*)', text)))

rows = []
gone = []
for entry in ["bin/orbit", "bin/daily-welcome", "bin/doctor"]:
    ep = ROOT / entry
    loaded = SOURCE.findall(ep.read_text())
    available = defs(ep)
    for lib in loaded: available |= defs(ROOT / lib)

    for lib in loaded:
        libp = ROOT / lib
        for name in sorted(calls(libp) - available - builtins):
            if subprocess.run(["which", name], capture_output=True).returncode == 0: continue
            owner = [n for n, p in ALL_LIB.items() if name in defs(p)]
            if owner:
                rows.append((entry, lib.split('/')[-1], name, owner[0]))

    # And the entry point's calls to itself. Deleting a function that is
    # still called reads as a tidy-up right until the one command that
    # needed it, and nothing anywhere says a word.
    # Only names with an underscore. Working out what is a call and what
    # is a word in a case label or a sentence of help text is not worth
    # doing properly, and every function in this repo is snake_case while
    # no English word in it has an underscore in the middle.
    local_vars = variables(ep.read_text())
    for name in sorted(calls(ep) - available - builtins - MACOS - local_vars):
        if "_" not in name: continue
        if subprocess.run(["which", name], capture_output=True).returncode == 0: continue
        owner = [n for n, p in ALL_LIB.items() if name in defs(p)]
        gone.append((entry, name, owner[0] if owner else None))

for e, lib, name, owner in rows:
    print("  sourcing: %s loads %s, which calls %s\n"
          "    %s is defined in lib/%s, which %s never sources\n"
          % (e, lib, name, name, owner, e))
for e, name, owner in gone:
    where = ("lib/%s, which it never sources" % owner) if owner \
            else "nowhere in this repo"
    print("  sourcing: %s calls %s\n    %s is defined in %s\n"
          % (e, name, name, where))
bad = len(rows) + len(gone)
print("TALLY %d %d" % (0 if bad else 2, bad))
sys.exit(1 if bad else 0)
