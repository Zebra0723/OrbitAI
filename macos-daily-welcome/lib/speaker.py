#!/usr/bin/env python3
"""Who is speaking.

Turns a few seconds of speech into 256 numbers - an embedding - and
compares it against the people who have enrolled. Same voice, similar
numbers; different voice, different numbers. That is the whole idea.

It is a recogniser, not a lock. Voices drift with a cold, a bad
microphone or a shouted sentence, and a recording of you sounds like you.
Treat the answer as "probably Priya", never as proof - which is why
banning a voice here refuses a request rather than securing anything.

    speaker.py enroll <name> <wav>    add a sample for someone
    speaker.py identify <wav>         name<TAB>score, or nothing
    speaker.py scores <wav>           every score, for tuning
    speaker.py health <name>          do their own samples agree
    speaker.py prune <name>           drop the ones that do not
    speaker.py list                   who is enrolled
    speaker.py forget <name>          remove them
"""

import json
import os
import sys
from pathlib import Path

STORE = Path(os.environ.get("ORBIT_SPEAKER_STORE",
                            Path.home() / ".config/daily-welcome/voices.json"))
# Cosine similarity above this counts as a match. Resemblyzer's own
# guidance puts a same-speaker pair well above 0.75 and different
# speakers well below; 0.72 leans towards admitting it does not know
# rather than naming the wrong person.
THRESHOLD = float(os.environ.get("ORBIT_SPEAKER_THRESHOLD", "0.78"))
# How far ahead of the runner-up the winner has to be. Without this, two
# people who sound alike take turns being each other.
MARGIN = float(os.environ.get("ORBIT_SPEAKER_MARGIN", "0.06"))
# How much actual speech - silence already removed - a clip needs before
# it is worth embedding at all.
MIN_VOICE_SECONDS = float(os.environ.get("ORBIT_SPEAKER_MIN_SECONDS", "1.6"))


def _fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _compat():
    """Put back the one name Resemblyzer needs and SciPy took away.

    Resemblyzer 0.1.4 opens with `from scipy.ndimage.morphology import
    binary_dilation`. SciPy deprecated that module in 1.10 and removed it
    in 1.15, so on anything installed today the import fails on line one -
    before Resemblyzer has done a thing. The function still exists, just
    under scipy.ndimage, so the old name is aliased back.

    This is the whole incompatibility: its librosa calls already use the
    modern keyword form, and it uses none of the numpy aliases that numpy
    2 removed. Checked against the 0.1.4 wheel rather than assumed.
    """
    import types
    if "scipy.ndimage.morphology" in sys.modules:
        return
    try:
        import scipy.ndimage.morphology  # noqa: F401
        return
    except ImportError:
        pass
    try:
        import scipy.ndimage as ndimage
    except ImportError:
        return          # no scipy at all; let the real error surface
    shim = types.ModuleType("scipy.ndimage.morphology")
    for name in dir(ndimage):
        if not name.startswith("_"):
            setattr(shim, name, getattr(ndimage, name))
    sys.modules["scipy.ndimage.morphology"] = shim


def _encoder():
    _compat()
    try:
        from resemblyzer import VoiceEncoder
    except Exception as exc:
        _fail("cannot load resemblyzer: %s: %s" % (type(exc).__name__, exc), 3)
    # cpu is explicit: the default probes for a GPU and says so on stderr,
    # which ends up in the middle of a spoken reply.
    return VoiceEncoder("cpu", verbose=False)


def _embed(wav_path):
    _compat()
    from resemblyzer import preprocess_wav
    wav = preprocess_wav(Path(wav_path))
    # preprocess_wav has already cut the silence out, so this is actual
    # VOICE. A second of it embeds badly - the vector wanders, and a
    # wandering vector is what lands a stranger next to somebody real.
    # Refusing is better than answering with a number nobody can trust.
    seconds = len(wav) / 16000.0
    if seconds < MIN_VOICE_SECONDS:
        _fail("only %.1fs of speech in that clip - need at least %.1fs"
              % (seconds, MIN_VOICE_SECONDS), 4)
    return _encoder().embed_utterance(wav).tolist()


def _load():
    if not STORE.exists():
        return {"people": {}}
    try:
        return json.loads(STORE.read_text())
    except (ValueError, OSError):
        return {"people": {}}


def _save(data):
    STORE.parent.mkdir(parents=True, exist_ok=True)
    STORE.write_text(json.dumps(data, indent=2))
    STORE.chmod(0o600)


def _similarity(a, b):
    dot = sum(x * y for x, y in zip(a, b))
    na = sum(x * x for x in a) ** 0.5
    nb = sum(x * x for x in b) ** 0.5
    return dot / (na * nb) if na and nb else 0.0


def _centroid(samples):
    """The average of somebody's samples - what their voice is, rather
    than what it did on one particular day.

    Scoring against the single best-matching sample was letting strangers
    in: the more samples a person has, the more chances one of them has
    of being spuriously close to whoever is talking, so every enrolment
    made the check WORSE. An average moves the other way - it gets more
    like the person and less like anybody else with every sample."""
    if not samples:
        return None
    width = len(samples[0])
    return [sum(s[i] for s in samples) / len(samples) for i in range(width)]


def _scores(here, data):
    """Everybody, best first, as (name, score, banned)."""
    rows = []
    for name, person in data["people"].items():
        centroid = _centroid(person.get("samples", []))
        if centroid is None:
            continue
        rows.append((name, _similarity(here, centroid), person.get("banned", False)))
    rows.sort(key=lambda r: r[1], reverse=True)
    return rows


