#!/usr/bin/env python3
"""OrbitAI console - a local web app for managing the assistant.

Everything it shows is read from the same files and commands the
assistant itself uses, and everything it changes is written back to
them, so the console and the voice never disagree about what the
settings are.

It binds to localhost, unless started with `orbit console --phone`, which
puts it on the Wi-Fi for as long as that runs so a phone can reach it.
Off the loopback address the pairing token is required for everything -
see Console.from_this_mac for why "same origin" stops being an answer the
moment a second device can ask.

Started with `orbit console`; stopped with ctrl-c.
"""

import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOME = Path.home()
CONFIG = HOME / ".config" / "daily-welcome" / "config.sh"
TOKEN_FILE = HOME / ".config" / "daily-welcome" / "console-token"
CONTACTS = HOME / ".config" / "daily-welcome" / "contacts.conf"
MACROS = HOME / ".config" / "daily-welcome" / "macros.conf"
STATE = Path(os.environ.get("WELCOME_STATE_DIR", HOME / ".local/state/daily-welcome"))

ORBIT = str(ROOT / "bin" / "orbit")
WELCOME = str(ROOT / "bin" / "daily-welcome")

# Settings the console is allowed to write, with the kind of control each
# one deserves. Anything not listed here stays editable only by hand -
# the console is not a text editor with extra steps.
SETTINGS = [
    ("WELCOME_NAME", "text", "Your name", "What it calls you, on screen and out loud."),
    ("ORBIT_WAKE_WORD", "text", "Wake word", "Ordinary words are recognised far better than invented ones."),
    ("ORBIT_WAKE_ALIASES", "text", "Also counts as the wake word",
     "Separated by |. Whatever the recogniser hears instead of your wake word, add it here."),
    ("ORBIT_GREETING", "text", "Greeting", "The answer to the wake word on its own."),
    ("ORBIT_SIGNOFF", "text", "Sign-off", "What ends a conversation."),
    ("WELCOME_HONORIFIC", "text", "Honorific", "How the briefing addresses you. Empty for just your name."),
    ("WELCOME_ELEVEN_VOICE_ID", "text", "Voice ID", "The ElevenLabs voice. An ID always works; a name only if it is in your account."),
    ("WELCOME_ELEVEN_SPEED", "number", "Speed", "1.0 is normal."),
    ("WELCOME_ELEVEN_STABILITY", "number", "Stability", "Lower is more expressive, higher is steadier."),
    ("WELCOME_VOLUME", "number", "Volume", "0 to 1."),
    ("ORBIT_LISTEN", "toggle", "Listening", "Opens the microphone for the wake word."),
    ("ORBIT_CONVERSATION", "toggle", "Conversation mode", "Keep listening after a reply until you say thanks."),
    ("ORBIT_MATCH_TONE", "toggle", "Match my tone", "Clipped questions get clipped answers."),
    ("ORBIT_PROACTIVE", "toggle", "Speak first", "Meetings starting, jobs finishing, mail from the list."),
    ("ORBIT_FREEFORM", "toggle", "Freeform commands", "Claude writes a command for anything not in the catalogue."),
    ("ORBIT_ONDEVICE", "toggle", "On-device recognition", "Keeps audio on this Mac. Hears invented names badly."),
    ("ORBIT_PAUSE_ON_CALL", "toggle", "Pause while you're on a call", "Shuts the microphone whenever another app is recording."),
    ("ORBIT_CALL_IGNORE", "text", "Never counts as a call", "Bundle ids to ignore, separated by commas."),
    ("ORBIT_CONFIRM_CALLS", "toggle", "Confirm calls", "Say the name back before dialling."),
    ("ORBIT_REQUIRE_UNLOCKED", "toggle", "Only when unlocked", "Ignore commands while the screen is locked."),
    ("ORBIT_VIPS", "text", "Interrupt for", "Names worth interrupting you for, separated by |."),
    ("WELCOME_SECTIONS", "text", "Briefing sections", "In order: reminders calendar messages mail claude tasks."),

    # Everything below here used to need a terminal. That is fine for the
    # person who wrote it and is the whole barrier for everybody else, so
    # anything you would reach for `daily-welcome --something` to change
    # is a control on a page instead.
    ("WELCOME_VOICE", "select", "Voice",
     "system means whatever you picked in System Settings, which is the only way to reach a Siri voice.",
     "@voices"),
    ("WELCOME_TTS", "select", "Who speaks",
     "auto tries ElevenLabs, then piper, then the built-in voice.",
     ["auto", "elevenlabs", "piper", "say"]),
    ("WELCOME_SPEAK_RATE", "number", "Speaking rate", "Words per minute. 175 is normal."),
    ("WELCOME_PAUSE", "select", "Pauses",
     "How long it rests at a comma.", ["short", "natural", "none"]),
    ("WELCOME_PAUSE_MS", "number", "Pause length",
     "Milliseconds at a comma, when pauses are short. 210 is the default."),
    ("WELCOME_SAY_EMPHASIS", "toggle", "Lean on the important words",
     "overdue, unread, late. Blunt on some voices."),
    ("WELCOME_SAY_MODULATION", "number", "Pitch movement",
     "0 to 100 for the built-in voice. Empty means the voice's own setting."),

    ("ORBIT_NLU", "select", "How it understands you",
     "A model is far better at phrasings nobody anticipated. rules needs no key at all.",
     ["claude", "openai", "rules"]),
    ("ORBIT_OPENAI_BASE", "select", "Which service",
     "Anything speaking the OpenAI shape. Groq and Gemini have free tiers.",
     ["https://api.groq.com/openai/v1",
      "https://generativelanguage.googleapis.com/v1beta/openai",
      "http://localhost:11434/v1"]),
    ("ORBIT_OPENAI_MODEL", "text", "Model",
     "Leave it and let Orbit ask the service what it serves today."),

    ("ORBIT_SPEAKER_ID", "toggle", "Recognise voices",
     "Keeps a few seconds of microphone audio on this Mac to tell people apart."),
    ("ORBIT_SPEAKER_REQUIRE_ENROLLED", "toggle", "Turn away voices it does not know",
     "Off unless you have checked it recognises you. A wrong guess stops it working for you."),
    ("ORBIT_BYPASS_CODE", "text", "Bypass code",
     "Said out loud to wave somebody through for one conversation."),
]

