"""The console bridge, as somebody else's web page would find it.

The bridge runs on the Mac and can send mail, place calls and speak. It
is bound to the loopback address, which stops the internet reaching it
and does nothing at all about the browser you have open - a browser will
happily let any page talk to 127.0.0.1.

The rule used to be "a request with no Origin header is fine", and a
browser leaves that header off exactly the requests a page can make
without permission. An <img> pointing at /api/briefing made this Mac
read the briefing out loud on any page you visited; /api/selftest runs
things. The site could not read the answer and did not need to.

Prints failures and a TALLY line for tests/run.
"""
import importlib.util, json, os, pathlib, sys, tempfile, threading, time
import urllib.error, urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
PASS = FAIL = 0


def check(what, want, got):
    global PASS, FAIL
    if want == got:
        PASS += 1
    else:
        FAIL += 1
        print("  bridge: %s\n    wanted: %r\n    got:    %r\n" % (what, want, got))


home = tempfile.mkdtemp()
os.environ["HOME"] = home
os.environ["ORBIT_CONSOLE_ORIGINS"] = "https://console.example.com"
os.environ["ORBIT_CONSOLE_VERCEL"] = "orbitai"

spec = importlib.util.spec_from_file_location("orbit_server", ROOT / "web" / "server.py")
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)

# Nothing is actually run. What matters is who gets as far as asking.
ran = []
server.run = lambda args, timeout=60: (ran.append(args), (True, "stub"))[1]
server.status = lambda: {"app_running": False, "listener": {}, "heard": [],
                         "last_greeting": "", "on_call": ""}
server.config_values = lambda: {}

