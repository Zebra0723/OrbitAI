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
THRESHOLD = float(os.environ.get("ORBIT_SPEAKER_THRESHOLD", "0.72"))


def _fail(message, code=1):
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _encoder():
    try:
        from resemblyzer import VoiceEncoder
    except ImportError:
        _fail("resemblyzer is not installed - run: daily-welcome --setup-speaker", 3)
    # cpu is explicit: the default probes for a GPU and says so on stderr,
    # which ends up in the middle of a spoken reply.
    return VoiceEncoder("cpu", verbose=False)


def _embed(wav_path):
    from resemblyzer import preprocess_wav
    wav = preprocess_wav(Path(wav_path))
    # Under about a second there is not enough voice to characterise.
    if len(wav) < 16000:
        _fail("that clip is too short to recognise a voice in", 4)
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
    here = _embed(wav_path)
    best, best_score = None, 0.0
    for name, person in data["people"].items():
        for sample in person.get("samples", []):
            score = _similarity(here, sample)
            if score > best_score:
                best, best_score = name, score
    if best is None or best_score < THRESHOLD:
        return
    banned = data["people"][best].get("banned", False)
    print("%s\t%.3f\t%s" % (best, best_score, "banned" if banned else "ok"))


def main():
    if len(sys.argv) < 2:
        _fail(__doc__, 2)
    command = sys.argv[1]

    if command == "enroll" and len(sys.argv) == 4:
        enroll(sys.argv[2], sys.argv[3])
    elif command == "identify" and len(sys.argv) == 3:
        identify(sys.argv[2])
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
        # Is the library actually here? Used by doctor and by setup.
        try:
            import resemblyzer  # noqa: F401
            print("ok")
        except ImportError:
            _fail("not installed", 3)
    else:
        _fail(__doc__, 2)


if __name__ == "__main__":
    main()
