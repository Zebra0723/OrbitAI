#!/bin/bash
# Galaxy Link, against a stand-in for it.
#
# The stand-in is a few lines of Python on a random port, with GALAXY_HOME
# pointing at a directory holding its port and token, the same way the
# real galaxyd is found. It answers the handful of calls Orbit makes and
# writes every request down, so a test can ask what Orbit sent.
#
# What matters most here is at the end: no Link interaction - a fact, a
# note, a handoff, a status, a Link full of finished results and pending
# approvals - ever makes Orbit produce a sound.

test_sandbox
load_orbit
unset -f say afplay osascript 2>/dev/null

gx_home="$WELCOME_STATE_DIR/galaxy-home"
gx_log="$gx_home/requests.log"
mkdir -p "$gx_home"
printf 'test-token-0123456789abcdef\n' > "$gx_home/token"
export GALAXY_HOME="$gx_home"

cat > "$WELCOME_STATE_DIR/fake_link.py" <<'PY'
import json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

home = sys.argv[1]
token = open(os.path.join(home, "token")).read().strip()
MEMBERS = {"code": "comet", "build_web": "comet", "cad": "comet", "research": "comet",
           "screen": "nova", "mac_apps": "nova", "missions": "zenith"}

def load(name, default):
    try:
        return json.load(open(os.path.join(home, name)))
    except Exception:
        return default