TOGGLES = {name for name, kind, *_ in SETTINGS if kind == "toggle"}


def installed_voices():
    """The voices `say` can name, plus "system" for the one macOS is set
    to - which is the only route to a Siri voice, since `say -v` cannot
    ask for one."""
    ok, out = run(["/bin/bash", "-c",
                   "say -v '?' 2>/dev/null | sed -E 's/[[:space:]]+[a-z]{2}(_[A-Z]{2})?[[:space:]]+#.*$//; s/[[:space:]]+$//'"],
                  timeout=15)
    voices = [v.strip() for v in out.splitlines() if v.strip()] if ok else []
    return ["system"] + voices


def setting_rows():
    """The settings, with any @-reference in the choices resolved."""
    values = config_values()
    rows = []
    for name, kind, label, help_, *rest in SETTINGS:
        choices = rest[0] if rest else None
        if choices == "@voices":
            choices = installed_voices()
        row = {"key": name, "kind": kind, "label": label, "help": help_,
               "value": values.get(name, "")}
        if choices:
            row["choices"] = choices
            # A value that is not on the list still has to be shown, or
            # opening the page would silently change it.
            if row["value"] and row["value"] not in choices:
                row["choices"] = [row["value"]] + list(choices)
        rows.append(row)
    return rows


def token():
    """The pairing token.

    Without this, any web page open in any tab could drive this Mac: a
    browser will happily let a site talk to localhost, and the assistant
    can send mail and place calls. The deployed console asks for the token
    once and keeps it; the local page is same-origin and doesn't need it.
    """
    if not TOKEN_FILE.exists():
        TOKEN_FILE.parent.mkdir(parents=True, exist_ok=True)
        TOKEN_FILE.write_text(secrets.token_urlsafe(24) + "\n")
        TOKEN_FILE.chmod(0o600)
    return TOKEN_FILE.read_text().strip()


# The pairing code, and the phone it lets in.
#
# A phone cannot be same-origin-trusted the way the Mac's own browser is:
# on a shared Wi-Fi, "same origin" is anybody in the building. So a phone
# is let in only by presenting the token, and the token is only handed
# over in exchange for a six-digit code that the Mac shows on its own
# screen. Somebody who is not standing in front of the Mac never sees it.
PAIR = {"code": "", "expires": 0.0, "tries": 0}
PAIR_MINUTES = 10
PAIR_TRIES = 5


