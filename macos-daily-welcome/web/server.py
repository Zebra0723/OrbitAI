#!/usr/bin/env python3
"""OrbitAI console - a local web app for managing the assistant.

It binds to localhost only. Everything it shows is read from the same
files and commands the assistant itself uses, and everything it changes is
written back to them, so the console and the voice never disagree about
what the settings are.

Started with `orbit console`; stopped with ctrl-c.
"""

import json
import os
import re
import secrets
import shutil
import subprocess
import sys
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
    ("ORBIT_CONFIRM_CALLS", "toggle", "Confirm calls", "Say the name back before dialling."),
    ("ORBIT_REQUIRE_UNLOCKED", "toggle", "Only when unlocked", "Ignore commands while the screen is locked."),
    ("ORBIT_VIPS", "text", "Interrupt for", "Names worth interrupting you for, separated by |."),
    ("WELCOME_SECTIONS", "text", "Briefing sections", "In order: reminders calendar messages mail claude tasks."),
]

TOGGLES = {name for name, kind, *_ in SETTINGS if kind == "toggle"}


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
    project = os.environ.get("ORBIT_CONSOLE_VERCEL", "").strip()
    if project and re.fullmatch(rf"https://{re.escape(project)}[a-z0-9-]*\.vercel\.app", origin):
        return True
    return False


def run(args, timeout=60):
    """Runs a command and returns (ok, output)."""
    try:
        done = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return done.returncode == 0, (done.stdout or done.stderr).strip()
    except subprocess.TimeoutExpired:
        return False, "timed out"
    except Exception as exc:  # noqa: BLE001 - reported, not raised
        return False, str(exc)


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

    return {
        "app_running": running,
        "listener": listener,
        "heard": heard,
        "last_greeting": last_run,
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
        """Same-origin needs no token; anything else must present one."""
        origin = self.headers.get("Origin", "")
        if not origin or origin.startswith("http://127.0.0.1") or origin.startswith("http://localhost"):
            return True
        if not origin_allowed(origin):
            return False
        return secrets.compare_digest(self.headers.get("X-Orbit-Token", ""), token())

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

    def body(self):
        length = int(self.headers.get("Content-Length") or 0)
        if not length:
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
                    }.get(candidate.suffix, "application/octet-stream")
                    return self.send(200, candidate.read_bytes(), kind)

        # Lets the deployed console confirm it has reached the right Mac
        # before it asks for anything.
        if path == "/api/hello":
            return self.send(200, json.dumps({"orbit": True, "name": os.uname().nodename}))

        if not self.authorised():
            return self.send(403, json.dumps({"error": "pair this site first"}))

        if path == "/api/state":
            return self.send(200, json.dumps({
                "settings": [
                    {"key": k, "kind": kind, "label": label, "help": help_,
                     "value": config_values().get(k, "")}
                    for k, kind, label, help_ in SETTINGS
                ],
                "status": status(),
                "contacts": read_pairs(CONTACTS),
                "macros": read_pairs(MACROS),
            }))

        if path == "/api/voices":
            ok, out = run([WELCOME, "--voices"], timeout=40)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        if path == "/api/selftest":
            ok, out = run([ORBIT, "selftest"], timeout=120)
            # Strip the colour codes; the page does its own styling.
            return self.send(200, json.dumps({"ok": ok, "output": re.sub(r"\x1b\[[0-9;]*m", "", out)}))

        if path == "/api/briefing":
            ok, out = run([WELCOME, "--print"], timeout=90)
            return self.send(200, json.dumps({"ok": ok, "output": out}))

        return self.send(404, json.dumps({"error": "no such thing"}))

    def do_POST(self):
        path = urllib.parse.urlparse(self.path).path
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
    # Localhost only. This thing can send mail and place calls; it has no
    # business listening on a network interface.
    server = ThreadingHTTPServer(("127.0.0.1", port), Console)
    url = f"http://127.0.0.1:{port}"
    print(f"OrbitAI bridge on {url}")
    print(f"Pairing token: {token()}")
    print("ctrl-c to stop")
    if shutil.which("open") and "--no-open" not in sys.argv:
        subprocess.run(["open", url], capture_output=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


if __name__ == "__main__":
    main()