class Link(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def reply(self, status, value):
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode() if length else ""
        with open(os.path.join(home, "requests.log"), "a") as f:
            f.write(json.dumps({
                "method": self.command, "path": self.path, "body": raw,
                "member": self.headers.get("X-Galaxy-Body", ""),
                "authorised": self.headers.get("Authorization", "") == "Bearer " + token,
                "origin": self.headers.get("Origin") is not None or self.headers.get("Sec-Fetch-Site") is not None,
            }) + "\n")
        path = self.path.split("?")[0]
        if path == "/v1/health":
            return self.reply(200, {"ok": True, "service": "galaxy-link"})
        if self.headers.get("Authorization", "") != "Bearer " + token:
            return self.reply(401, {"error": "missing or wrong token"})
        body = json.loads(raw) if raw else {}
        if path == "/v1/memory" and self.command == "GET":
            return self.reply(200, load("memories.json", []))
        if path == "/v1/memory" and self.command == "POST":
            return self.reply(201, {"id": "m_1", "text": body.get("text"), "source": "orbit"})
        if path == "/v1/events" and self.command == "POST":
            return self.reply(201, {"id": 1, "body": "orbit", "kind": body.get("kind"), "summary": body.get("summary")})
        if path == "/v1/tasks" and self.command == "POST":
            to = body.get("to") or MEMBERS.get(body.get("power", ""), "")
            if not to:
                return self.reply(422, {"error": "no body has that power"})
            return self.reply(201, {"id": "t_1", "from": "orbit", "to": to, "power": body.get("power", ""),
                                    "title": body.get("title"), "instructions": body.get("instructions"),
                                    "status": "queued", "result": "", "progress": "", "replyTo": ""})
        if path == "/v1/tasks" and self.command == "GET":
            return self.reply(200, load("tasks.json", []))
        if path == "/v1/overview":
            return self.reply(200, load("overview.json", {"bodies": [], "counts": {"approvals": 0}}))
        return self.reply(404, {"error": "no such thing"})

    do_GET = do_POST = do_PATCH = do_DELETE = handle_any

server = HTTPServer(("127.0.0.1", 0), Link)
with open(os.path.join(home, "port.tmp"), "w") as f:
    f.write(str(server.server_port))
os.rename(os.path.join(home, "port.tmp"), os.path.join(home, "port"))
server.serve_forever()
PY

python3 "$WELCOME_STATE_DIR/fake_link.py" "$gx_home" >/dev/null 2>&1 &
gx_pid=$!
for _ in $(seq 1 50); do [ -s "$gx_home/port" ] && break; sleep 0.1; done

# What Orbit has sent so far, and a way to wait for the background ones.
sent() { cat "$gx_log" 2>/dev/null; }
forget_sent() { : > "$gx_log"; }
wait_for_sent() { # wait_for_sent NEEDLE - up to three seconds
  local i
  for i in $(seq 1 30); do
    grep -qF -- "$1" "$gx_log" 2>/dev/null && return 0
    sleep 0.1
  done
  return 1
}
orbit() { "$TEST_ROOT/bin/orbit" "$@"; }

# ------------------------------------------------------------- the client

succeeds "Link is found through GALAXY_HOME" galaxy_installed
succeeds "and it answers" galaxy_available
forget_sent
out="$(galaxy_call GET /v1/overview)"
contains "a call returns the body" '"bodies"' "$out"
contains "it says it is Orbit"       '"member": "orbit"'   "$(sent)"
contains "with the token"            '"authorised": true'  "$(sent)"
lacks "and never like a web page"    '"origin": true'      "$(sent)"
fails "a 404 is a failure" galaxy_call GET /v1/nothing-here
ok "and prints nothing" "" "$(galaxy_call GET /v1/nothing-here)"

# ------------------------------------------------------------- memory

forget_sent
memory_add_fact "Has a dog called Biscuit"
succeeds "a new fact is shared with Link" wait_for_sent "Biscuit"
contains "as a memory"         '"path": "/v1/memory"' "$(sent)"
contains "and still kept here" "Biscuit" "$(memory_facts)"
forget_sent
memory_add_fact "has a dog called biscuit"
sleep 0.5
lacks "a fact it already had is not sent again" "iscuit" "$(sent)"

# Shared memories reach the prompt, without saying Orbit's own twice.
cat > "$gx_home/memories.json" <<'JSON'
[{"id":"m_1","text":"Has a dog called Biscuit.","source":"orbit"},
 {"id":"m_2","text":"Prefers window seats on flights","source":"comet"},
 {"id":"m_3","text":"Is building a site for the bakery","source":"nova"}]
JSON
known="$(memory_known)"
contains "Comet's memory is known to Orbit" "window seats" "$known"
contains "and Nova's"                        "bakery" "$known"
ok "Orbit's own fact is said once, not twice" "1" "$(printf '%s\n' "$known" | grep -ci biscuit)"

p="$(ORBIT_SPEAKER_NAME="" _claude_turn_prompt "hello" "" "$(memory_known | tr '\n' ';')" "" "" "")"
contains "shared memories reach the model prompt" "window seats" "$p"
contains "and the handoff form is offered" "handoff<TAB>" "$p"
body="$(declare -f claude_intent)"
contains "the turn prompt is fed the merged memories" "memory_known" "$body"
contains "and chat_claude's" "memory_known" "$(declare -f chat_claude)"
contains "and openai's" "memory_known" "$(declare -f openai_intent)"

# Cached for a minute: a second read does not ask Link again.
forget_sent
memory_known >/dev/null
lacks "a fresh cache is not refetched" "/v1/memory" "$(sent)"
printf '0\n' > "$WELCOME_STATE_DIR/galaxy/memories.txt"
memory_known >/dev/null
contains "a stale one is" "/v1/memory?limit=60" "$(sent)"

# ------------------------------------------------------------- what it did

forget_sent
memory_log_event message "Messaged Mama: running late"
succeeds "something it did is noted for the others" wait_for_sent "running late"
contains "as activity" '\"kind\":\"activity\"' "$(sent)"
forget_sent
memory_log_event refused "Turned away a voice it did not recognise"
memory_log_event quiet "mute for an hour"
sleep 0.5
ok "refusals and mutes are not news" "" "$(sent)"

# ------------------------------------------------------------- handoffs

intent() { parse_intent "$1" | cut -f1-2,4 | tr '\t' ' '; }
ok "'ask Comet to build me a site'"        "handoff comet to"    "$(intent "ask Comet to build me a site")"
ok "'can you have Nova book a table'"      "handoff nova to"     "$(intent "can you have Nova book a table at Nopa")"
ok "'tell Zenith to research grants'"      "handoff zenith to"   "$(intent "tell Zenith to research every grant I could apply for")"
ok "'ask Comet for a CAD model'"           "handoff comet for"   "$(intent "ask Comet for a CAD model of a shelf bracket")"
ok "'hand this to Nova'"                   "handoff nova "       "$(intent "hand this to Nova")"
ok "'make this a mission'"                 "handoff mission mission" "$(intent "make this a mission")"
ok "'start a mission to map the cafes'"    "handoff mission mission" "$(intent "start a mission to map every cafe in town")"
ok "the task is kept" "build me a site" "$(parse_intent "ask Comet to build me a site" | cut -f3)"
ok "'tell Mama I'm late' is still a message" "message mama" "$(intent "tell mama I'm late" | cut -d' ' -f1-2)"

forget_sent
out="$(orbit plan "ask Comet to build me a landing page for the bakery")"
contains "a handoff creates a task"       '"path": "/v1/tasks"' "$(sent)"
contains "for Comet"                      '\"to\":\"comet\"' "$(sent)"
contains "with what was asked"            'landing page for the bakery' "$(sent)"
contains "and Orbit says so, as itself"   "I've asked Comet to build you a landing page for the bakery." "$out"
contains "and where the result will be"   "on your screen or phone" "$out"
contains "with nothing left to confirm"   '"confirm":false' "$out"
contains "it is in Orbit's own record"    "Asked Comet" "$(memory_events)"

forget_sent
out="$(orbit plan "start a mission to map every cafe in town")"
contains "a mission goes by power"        '\"power\":\"missions\"' "$(sent)"
contains "to whoever has it"              "a mission with Zenith" "$out"

# "Make this a mission" is about the thing just asked for.
memory_log_turn "find me every grant a small bakery could apply for" "That is a big job."
forget_sent
out="$(orbit plan "make this a mission")"
contains "the last request becomes the mission" "every grant a small bakery" "$(sent)"
contains "and is said back"                      "every grant a small bakery" "$out"

# ------------------------------------------------------------- status

cat > "$gx_home/overview.json" <<'JSON'
{"bodies":[
  {"id":"comet","name":"Comet","online":true,"joined":true,"working":{"id":"t_1","title":"Bakery landing page","progress":"drafting the hero"}},
  {"id":"nova","name":"Nova","online":true,"joined":true,"working":null},
  {"id":"orbit","name":"Orbit","online":true,"joined":true,"working":null},
  {"id":"zenith","name":"Zenith","online":false,"joined":false,"working":null}],
 "counts":{"approvals":2}}
JSON
cat > "$gx_home/tasks.json" <<'JSON'
[{"id":"t_2","from":"orbit","to":"zenith","power":"missions","title":"Map every cafe in town","status":"claimed","progress":"halfway through the north side"}]
JSON
ok "'galaxy status'"               "galaxy all"     "$(intent "galaxy status")"
ok "'what are the others doing'"   "galaxy all"     "$(intent "what are the others doing?")"
ok "'how's my mission'"            "galaxy mission" "$(intent "how's my mission going")"
ok "'what's Comet doing'"          "galaxy comet"   "$(intent "what's Comet doing")"
ok "'what is the mission of NASA' is a question" "ask" "$(intent "what is the mission of NASA" | cut -d' ' -f1)"

out="$(orbit plan "galaxy status")"
contains "status says what Comet is doing" "Comet is working on Bakery landing page, drafting the hero." "$out"
contains "who is idle"                     "Nova is running" "$out"
contains "who is not running"              "Zenith is not running" "$out"
contains "and what is waiting"             "2 approvals are waiting for you" "$out"
lacks "and leaves Orbit out of it"         "Orbit is" "$out"
out="$(orbit plan "how's my mission")"
contains "the mission is reported"         "Zenith is working on Map every cafe in town. Latest: halfway through the north side." "$out"
out="$(orbit plan "what's Nova doing")"
contains "one member, when asked about"    "Nova is running" "$out"
lacks "and only that one"                  "Comet" "$out"

# ------------------------------------------------------------- Link down

kill "$gx_pid" 2>/dev/null; wait "$gx_pid" 2>/dev/null
fails "with Link stopped it is not available" galaxy_available
started="$(date +%s)"
memory_add_fact "Likes oat milk"
contains "facts are still kept" "oat milk" "$(memory_facts)"
printf '0\n' > "$WELCOME_STATE_DIR/galaxy/memories.txt"
known="$(memory_known)"
contains "its own facts still reach the prompt" "oat milk" "$known"
lacks "and nothing stale from Link" "window seats" "$known"
out="$(orbit plan "ask Comet to build me a site")"
contains "a handoff says it could not reach Link" "couldn't reach Galaxy Link" "$out"
lacks "and does not pretend" "I've asked" "$out"
out="$(orbit plan "galaxy status")"
contains "status says so too" "can't reach Galaxy Link" "$out"
ok "and none of it waits on Link" "yes" "$([ $(( $(date +%s) - started )) -le 8 ] && echo yes || echo no)"

# Not installed at all, or switched off: these sentences mean what they
# always meant.
before="$(GALAXY_HOME="$WELCOME_STATE_DIR/nowhere" parse_intent "tell Zenith to research grants")"
ok "with no Link, 'tell Zenith...' is what it always was" "message" "$(intent_of "$before")"
ok "and ORBIT_GALAXY=0 is the same" "$before" "$(ORBIT_GALAXY=0 parse_intent "tell Zenith to research grants")"
fails "switched off, nothing is called" env ORBIT_GALAXY=0 bash -c ". '$TEST_ROOT/lib/config.sh'; . '$TEST_ROOT/lib/common.sh'; . '$TEST_ROOT/lib/galaxy.sh'; galaxy_installed"
ok "and no shared memories" "" "$(ORBIT_GALAXY=0 galaxy_memories 2>/dev/null)"
p="$(ORBIT_GALAXY=0 _claude_turn_prompt "hello" "" "" "" "" "")"
lacks "nor a handoff form in the prompt" "handoff<TAB>" "$p"

# ------------------------------------------------------------- never a sound
#
# A Link full of things that might tempt something to talk: finished
# results, a pending approval, chat. Every interaction Orbit has with it
# is run against stand-ins for say and afplay that write down anything
# they are asked to play. Nothing may reach them.

python3 "$WELCOME_STATE_DIR/fake_link.py" "$gx_home" >/dev/null 2>&1 &
gx_pid=$!
rm -f "$gx_home/port"
for _ in $(seq 1 50); do [ -s "$gx_home/port" ] && break; sleep 0.1; done
cat > "$gx_home/tasks.json" <<'JSON'
[{"id":"t_2","from":"orbit","to":"zenith","power":"missions","title":"Map every cafe","status":"done","result":"Here are 41 cafes.","progress":""}]
JSON

fakes="$WELCOME_STATE_DIR/fakes"
sounds="$WELCOME_STATE_DIR/sounds.log"
mkdir -p "$fakes"
for tool in say afplay osascript; do
  printf '#!/bin/bash\nprintf "%%s %%s\\n" "%s" "$*" >> "%s"\n' "$tool" "$sounds" > "$fakes/$tool"
  chmod +x "$fakes/$tool"
done
saved_path="$PATH"
export PATH="$fakes:$PATH"
: > "$sounds"

# Unmuted, and with speech switched on: the library calls on their own.
WELCOME_SPEAK=1
galaxy_remember "Likes the window seat" ; galaxy_note "Set a timer for ten minutes"
galaxy_memories >/dev/null; galaxy_status all >/dev/null; galaxy_status mission >/dev/null
galaxy_handoff comet "build a site" >/dev/null
memory_add_fact "Takes the train on Tuesdays"
memory_log_event timer "Set a timer for ten minutes"
sleep 1
ok "no Link call makes a sound by itself" "" "$(cat "$sounds" 2>/dev/null)"

# The whole of orbit, muted, through every Link path. Muted means silent.
printf 'never\n' > "$(orbit_mute_file)"
for said in "ask Comet to build me a site" "make this a mission" "galaxy status" \
            "how's my mission" "what's Comet doing"; do
  WELCOME_SPEAK=1 WELCOME_TTS=say orbit plan "$said" >/dev/null
done
WELCOME_SPEAK=1 orbit memory add "Has a sister called Asha" >/dev/null
sleep 1
ok "muted, no Link path makes a sound" "" "$(cat "$sounds" 2>/dev/null)"
orbit_unmute
export PATH="$saved_path"

# And nothing in Orbit listens to Link: no inbox, no task queue, no chat,
# no approvals. Results are delivered to a screen or a phone, never here.
# (OpenAI's /v1/chat/completions is another service altogether; this
# looks only at calls made to Link.)
listens="$( { grep -rhE 'galaxy_(call|send)' "$TEST_ROOT/lib" "$TEST_ROOT/bin"
              cat "$TEST_ROOT/menubar/galaxy.swift"; } \
            | grep -E '/v1/(inbox|tasks/next|chat|approvals|deliver)')"
ok "nothing in Orbit asks Link for results, chat or approvals" "" "$listens"
swift="$(grep -vE '^[[:space:]]*//' "$TEST_ROOT/menubar/galaxy.swift")"
for word in AVSpeech NSSound afplay speak orbitPath 'Process('; do
  lacks "the presence code has nothing to do with $word" "$word" "$swift"
done
lib="$(grep -vE '^[[:space:]]*#' "$TEST_ROOT/lib/galaxy.sh")"
for word in speak_ say_speak play_file emit afplay; do
  lacks "lib/galaxy.sh never calls $word" "$word" "$lib"
done

kill "$gx_pid" 2>/dev/null; wait "$gx_pid" 2>/dev/null
unset GALAXY_HOME