def pair_code(fresh=False):
    """The code currently on the Mac's screen, minted on demand."""
    now = time.time()
    if fresh or not PAIR["code"] or now > PAIR["expires"]:
        # secrets, not random: this is the whole lock. randbelow, not a
        # slice of a hex token, because a code has to be six DIGITS to be
        # readable off a screen and typed on a phone.
        PAIR.update(code="%06d" % secrets.randbelow(1000000),
                    expires=now + PAIR_MINUTES * 60, tries=0)
    return PAIR["code"]


def pair_open():
    """Is there a code somebody could still use?"""
    return bool(PAIR["code"]) and time.time() <= PAIR["expires"] \
        and PAIR["tries"] < PAIR_TRIES


def pair_redeem(given):
    """Trades a correct code for the token, once."""
    given = re.sub(r"\D", "", str(given or ""))
    if not PAIR["code"] or time.time() > PAIR["expires"]:
        return None, "that code has expired - ask the Mac for a new one"
    # Burnt by wrong guesses, which is a different thing from expired and
    # worth saying so: it means somebody has been trying. The code itself
    # is deliberately left in place rather than blanked, so that this
    # answer survives instead of decaying into "expired".
    if PAIR["tries"] >= PAIR_TRIES:
        return None, "too many wrong tries - ask the Mac for a new one"
    if not secrets.compare_digest(given, PAIR["code"]):
        PAIR["tries"] += 1
        left = PAIR_TRIES - PAIR["tries"]
        if left <= 0:
            return None, "too many wrong tries - ask the Mac for a new one"
        return None, "not that code (%d %s left)" % (left, "try" if left == 1 else "tries")
    # Spent. A code read off a shoulder five minutes later is no use.
    PAIR["code"] = ""
    return token(), ""


def lan_mode():
    return os.environ.get("ORBIT_CONSOLE_LAN", "") == "1"


def lan_addresses(port):
    """Where a phone on the same Wi-Fi should point its browser.

    The .local name first: it survives the router handing out a
    different address tomorrow, which a typed-in IP does not.
    """
    places = []
    host = os.uname().nodename
    if host:
        # macOS reports "Name.local" already; a bare name gets the suffix
        # so Bonjour can answer for it.
        name = host if host.endswith(".local") else host + ".local"
        places.append(f"http://{name}:{port}")
    seen = set(places)
    try:
        import socket
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            address = info[4][0]
            if address.startswith("127."):
                continue
            url = f"http://{address}:{port}"
            if url not in seen:
                seen.add(url)
                places.append(url)
    except Exception:  # noqa: BLE001 - a machine with no network is not an error
        pass
    return places


def origin_allowed(origin):
    """Which sites may talk to the bridge."""
    if not origin:
        return False
    if origin.startswith("http://127.0.0.1") or origin.startswith("http://localhost"):
        return True
    allowed = os.environ.get("ORBIT_CONSOLE_ORIGINS", "")
    for candidate in allowed.split(","):
        candidate = candidate.strip().rstrip("/")
        if candidate and origin.rstrip("/") == candidate:
            return True
    # Vercel gives every deployment its own subdomain, so the project is
    # matched rather than one exact host.
    # Vercel gives every deployment its own subdomain, so the project is
    # matched rather than one exact host: the project itself, plus its
    # previews, which are the name followed by dashes and a deployment
    # hash. It was "[a-z0-9-]*", which also matched orbitai-anything, and
    # names on vercel.app are there for the taking - so this is narrower
    # now. It is still not a boundary anybody should lean on: a matching
    # origin is only allowed to ASK, and every request from one still has
    # to carry the pairing token. If you want a boundary, name the exact
    # host in ORBIT_CONSOLE_ORIGINS and leave this unset.
    project = os.environ.get("ORBIT_CONSOLE_VERCEL", "").strip()
    if project and re.fullmatch(
            rf"https://{re.escape(project)}(-[a-z0-9]+)*\.vercel\.app", origin):
        return True
    return False


def run(args, timeout=60):
    """Runs a command and returns (ok, output)."""
    try:
        # Nothing started here came from the microphone, so the voice gate
        # must not judge it - a paired phone would otherwise stop working
        # whenever the last person to speak near the Mac was a stranger.
        # What authenticates these is the pairing token.
        env = dict(os.environ, ORBIT_FROM_CONSOLE="1")
        done = subprocess.run(args, capture_output=True, text=True,
                              timeout=timeout, env=env)
        return done.returncode == 0, (done.stdout or done.stderr).strip()
    except subprocess.TimeoutExpired:
        return False, "timed out"
    except Exception as exc:  # noqa: BLE001 - reported, not raised
        return False, str(exc)


