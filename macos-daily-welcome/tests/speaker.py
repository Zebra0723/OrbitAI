"""The voice store: enrolling, banning, and the threshold.

Everything here runs without Resemblyzer, by standing in for the one
function that needs it. What is worth testing is not whether the neural
network works - it does - but what happens around it: who counts as a
match, who is turned away, and what an unknown voice does. Those are the
parts this project got wrong.

Prints "ok NAME" / "FAIL NAME" lines for tests/run to tally.
"""
import importlib.util, io, json, os, sys, tempfile, contextlib, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
PASS = FAIL = 0


def check(what, want, got):
    global PASS, FAIL
    if want == got:
        PASS += 1
    else:
        FAIL += 1
        print("  speaker: %s\n    wanted: %r\n    got:    %r\n" % (what, want, got))


def load(store):
    """A fresh copy of speaker.py pointed at a throwaway store."""
    os.environ["ORBIT_SPEAKER_STORE"] = str(store)
    spec = importlib.util.spec_from_file_location("orbit_speaker",
                                                  ROOT / "lib" / "speaker.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def says(mod, fn, *args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        fn(*args)
    return out.getvalue().strip()


with tempfile.TemporaryDirectory() as tmp:
    store = pathlib.Path(tmp) / "voices.json"
    m = load(store)

    # Stand in for the embedding. Each "wav" is just a vector.
    ARJUN = [1.0, 0.0, 0.0]
    PRIYA = [0.0, 1.0, 0.0]
    COLD  = [0.97, 0.24, 0.0]   # Arjun with a cold: close, not identical
    m._embed = lambda path: {"arjun": ARJUN, "priya": PRIYA, "cold": COLD}[path]

    # --------------------------------------------------------- similarity
    check("a voice matches itself", 1.0, round(m._similarity(ARJUN, ARJUN), 3))
    check("and not someone else", 0.0, round(m._similarity(ARJUN, PRIYA), 3))
    check("a cold is still mostly you", True, m._similarity(ARJUN, COLD) > 0.9)

    # ------------------------------------------------------------ nobody
    # An empty store must say nothing rather than guess, or the first
    # person to speak is locked out of enrolling.
    check("an empty store names nobody", "", says(m, m.identify, "arjun"))

    # ---------------------------------------------------------- enrolling
    check("enrolling counts the sample", "Arjun\t1", says(m, m.enroll, "Arjun", "arjun"))
    check("a second sample is kept too", "Arjun\t2", says(m, m.enroll, "Arjun", "arjun"))
    saved = json.loads(store.read_text())
    check("under the name given", ["Arjun"], list(saved["people"]))
    check("the file is not world readable", "600", oct(store.stat().st_mode)[-3:])

    # -------------------------------------------------------- identifying
    check("it knows you", "Arjun", says(m, m.identify, "arjun").split("\t")[0])
    check("and says you are allowed", "ok", says(m, m.identify, "arjun").split("\t")[2])
    check("a cold does not make you a stranger", "Arjun",
          says(m, m.identify, "cold").split("\t")[0])
    # The whole point: a voice it does not know is not the nearest voice
    # it does know.
    check("a stranger is nobody, not the closest match", "",
          says(m, m.identify, "priya"))

    # ---------------------------------------------------- letting nobody in
    #
    # The complaint that made this: "it is not very good at identifying
    # not enrolled voices". Two things were wrong. It scored against the
    # single closest SAMPLE, so every extra enrolment gave a stranger
    # another chance of landing near one of them - the check got worse
    # the more you taught it. And anything past 0.72 was a match, which
    # different speakers reach easily on a short clip.
    STRANGER = [0.75, 0.0, 0.6614]   # 0.75 against Arjun: close, not him
    TWIN     = [0.94, 0.34, 0.0]     # someone who really does sound like him
    m._embed = lambda path: {"arjun": ARJUN, "priya": PRIYA, "cold": COLD,
                             "stranger": STRANGER, "twin": TWIN}[path]

    check("a stranger who is merely close is still a stranger", "",
          says(m, m.identify, "stranger"))

    # Under the old bar this exact voice was let in as Arjun.
    old_threshold, m.THRESHOLD = m.THRESHOLD, 0.72
    check("and would have been let in under the old bar", "Arjun",
          says(m, m.identify, "stranger").split("\t")[0])
    m.THRESHOLD = old_threshold

    # Teaching it more about Arjun must not make it worse at strangers.
    # Against the closest sample it did; against the average it cannot.
    for _ in range(4):
        says(m, m.enroll, "Arjun", "cold")
    check("more enrolments do not let the stranger in", "",
          says(m, m.identify, "stranger"))
    check("and you are still you", "Arjun",
          says(m, m.identify, "arjun").split("\t")[0])

    # Two people scoring alike is a coin toss, and a coin toss that says
    # a name out loud is worse than saying nothing.
    says(m, m.enroll, "Twin", "twin")
    check("no answer when two voices are neck and neck", "",
          says(m, m.identify, "arjun"))
    data = m._load(); data["people"].pop("Twin", None); m._save(data)
    check("and an answer again once they are not", "Arjun",
          says(m, m.identify, "arjun").split("\t")[0])

    # The scores are readable, so the bar can be set against real voices
    # instead of against a number somebody guessed.
    says(m, m.enroll, "Priya", "priya")
    listing = says(m, m.scores, "arjun")
    rows = [l for l in listing.splitlines() if not l.startswith("margin")]
    check("every enrolled voice is scored", 2, len(rows))
    check("and the margin is shown", True, "margin" in listing)
    check("best first", "Arjun", rows[0].split("\t")[0])
    data = m._load(); data["people"].pop("Priya", None); m._save(data)

    # ------------------------------------------------------------ banning
    m.STORE = store
    data = m._load(); data["people"]["Arjun"]["banned"] = True; m._save(data)
    check("a banned voice is still recognised", "Arjun",
          says(m, m.identify, "arjun").split("\t")[0])
    check("and marked as banned", "banned", says(m, m.identify, "arjun").split("\t")[2])

    # ------------------------------------------------------------ samples
    for _ in range(8):
        says(m, m.enroll, "Arjun", "arjun")
    saved = json.loads(store.read_text())
    check("only the last five samples are kept", 5,
          len(saved["people"]["Arjun"]["samples"]))
    check("banning survives re-enrolling", True,
          saved["people"]["Arjun"]["banned"])

    # ------------------------------------------------------- a broken store
    store.write_text("{ this is not json")
    check("a corrupt store is empty, not fatal", {"people": {}}, m._load())

# tests/run reads this last line and folds it into the totals.
print("TALLY %d %d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
