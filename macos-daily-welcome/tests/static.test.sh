#!/bin/bash
# Things that should never have got as far as running.
#
# Half the outages in this project were not logic at all: a script that
# would not parse, a Swift file with a brace missing, an entry point that
# forgot to load a library. None of those need a Mac to catch.

test_sandbox

# Every shell file parses.
for f in "$TEST_ROOT"/bin/* "$TEST_ROOT"/lib/*.sh "$TEST_ROOT"/*.sh \
         "$TEST_ROOT"/tests/run "$TEST_ROOT"/tests/*.test.sh; do
  [ -f "$f" ] || continue
  case "$f" in *.py) continue ;; esac
  succeeds "${f#$TEST_ROOT/} parses" bash -n "$f"
done

# Every Python file compiles.
for f in "$TEST_ROOT"/lib/*.py "$TEST_ROOT"/tests/*.py "$TEST_ROOT"/web/*.py; do
  [ -f "$f" ] || continue
  succeeds "${f#$TEST_ROOT/} compiles" python3 -m py_compile "$f"
done

# Swift cannot be compiled without a Mac, but a file that does not
# balance is a file that will not build, and finding that out at install
# time is finding it out too late.
for f in "$TEST_ROOT"/menubar/*.swift; do
  [ -f "$f" ] || continue
  swift_name="${f#$TEST_ROOT/}"
  counts="$(python3 - "$f" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
# Strings BEFORE comments. The other way round, the "//" inside a URL in
# a string literal reads as the start of a comment and eats the rest of
# the line - including whatever brackets were closing on it.
src = re.sub(r'"""(?:.|\n)*?"""', '""', src)
src = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', src)
src = re.sub(r'//[^\n]*', '', src)
src = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
for op, cl in (("{", "}"), ("(", ")"), ("[", "]")):
    print("%d %d" % (src.count(op), src.count(cl)))
PY
)"
  while read -r opened closed; do
    ok "$swift_name balances" "$opened" "$closed"
  done <<< "$counts"
done

# The web pages are wired up by a registry, not by inline handlers -
# Chromium has a `command` property on elements that shadowed a global
# function of the same name, and every button on the site stopped
# working with no error anywhere.
if [ -d "$TEST_ROOT/web/orbitai" ]; then
  # In the markup, that is. app.js explains at length why they are gone.
  inline="$(grep -rl 'onclick=' "$TEST_ROOT/web/orbitai" --include='*.html' 2>/dev/null | head -5)"
  ok "no inline onclick handlers" "" "$inline"
fi