def last_json(out):
    """The JSON line orbit ends with, or an empty dict.

    orbit prints one line of JSON after anything it wanted to say on the
    way, so the last line is the answer and the rest is commentary.
    """
    try:
        parsed = json.loads(out.splitlines()[-1])
        return parsed if isinstance(parsed, dict) else {}
    except (json.JSONDecodeError, IndexError, AttributeError):
        return {}


def config_values():
    """Effective settings: the shell's own answer, not a re-parse of it."""
    ok, out = run(["/bin/bash", "-c",
                   f'. "{ROOT}/lib/config.sh"; welcome_load_user_config; '
                   + "; ".join(f'printf "%s\\t%s\\n" {n} "${n}"' for n, *_ in SETTINGS)])
    values = {}
    if ok:
        for line in out.splitlines():
            if "\t" in line:
                key, value = line.split("\t", 1)
                values[key] = value
    return values


def write_setting(key, value):
    """Replaces one line in the user's config, leaving the rest alone."""
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    if not CONFIG.exists():
        CONFIG.write_text("# daily-welcome settings\n")

    lines = [l for l in CONFIG.read_text().splitlines()
             if not re.match(rf"^{re.escape(key)}=", l)]
    lines.append(f'{key}="{value}"')
    CONFIG.write_text("\n".join(lines) + "\n")


def status():
    listener = {}
    path = STATE / "listener-status"
    if path.exists():
        for line in path.read_text().splitlines():
            if "\t" in line:
                k, v = line.split("\t", 1)
                listener[k] = v

    running = subprocess.run(["pgrep", "-f", "DailyWelcome.app/Contents/MacOS/DailyWelcome"],
                             capture_output=True).returncode == 0

    heard = []
    heard_path = STATE / "heard.log"
    if heard_path.exists():
        heard = [l.split("\t", 1)[-1] for l in heard_path.read_text().splitlines()[-8:]]

    last_run = ""
    last_path = STATE / "last-run"
    if last_path.exists():
        last_run = last_path.read_text().strip()

    # Written by the menu bar app while another app has the microphone.
    # Stale notes are debris from an app that was killed mid-call.
    on_call = ""
    call_path = STATE / "on-call"
    if call_path.exists() and (time.time() - call_path.stat().st_mtime) < 300:
        on_call = call_path.read_text().strip()

    return {
        "app_running": running,
        "listener": listener,
        "heard": heard,
        "last_greeting": last_run,
        "on_call": on_call,
    }


def read_pairs(path, sep="="):
    if not path.exists():
        return []
    rows = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or sep not in line:
            continue
        left, right = line.split(sep, 1)
        rows.append({"name": left.strip(), "value": right.strip()})
    return rows


def write_pairs(path, rows, header):
    path.parent.mkdir(parents=True, exist_ok=True)
    body = [header, ""]
    for row in rows:
        name = (row.get("name") or "").strip()
        value = (row.get("value") or "").strip()
        if name and value:
            body.append(f"{name} = {value}")
    path.write_text("\n".join(body) + "\n")