httpd = server.ThreadingHTTPServer(("127.0.0.1", 0), server.Console)
port = httpd.server_address[1]
threading.Thread(target=httpd.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{port}"
TOKEN = server.token()


def ask(path, headers=None, data=None):
    req = urllib.request.Request(base + path, data=data,
                                 headers=headers or {}, method="POST" if data else "GET")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code
    except Exception:
        return 0


# ------------------------------------------------ the page this server served
check("the local console is let in", 200,
      ask("/api/state", {"Sec-Fetch-Site": "same-origin", "Sec-Fetch-Mode": "cors",
                         "Sec-Fetch-Dest": "empty", "Origin": base}))
# The pages themselves are served before any of this is consulted, so the
# console still loads by being typed in. An API path navigated to is a
# different thing, and refusing it also refuses a link straight to
# /api/briefing.
check("the console page itself still loads", 200,
      ask("/console.html", {"Sec-Fetch-Site": "none", "Sec-Fetch-Mode": "navigate",
                            "Sec-Fetch-Dest": "document"}))
check("but navigating to an API path is not an API call", 403,
      ask("/api/briefing", {"Sec-Fetch-Site": "none", "Sec-Fetch-Mode": "navigate",
                            "Sec-Fetch-Dest": "document"}))

# ------------------------------------------------------ somebody else's page
#
# The shapes a page can produce without the bridge agreeing to it. None of
# them can read the answer; all of them used to have the side effect.
IMG = {"Sec-Fetch-Site": "cross-site", "Sec-Fetch-Mode": "no-cors",
       "Sec-Fetch-Dest": "image"}
SCRIPT = {"Sec-Fetch-Site": "cross-site", "Sec-Fetch-Mode": "no-cors",
          "Sec-Fetch-Dest": "script"}
FRAME = {"Sec-Fetch-Site": "cross-site", "Sec-Fetch-Mode": "navigate",
         "Sec-Fetch-Dest": "iframe"}
FORM = {"Sec-Fetch-Site": "cross-site", "Sec-Fetch-Mode": "no-cors",
        "Sec-Fetch-Dest": "empty", "Origin": "https://evil.example",
        "Content-Type": "text/plain"}

for name, headers, path in [
    ("an image tag cannot read the state", IMG, "/api/state"),
    ("an image tag cannot make it speak", IMG, "/api/briefing"),
    ("an image tag cannot run the self-test", IMG, "/api/selftest"),
    ("a script tag cannot either", SCRIPT, "/api/selftest"),
    ("nor an iframe", FRAME, "/api/briefing"),
]:
    check(name, 403, ask(path, headers))

check("nor a form post", 403,
      ask("/api/say", FORM, json.dumps({"text": "hello"}).encode()))

# A cross-site fetch, which is the shape the deployed console uses.
CROSS = {"Sec-Fetch-Site": "cross-site", "Sec-Fetch-Mode": "cors",
         "Sec-Fetch-Dest": "empty", "Origin": "https://console.example.com"}
check("a cross-site fetch without the token is refused", 403, ask("/api/state", CROSS))
check("and with it is let in", 200, ask("/api/state", {**CROSS, "X-Orbit-Token": TOKEN}))
check("a token that is nearly right is still wrong", 403,
      ask("/api/state", {**CROSS, "X-Orbit-Token": TOKEN[:-1] + "x"}))
check("an origin nobody allowed is refused even with the token", 403,
      ask("/api/state", {"Sec-Fetch-Site": "cross-site", "Sec-Fetch-Mode": "cors",
                         "Sec-Fetch-Dest": "empty", "Origin": "https://evil.example",
                         "X-Orbit-Token": TOKEN}))

# --------------------------------------------------------------- the origins
allowed = server.origin_allowed
check("the named origin is allowed", True, allowed("https://console.example.com"))
check("a trailing slash is the same origin", True, allowed("https://console.example.com/"))
check("the project's own site", True, allowed("https://orbitai.vercel.app"))
check("and its previews", True, allowed("https://orbitai-a1b2c3d4-team.vercel.app"))
check("but not a lookalike", False, allowed("https://orbitai.evil.com"))
check("nor a prefix of it", False, allowed("https://notorbitai.vercel.app"))
check("nor plain http to it", False, allowed("http://orbitai.vercel.app"))
check("and no origin is not an origin", False, allowed(""))

# ------------------------------------------------------------- what it runs
#
# Only from a list. An action that is not on it never reaches a process.
ran.clear()
LOCAL = {"Sec-Fetch-Site": "same-origin", "Sec-Fetch-Mode": "cors",
         "Sec-Fetch-Dest": "empty", "Origin": base, "Content-Type": "application/json"}
check("a listen action that is not one of ours is refused", 400,
      ask("/api/listen", LOCAL, json.dumps({"action": "; rm -rf /"}).encode()))
check("and nothing was run", [], ran)

check("a setting the console does not manage is refused", 400,
      ask("/api/setting", LOCAL, json.dumps({"key": "PATH", "value": "/evil"}).encode()))

# Arguments go to a process as arguments, never through a shell.
ran.clear()
ask("/api/say", LOCAL, json.dumps({"text": "hello; touch /tmp/pwned"}).encode())
check("what is said is one argument, not a command line",
      True, any(a[-1] == "hello; touch /tmp/pwned" for a in ran))

# ------------------------------------------------- the pages that replaced
#                                                    the terminal
#
# Every one of these used to be a command you typed. A verb that is not on
# the list must never reach a process, and a name must arrive as one
# argument however it is spelled.
for path, body in [
    ("/api/person", {"action": "delete-everything", "name": "Arjun"}),
    ("/api/person", {"action": "ban", "name": ""}),
    ("/api/gate", {"action": "maybe"}),
    ("/api/bypass", {"action": "forever"}),
    ("/api/setup", {"what": "rm -rf /"}),
    ("/api/claudeat", {"path": ""}),
    ("/api/enroll", {"name": ""}),
    ("/api/modelkey", {"key": ""}),
]:
    ran.clear()
    check("%s refuses %r" % (path, body), 400,
          ask(path, LOCAL, json.dumps(body).encode()))
    check("and ran nothing", [], ran)

ran.clear()
ask("/api/person", LOCAL,
    json.dumps({"action": "ban", "name": "Somebody; rm -rf /"}).encode())
check("a name is one argument, not a command line",
      True, any(a[-1] == "Somebody; rm -rf /" for a in ran))

ran.clear()
ask("/api/banlast", LOCAL, json.dumps({}).encode())
check("banning the last voice needs no label",
      True, any(a[-3:] == ["voice", "ban", "last"] for a in ran))

# ------------------------------------------------------------ who it knows
#
# The console draws a button per person, so it needs rows. It gets them
# from the same command the terminal uses, which knows how to answer
# twice - and the rows are tab-separated, which is the only reason a name
# with a space in it survives. "Unwelcome 2 Sep" is the label banning an
# unknown voice generates, so this is the ordinary case, not an exotic one.
def answers(mapping, fallback=(True, "")):
    def stub(args, timeout=60):
        for needle, reply in mapping.items():
            if needle in " ".join(args):
                return reply
        return fallback
    return stub

real_run = server.run
server.run = answers({
    "voice list --raw": (True, "Arjun\t3\t\nUnwelcome 2 Sep\t1\tbanned"),
    "voice status": (True, "installed\t1\nenabled\t1\ngate\t0\n"
                           "threshold\t0.78\nenrolled\t2\nbypass\t"),
})
request = urllib.request.Request(base + "/api/people", headers=LOCAL)
with urllib.request.urlopen(request, timeout=5) as response:
    people = json.load(response)
server.run = real_run

check("both people come back", 2, len(people["people"]))
check("a name with a space in it survives", "Unwelcome 2 Sep", people["people"][1]["name"])
check("the sample count is a number", 3, people["people"][0]["samples"])
check("an empty third column is not a ban", False, people["people"][0]["banned"])
check("and 'banned' is", True, people["people"][1]["banned"])
check("it knows recognition is installed", True, people["installed"])
check("and that the gate is off", False, people["gate"])
check("no bypass is open", "", people["bypass"])

# --------------------------------------------------------------- the token
check("the token file is not readable by anyone else", "600",
      oct((pathlib.Path(home) / ".config/daily-welcome/console-token").stat().st_mode)[-3:])
check("and the token is long enough to be worth having", True, len(TOKEN) >= 24)

# A body that claims to be enormous is not read at all, so the request
# arrives carrying nothing and is refused for that.
check("an absurd Content-Length is not read", 400,
      ask("/api/setting", {**LOCAL, "Content-Length": "999999999"}, b"{}"))

httpd.shutdown()
print("TALLY %d %d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