def enroll(name, wav_path):
    data = _load()
    person = data["people"].setdefault(name, {"samples": [], "banned": False})
    # Several samples per person, averaged at match time: one recording of
    # one sentence in one mood is a thin thing to judge a voice by.
    person["samples"].append(_embed(wav_path))
    person["samples"] = person["samples"][-5:]
    _save(data)
    print("%s\t%d" % (name, len(person["samples"])))


def identify(wav_path):
    data = _load()
    if not data["people"]:
        return
    rows = _scores(_embed(wav_path), data)
    if not rows:
        return

    name, score, banned = rows[0]
    if score < THRESHOLD:
        return

    # Beating the threshold is not enough when somebody else is nearly as
    # close. Two people at 0.79 and 0.78 is a coin toss, and a coin toss
    # that names a person out loud is worse than saying nothing.
    if len(rows) > 1 and (score - rows[1][1]) < MARGIN:
        return

    print("%s\t%.3f\t%s" % (name, score, "banned" if banned else "ok"))


def scores(wav_path):
    """Every score, for tuning the threshold against actual voices rather
    than against a number somebody once guessed."""
    data = _load()
    if not data["people"]:
        _fail("nobody has enrolled yet", 5)
    rows = _scores(_embed(wav_path), data)
    for name, score, banned in rows:
        verdict = "match" if score >= THRESHOLD else "no"
        print("%s\t%.3f\t%s\t%s" % (name, score, verdict,
                                      "banned" if banned else "allowed"))
    if len(rows) > 1:
        print("margin\t%.3f\t(needs %.2f)" % (rows[0][1] - rows[1][1], MARGIN))


def _agreement(samples, i):
    """How well one sample fits in with the others: its BEST match.

    Not the average. With four recordings and one intruder, averaging
    against everybody drags the three real ones down too, and the report
    says all four are wrong. The question worth asking is whether a
    recording has at least one other that agrees with it - a genuine one
    always does, and the intruder has nobody.
    """
    best = 0.0
    for j, other in enumerate(samples):
        if j == i:
            continue
        score = _similarity(samples[i], other)
        if score > best:
            best = score
    return best


def health(name):
    """How well somebody's own samples agree with each other.

    A person recorded three times should look like the same person three
    times. When one sample disagrees with the rest, it is not a bad day
    or a cold - it is a recording that caught somebody else, and it drags
    the average towards them. That is how a stranger ends up being
    identified as you, and no threshold can fix it because the fault is
    in what was learnt, not in how it is compared.
    """
    data = _load()
    person = data["people"].get(name)
    if person is None:
        _fail("nobody called %s has enrolled" % name, 5)
    samples = person.get("samples", [])
    if len(samples) < 2:
        print("%s\t%d\tonly one sample, nothing to compare" % (name, len(samples)))
        return

    for i, sample in enumerate(samples):
        agreement = _agreement(samples, i)
        verdict = "ok" if agreement >= 0.80 else (
            "odd" if agreement >= 0.70 else "not the same voice")
        print("%d\t%.3f\t%s" % (i + 1, agreement, verdict))


def prune(name, floor=0.70):
    """Drops the samples that do not agree with the rest."""
    data = _load()
    person = data["people"].get(name)
    if person is None:
        _fail("nobody called %s has enrolled" % name, 5)
    samples = person.get("samples", [])
    if len(samples) < 3:
        _fail("only %d samples - too few to drop any" % len(samples), 6)

    keep = [s for i, s in enumerate(samples) if _agreement(samples, i) >= floor]
    if not keep:
        _fail("none of them agree with each other - start again with forget", 6)
    dropped = len(samples) - len(keep)
    person["samples"] = keep
    _save(data)
    print("%s\t%d\t%d" % (name, dropped, len(keep)))


def main():
    if len(sys.argv) < 2:
        _fail(__doc__, 2)
    command = sys.argv[1]

    if command == "enroll" and len(sys.argv) == 4:
        enroll(sys.argv[2], sys.argv[3])
    elif command == "identify" and len(sys.argv) == 3:
        identify(sys.argv[2])
    elif command == "health" and len(sys.argv) == 3:
        health(sys.argv[2])
    elif command == "prune" and len(sys.argv) in (3, 4):
        prune(sys.argv[2], float(sys.argv[3]) if len(sys.argv) == 4 else 0.70)
    elif command == "scores" and len(sys.argv) == 3:
        scores(sys.argv[2])
    elif command == "list":
        for name, person in sorted(_load()["people"].items()):
            print("%s\t%d\t%s" % (name, len(person.get("samples", [])),
                                  "banned" if person.get("banned") else "allowed"))
    elif command in ("ban", "unban") and len(sys.argv) == 3:
        data = _load()
        person = data["people"].get(sys.argv[2])
        if person is None:
            _fail("nobody called %s has enrolled" % sys.argv[2], 5)
        person["banned"] = (command == "ban")
        _save(data)
        print("%s\t%s" % (sys.argv[2], "banned" if person["banned"] else "allowed"))
    elif command == "forget" and len(sys.argv) == 3:
        data = _load()
        if data["people"].pop(sys.argv[2], None) is None:
            _fail("nobody called %s has enrolled" % sys.argv[2], 5)
        _save(data)
        print(sys.argv[2])
    elif command == "check":
        # Used by doctor and by setup. It reports the REAL error: saying
        # "not installed" about a package that is plainly installed sends
        # you looking in exactly the wrong place.
        _compat()
        try:
            import resemblyzer  # noqa: F401
            print("ok")
        except Exception as exc:
            _fail("%s: %s" % (type(exc).__name__, exc), 3)
    else:
        _fail(__doc__, 2)


if __name__ == "__main__":
    main()