class Console(BaseHTTPRequestHandler):
    server_version = "OrbitAI"

    def log_message(self, *args):  # quiet: this is a desktop app, not a server
        pass

    # -- helpers ---------------------------------------------------------
    def cors(self):
        origin = self.headers.get("Origin", "")
        if origin_allowed(origin):
            self.send_header("Access-Control-Allow-Origin", origin)
            self.send_header("Vary", "Origin")
            self.send_header("Access-Control-Allow-Headers", "Content-Type, X-Orbit-Token")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            # Chrome's private network access check: a public page reaching
            # a local address must be let in explicitly.
            self.send_header("Access-Control-Allow-Private-Network", "true")

    def authorised(self):
        """Same-origin needs no token; anything else must present one.

        The rule used to be "no Origin header means it is fine", and a
        browser leaves that header off exactly the requests a page makes
        without asking permission first. `<img src="http://127.0.0.1:7717
        /api/briefing">` on any page you happened to visit therefore made
        this Mac read the briefing out loud - the site could not see the
        answer, but it did not need to. /api/selftest was the same, and it
        runs things.

        So the Sec-Fetch headers decide it. Every browser still receiving
        security updates sends them, and they say what the request is FOR:
        a fetch from a script is Dest: empty, Mode: cors or same-origin. An
        image, a script tag, a stylesheet, an iframe or a form submission
        is none of those, and none of them has any business here.
        """
        dest = self.headers.get("Sec-Fetch-Dest", "")
        mode = self.headers.get("Sec-Fetch-Mode", "")
        site = self.headers.get("Sec-Fetch-Site", "")
        here = self.from_this_mac()

        if dest or mode or site:
            # A browser. It has told us what kind of request this is.
            if dest and dest != "empty":
                return False          # an image, a frame, a form - not an API call
            if mode == "no-cors":
                return False          # a request made without asking permission
            if site in ("same-origin", "none") and here:
                return True           # the console this server served, or a typed URL
            # Anywhere else has to be allowed AND carry the token. A phone
            # is "same-origin" too once the bridge is on the Wi-Fi, which
            # is exactly why being same-origin is no longer enough on its
            # own - see from_this_mac.
            if site not in ("same-origin", "none") and \
                    not origin_allowed(self.headers.get("Origin", "")):
                return False
            return secrets.compare_digest(self.headers.get("X-Orbit-Token", ""), token())

        # No Sec-Fetch headers at all: not a browser. curl, or a script on
        # this Mac, which could read the token file anyway.
        origin = self.headers.get("Origin", "")
        if here and (not origin or origin.startswith("http://127.0.0.1")
                     or origin.startswith("http://localhost")):
            return True
        if origin and not origin_allowed(origin) and not here:
            return False
        return secrets.compare_digest(self.headers.get("X-Orbit-Token", ""), token())

    def from_this_mac(self):
        """Did this request come from the machine the bridge is running on?

        Everything used to lean on the server being bound to the loopback
        address, so anything that could reach it was already on the Mac
        and could have read the token file anyway. On the Wi-Fi that stops
        being true, and "same-origin" starts meaning "anybody in the
        building who typed the address" - the phone's page and a stranger's
        page are the same origin as each other.

        So the address the connection came from decides it, rather than
        anything the request says about itself. Off the Mac, the token is
        required, whatever the headers claim.
        """
        address = (self.client_address or ("",))[0]
        return address.startswith("127.") or address in ("::1", "localhost")

    def do_OPTIONS(self):
        self.send_response(204)
        self.cors()
        self.send_header("Content-Length", "0")
        self.end_headers()

    def send(self, code, body, content_type="application/json"):
        raw = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.cors()
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    # A settings page does not send megabytes. Reading whatever length a
    # request claims is a way to be handed one.
    MAX_BODY = 1 << 20

    def body(self):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return {}
        if not length or length > self.MAX_BODY:
            return {}
        try:
            return json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            return {}

    # -- routes ----------------------------------------------------------
    def do_GET(self):
        path = urllib.parse.urlparse(self.path).path

        # The site is the same files Vercel serves, so the local copy and
        # the deployed one can never drift apart.
        site = ROOT / "web" / "orbitai"
        if path in ("/", "/index.html"):
            return self.send(200, (site / "index.html").read_bytes(), "text/html; charset=utf-8")

        name = path.strip("/")
        if name and ".." not in name:
            for candidate, kind in ((site / name, None),
                                    (site / f"{name}.html", "text/html; charset=utf-8")):
                if candidate.is_file():
                    kind = kind or {
                        ".css": "text/css", ".js": "text/javascript",
                        ".json": "application/json", ".html": "text/html; charset=utf-8",
                        # The home-screen icon and the manifest. Served as
                        # octet-stream they are ignored, and "Add to Home
                        # Screen" quietly falls back to a screenshot.
                        ".png": "image/png", ".svg": "image/svg+xml",
                        ".webmanifest": "application/manifest+json",
                    }.get(candidate.suffix, "application/octet-stream")
                    return self.send(200, candidate.read_bytes(), kind)

        # Lets the deployed console confirm it has reached the right Mac
        # before it asks for anything.
        if path == "/api/hello":
            # Answered before the token is checked, because a phone that
            # has not paired yet still needs to know it reached the right
            # Mac and whether pairing is open.
            return self.send(200, json.dumps({
                "orbit": True,
                "name": os.uname().nodename,
                "pairing": pair_open(),
                "paired": self.from_this_mac() or secrets.compare_digest(
                    self.headers.get("X-Orbit-Token", ""), token()),
            }))

        if not self.authorised():
            return self.send(403, json.dumps({"error": "pair this site first"}))

        if path == "/api/state":
            return self.send(200, json.dumps({
                "settings": setting_rows(),
                "status": status(),
                "contacts": read_pairs(CONTACTS),
                "macros": read_pairs(MACROS),
            }))

        if path == "/api/token":
            # For the one step of the Siri shortcut that has to be typed
            # by hand. Behind the same check as everything else, so it is
            # readable from the Mac itself or from a phone that has
            # already paired - and from nowhere else.
            return self.send(200, json.dumps({"ok": True, "token": token()}))

        if path == "/api/voices":
            ok, out = run([WELCOME, "--voices"], timeout=40)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/selftest":
            ok, out = run([ORBIT, "selftest"], timeout=120)
            # Strip the colour codes; the page does its own styling.
            return self.send(200, json.dumps({"ok": ok, "output": re.sub(r"\x1b\[[0-9;]*m", "", out)}))

        if path == "/api/doctor":
            ok, out = run([WELCOME, "--doctor"], timeout=180)
            return self.send(200, json.dumps(
                {"ok": ok, "output": re.sub(r"\x1b\[[0-9;]*m", "", out)}))

        if path == "/api/people":
            # Who is enrolled, and whether the gate is on. Its own call
            # rather than part of state: it shells out to Python and the
            # rest of the page should not wait for that.
            #
            # Rows, not the paragraph the terminal prints. A page that
            # re-reads the enrolment files itself would eventually
            # disagree with the assistant about who is enrolled, so it
            # asks the same command, which just knows how to answer twice.
            ok, out = run([ORBIT, "voice", "list", "--raw"], timeout=30)
            people = []
            if ok:
                for line in out.splitlines():
                    parts = line.split("\t")
                    if parts and parts[0].strip():
                        people.append({
                            "name": parts[0],
                            "samples": int(parts[1]) if len(parts) > 1 and parts[1].isdigit() else 0,
                            "banned": len(parts) > 2 and parts[2] == "banned",
                        })
            facts = {}
            fine, raw = run([ORBIT, "voice", "status"], timeout=30)
            if fine:
                for line in raw.splitlines():
                    if "\t" in line:
                        k, v = line.split("\t", 1)
                        facts[k] = v
            return self.send(200, json.dumps({
                "ok": ok, "output": out, "people": people,
                "installed": facts.get("installed") == "1",
                "enabled": facts.get("enabled") == "1",
                "gate": facts.get("gate") == "1",
                "threshold": facts.get("threshold", ""),
                "bypass": facts.get("bypass", ""),
            }))

        if path == "/api/models":
            ok, out = run([WELCOME, "--brain", "models"], timeout=45)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/who":
            # Who spoke last, and how sure it is. The console's answer to
            # "does it actually know me", which until now you could only
            # ask a terminal.
            ok, out = run([ORBIT, "voice", "who"], timeout=30)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/scores":
            ok, out = run([ORBIT, "voice", "test"], timeout=40)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/refusals":
            ok, out = run([ORBIT, "voice", "refusals", "6"], timeout=30)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/claude":
            # Whether Orbit can find Claude, and where. The single most
            # common "it says it is not installed" is a menu bar app that
            # inherited launchd's PATH rather than a login shell's.
            ok, out = run([WELCOME, "--find-claude"], timeout=45)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/braintest":
            ok, out = run([WELCOME, "--brain", "test"], timeout=60)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/briefing":
            ok, out = run([WELCOME, "--print"], timeout=90)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        return self.send(404, json.dumps({"error": "no such thing"}))

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path

        # The one POST that cannot require the token, since it is how you
        # get the token. It is rate-limited and one-shot instead.
        if path == "/api/pair":
            # Only a real browser fetch, and never a request a page can
            # make without asking: a site you happened to visit must not
            # be able to sit there guessing six digits.
            if self.headers.get("Sec-Fetch-Dest", "empty") != "empty" or \
                    self.headers.get("Sec-Fetch-Mode", "cors") == "no-cors":
                return self.send(403, json.dumps({"error": "no"}))
            granted, why = pair_redeem(self.body().get("code", ""))
            if not granted:
                return self.send(403, json.dumps({"error": why}))
            return self.send(200, json.dumps({"ok": True, "token": granted}))

        if not self.authorised():
            return self.send(403, json.dumps({"error": "pair this site first"}))
        data = self.body()

        if path == "/api/setting":
            key, value = data.get("key", ""), str(data.get("value", ""))
            if key not in {k for k, *_ in SETTINGS}:
                return self.send(400, json.dumps({"error": "not a setting the console manages"}))
            write_setting(key, value)
            # Settings the app reads at launch only take effect on restart.
            run([ORBIT, "listen", "restart"], timeout=20)
            return self.send(200, json.dumps({"ok": True}))

        if path == "/api/say":
            text = (data.get("text") or "").strip()
            if not text:
                return self.send(400, json.dumps({"error": "nothing to say"}))
            ok, out = run([ORBIT, "say", text], timeout=60)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/command":
            text = (data.get("text") or "").strip()
            if not text:
                return self.send(400, json.dumps({"error": "no command"}))
            ok, out = run([ORBIT, "plan", text], timeout=120)
            try:
                parsed = json.loads(out.splitlines()[-1])
            except (json.JSONDecodeError, IndexError):
                parsed = {"speak": out}
            return self.send(200, json.dumps({"ok": ok, "result": parsed}))

        if path == "/api/ask":
            # /api/command with the answer at the top level. Shortcuts on
            # an iPhone reads a dictionary value by key, and walking into
            # result.speak is four more taps to set up and one more thing
            # to get wrong - in the one step of the shortcut that somebody
            # actually has to type by hand.
            text = (data.get("text") or "").strip()
            if not text:
                return self.send(400, json.dumps({"error": "no command", "speak": ""}))
            ok, out = run([ORBIT, "plan", text], timeout=120)
            parsed = last_json(out)
            return self.send(200, json.dumps({
                "ok": ok,
                "speak": parsed.get("speak", out),
                "confirm": bool(parsed.get("confirm")),
                "token": parsed.get("token", ""),
            }))

        if path in ("/api/run", "/api/cancel"):
            # The yes, and the no. Spoken aloud these are a word; from a
            # phone they have to be an endpoint, or everything that waits
            # for confirmation is simply unavailable there - which is
            # everything worth being careful about.
            plan = (data.get("token") or "").strip()
            # A plan token is minted by orbit and looks it. Anything else
            # never reaches a process.
            if not re.fullmatch(r"[A-Za-z0-9_-]{4,64}", plan):
                return self.send(400, json.dumps({"error": "not a plan"}))
            verb = "run" if path.endswith("run") else "cancel"
            ok, out = run([ORBIT, verb, plan], timeout=120)
            return self.send(200, json.dumps(
                {"ok": ok, "speak": last_json(out).get("speak", out)}))

        if path == "/api/listen":
            action = data.get("action", "status")
            if action not in ("on", "off", "restart", "status"):
                return self.send(400, json.dumps({"error": "no"}))
            ok, out = run([ORBIT, "listen", action], timeout=30)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/contacts":
            write_pairs(CONTACTS, data.get("rows", []),
                        "# Nicknames for the people you message and call by voice.")
            return self.send(200, json.dumps({"ok": True}))

        if path == "/api/macros":
            write_pairs(MACROS, data.get("rows", []),
                        "# One phrase, several commands, separated by ; or then.")
            return self.send(200, json.dumps({"ok": True}))

        if path == "/api/enroll":
            # Recording somebody's voice takes as long as it takes them to
            # say a couple of sentences.
            name = (data.get("name") or "").strip()
            if not name:
                return self.send(400, json.dumps({"error": "no name"}))
            ok, out = run([ORBIT, "voice", "enroll", name], timeout=90)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/person":
            # ban, unban, forget, check, prune - one verb, one name.
            action = data.get("action", "")
            name = (data.get("name") or "").strip()
            if action not in ("ban", "unban", "forget", "check", "prune"):
                return self.send(400, json.dumps({"error": "not a thing it does"}))
            if not name:
                return self.send(400, json.dumps({"error": "no name"}))
            ok, out = run([ORBIT, "voice", action, name], timeout=60)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/gate":
            action = data.get("action", "")
            if action not in ("on", "off", "status"):
                return self.send(400, json.dumps({"error": "no"}))
            ok, out = run([ORBIT, "voice", "gate", action], timeout=30)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/modelkey":
            # The key for whichever service understands you. Handed over
            # on stdin, never as an argument - an argument is in the
            # process list and in shell history.
            key = (data.get("key") or "").strip()
            if not key:
                return self.send(400, json.dumps({"error": "no key"}))
            try:
                done = subprocess.run([WELCOME, "--set-openai-key"], input=key + "\n",
                                      capture_output=True, text=True, timeout=60)
                return self.send(200, json.dumps({"ok": done.returncode == 0,
                                                  "output": (done.stdout or done.stderr).strip()}))
            except subprocess.TimeoutExpired:
                return self.send(200, json.dumps({"ok": False, "output": "timed out"}))

        if path == "/api/setup":
            what = data.get("what", "")
            if what not in ("piper", "speaker"):
                return self.send(400, json.dumps({"error": "no"}))
            ok, out = run([WELCOME, "--setup-" + what], timeout=600)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/banlast":
            # Ban whoever just spoke. The voices worth banning are exactly
            # the ones with no name, so this enrols the last thing heard
            # under a label and bans that, in one go.
            label = (data.get("label") or "").strip()
            args = [ORBIT, "voice", "ban", "last"] + ([label] if label else [])
            ok, out = run(args, timeout=60)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/bypass":
            action = data.get("action", "status")
            if action not in ("start", "end", "status"):
                return self.send(400, json.dumps({"error": "no"}))
            ok, out = run([ORBIT, "voice", "bypass", action], timeout=30)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/permissions":
            ok, out = run([WELCOME, "--reset-permissions"], timeout=60)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/installclaude":
            # Long, and the page says so. It looks before it installs, so
            # pressing this when Claude is merely unfindable costs a
            # second rather than a download.
            ok, out = run([WELCOME, "--install-claude"], timeout=900)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/claudeat":
            # Point it at a Claude you found yourself, when the search
            # cannot: a Claude inside a version manager the shell only
            # sets up interactively.
            where = (data.get("path") or "").strip()
            if not where:
                return self.send(400, json.dumps({"error": "no path"}))
            ok, out = run([WELCOME, "--claude-at", where], timeout=45)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/preview":
            # Say one line in whatever the settings currently are.
            ok, out = run([WELCOME, "--test-voice"], timeout=90)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/key":
            key = (data.get("key") or "").strip()
            if not key:
                return self.send(400, json.dumps({"error": "no key"}))
            try:
                done = subprocess.run([WELCOME, "--set-key"], input=key + "\n",
                                      capture_output=True, text=True, timeout=60)
                return self.send(200, json.dumps({"ok": done.returncode == 0,
                                                  "output": (done.stdout or done.stderr).strip()}))
            except subprocess.TimeoutExpired:
                return self.send(200, json.dumps({"ok": False, "output": "timed out"}))

        return self.send(404, json.dumps({"error": "no such thing"}))


def main():
    port = int(os.environ.get("ORBIT_CONSOLE_PORT", "7717"))
    # Loopback unless asked otherwise. This thing can send mail and place
    # calls, so it has no business on a network interface by default - and
    # when it is on one, the address a request came from decides whether
    # the token is optional, never the headers. See Console.from_this_mac.
    local_only = "127.0.0.1"
    every_interface = "0.0.0.0"  # noqa: S104 - deliberate, and only with ORBIT_CONSOLE_LAN
    server = ThreadingHTTPServer(
        (every_interface if lan_mode() else local_only, port), Console)
    url = f"http://{local_only}:{port}"

    if lan_mode():
        code = pair_code(fresh=True)
        print("Orbit on your phone")
        print()
        print("  1. On the phone, open Safari and go to:")
        for place in lan_addresses(port):
            print(f"       {place}/phone")
        print()
        print("  2. It will ask for this code:")
        print(f"       {code[:3]} {code[3:]}")
        print()
        print("  3. Then Share, Add to Home Screen, and it opens like an app.")
        print()
        print(f"The code works once, within {PAIR_MINUTES} minutes.")
        print("While this runs, anything on your Wi-Fi can reach the sign-in")
        print("page - not Orbit itself, which needs the code first.")
        print("ctrl-c to stop.")
    else:
        print(f"OrbitAI bridge on {url}")
        print(f"Pairing token: {token()}")
        print("ctrl-c to stop")

    if shutil.which("open") and "--no-open" not in sys.argv and not lan_mode():
        subprocess.run(["open", url], capture_output=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
