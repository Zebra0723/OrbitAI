#!/bin/bash
# Galaxy Link: the hub the rest of GalaxyAI meets in.
#
# Comet, Nova, Zenith and Nebula share one memory, one record of what has
# been happening, and a way to hand each other work, all through a small
# service on this Mac called galaxyd. Orbit joins in on its own terms:
#
#   - what it learns about you is shared, and what the others learned
#     reaches its prompt;
#   - what it actually did (sent a message, set a timer) is noted, so the
#     others know;
#   - something it cannot do itself is handed to the member who can, and
#     Orbit says so in the same breath;
#   - asked, it says what the others are up to.
#
# What it never does is listen to Link. Nothing here waits for a result,
# polls an inbox or reads the group chat, so nothing Link does can make
# Orbit speak. Orbit talks when somebody talks to it, and Link is built to
# never route a result to a voice in the first place.
#
# Everything fails soft. With Link not installed, not running, or switched
# off (ORBIT_GALAXY=0), every function here returns non-zero, prints
# nothing, and Orbit carries on exactly as it did before Link existed.

# Where Link keeps its port and token. GALAXY_HOME moves it, the same way
# it moves it for galaxyd itself, which is what the tests point at a fake.
_galaxy_home() {
  printf '%s' "${GALAXY_HOME:-$HOME/Library/Application Support/Galaxy}"
}

_galaxy_dir() { printf '%s/galaxy' "$WELCOME_STATE_DIR"; }

galaxy_enabled() { [ "${ORBIT_GALAXY:-1}" != "0" ]; }

# The token, if there is a believable one. It is spliced into a curl
# config line, so anything that is not plainly a token is refused rather
# than quoted: a stray quote in that file must not become a curl option.
_galaxy_token() {
  local token
  token="$(tr -d '[:space:]' 2>/dev/null < "$(_galaxy_home)/token")"
  case "$token" in
    ''|*[!A-Za-z0-9._~+/=-]*) return 1 ;;
  esac
  printf '%s' "$token"
}

_galaxy_port() {
  local port
  port="$(tr -d '[:space:]' 2>/dev/null < "$(_galaxy_home)/port")"
  case "$port" in
    ''|*[!0-9]*) port=7740 ;;
  esac
  printf '%s' "$port"
}

# Link is set up on this Mac and switched on here. Reads two small files
# and touches no network, so it is cheap enough to ask on every sentence.
galaxy_installed() {
  galaxy_enabled || return 1
  have_cmd curl || return 1
  _galaxy_token >/dev/null
}

# galaxy_call METHOD PATH [JSON] -> the response body, on a 2xx
#
# Short timeouts, because every call here is made while somebody is
# waiting for an answer: half a second to connect (it is this Mac, so a
# refusal is instant and a hang means something is wrong) and three in
# all. The token goes to curl on stdin, never on its command line, where
# any process on the Mac could read it. -q skips ~/.curlrc and --noproxy
# keeps a configured proxy from being asked to reach 127.0.0.1. curl sends
# no Origin and no Sec-Fetch-Site, which is what tells Link this is a
# member and not a web page.
galaxy_call() {
  local method="$1" path="$2" data="${3-}" token out code
  galaxy_installed || return 1
  token="$(_galaxy_token)" || return 1

  local args=(-q -s --noproxy '*' --connect-timeout 0.5 --max-time 3 -X "$method"
              -w '\n%{http_code}')
  if [ -n "$data" ]; then
    args+=(-H 'Content-Type: application/json' --data-binary "$data")
  fi

  out="$(printf 'header = "Authorization: Bearer %s"\nheader = "X-Galaxy-Body: orbit"\n' "$token" \
    | curl -K - "${args[@]}" "http://127.0.0.1:$(_galaxy_port)$path" 2>/dev/null)" || return 1

  code="${out##*$'\n'}"
  case "$code" in
    2??) ;;
    *) return 1 ;;
  esac
  printf '%s' "${out%$'\n'*}"
}

# Is Link actually answering, rather than merely installed?
galaxy_available() {
  galaxy_call GET /v1/health >/dev/null
}

# The same call, sent off without waiting. For the things that are only
# ever a courtesy to the other members - a fact, a note of what was done -
# and must never add a moment to the reply. Every stream is closed: the
# menu bar app reads orbit's output until it ends, and a background curl
# still holding it would hold the answer back with it.
galaxy_send() {
  galaxy_installed || return 1
  ( galaxy_call "$@" >/dev/null 2>&1 & ) </dev/null >/dev/null 2>&1
  return 0
}

# A string as JSON. json_escape leaves carriage returns alone, and a
# transcript can carry one.
_galaxy_str() {
  printf '"%s"' "$(json_escape "$(printf '%s' "$1" | tr '\r' ' ')")"
}

# Reads JSON on stdin and prints it as tab-separated lines.
_galaxy_read() {
  have_cmd python3 || return 1
  python3 -c '
import json, sys
mode = sys.argv[1]
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
def clean(v):
    return " ".join(str(v if v is not None else "").split())
if mode == "memories":
    for m in data if isinstance(data, list) else []:
        text = clean(m.get("text") if isinstance(m, dict) else "")
        if text:
            print(text)
elif mode == "task":
    print("\t".join(clean(data.get(k)) for k in ("to", "title", "status", "progress")))
elif mode == "tasks":
    for t in data if isinstance(data, list) else []:
        print("\t".join(clean(t.get(k)) for k in ("to", "from", "power", "title", "status", "progress")))
elif mode == "overview":
    for b in data.get("bodies", []):
        w = b.get("working") or {}
        print("\t".join(["body", clean(b.get("id")), clean(b.get("name")),
                         "1" if b.get("online") else "0", "1" if b.get("joined") else "0",
                         clean(w.get("title")), clean(w.get("progress"))]))
    print("approvals\t%d" % int((data.get("counts") or {}).get("approvals") or 0))
' "$1" 2>/dev/null
}

# ------------------------------------------------------------- memory

# A fact Orbit just learned, shared with the others. In the background:
# remembering is never a reason to answer later.
galaxy_remember() {
  [ -n "${1:-}" ] || return 0
  galaxy_send POST /v1/memory "{\"text\":$(_galaxy_str "$1")}"
}

# What every member knows about you, one memory a line.
#
# Cached for a minute. The prompt is built on every sentence and the
# memory changes on a scale of days, so asking Link every time would buy
# nothing but a round trip. A failed fetch is cached too - as nothing - so
# a Link that has stopped costs one refused connection a minute rather
# than one a sentence. The first line of the cache is when it was fetched.
galaxy_memories() {
  galaxy_installed || return 1
  local cache now fetched body
  cache="$(_galaxy_dir)/memories.txt"
  now="$(date +%s)"
  fetched="$(head -1 "$cache" 2>/dev/null)"
  case "$fetched" in ''|*[!0-9]*) fetched=0 ;; esac

  if [ $(( now - fetched )) -ge "$ORBIT_GALAXY_MEMORY_SECONDS" ] || [ "$fetched" -gt "$now" ]; then
    mkdir -p "$(_galaxy_dir)" 2>/dev/null
    {
      printf '%s\n' "$now"
      if body="$(galaxy_call GET '/v1/memory?limit=60')"; then
        printf '%s' "$body" | _galaxy_read memories
      fi
    } > "$cache.tmp" 2>/dev/null && mv "$cache.tmp" "$cache"
  fi
  tail -n +2 "$cache" 2>/dev/null
}

# ------------------------------------------------------------- activity

# A short line in the record every member reads: "Messaged Mama: running
# late". Only for things Orbit actually did - a question answered is not
# news to anybody.
galaxy_note() {
  [ -n "${1:-}" ] || return 0
  galaxy_send POST /v1/events "{\"kind\":\"activity\",\"summary\":$(_galaxy_str "$(printf '%s' "$1" | cut -c1-300)")}"
}

# ------------------------------------------------------------- handoffs

# The members Orbit can name, and how they are said.
galaxy_member_name() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    comet)  printf 'Comet' ;;
    nova)   printf 'Nova' ;;
    zenith) printf 'Zenith' ;;
    nebula) printf 'Nebula' ;;
    *)      printf '%s' "$1" | awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }' ;;
  esac
}

# galaxy_handoff WHO TASK [WHAT THEY SAID] -> who took it, by name
#
# WHO is a member (comet, nova, zenith), "mission" for whoever does the
# long ones, or a power (code, research, screen...) for Link to route.
# Orbit asks and that is the end of it: the result goes wherever you are,
# by way of Comet or Nova, and never back to this voice.
galaxy_handoff() {
  local who task said title target payload body to
  who="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"
  task="$2"
  said="${3:-$2}"
  [ -n "$task" ] || return 1

  case "$who" in
    comet|nova|zenith) target="\"to\":\"$who\"" ;;
    mission|missions)  target="\"power\":\"missions\"" ;;
    *[!a-z_]*|'')      return 1 ;;
    *)                 target="\"power\":\"$who\"" ;;
  esac

  # A title is what shows in Galaxy Chat and on the dashboard: the first
  # few words, with a capital. The whole thing goes in the instructions.
  title="$(printf '%s' "$task" | tr '\n\r' '  ' | awk '{
      out = ""
      for (i = 1; i <= NF && i <= 12; i++) out = out (i > 1 ? " " : "") $i
      if (NF > 12) out = out "..."
      print toupper(substr(out, 1, 1)) substr(out, 2)
    }')"

  payload="{$target,\"title\":$(_galaxy_str "$title"),\"instructions\":$(_galaxy_str "$(printf 'Asked by voice, through Orbit%s: "%s"\n\nWhat they want: %s\n\nOrbit is a voice and will not wait for this. Deliver the result the usual way, to their screen or phone.' \
    "${ORBIT_SPEAKER_NAME:+, by $ORBIT_SPEAKER_NAME}" "$said" "$task")")}"

  body="$(galaxy_call POST /v1/tasks "$payload")" || return 1
  to="$(printf '%s' "$body" | _galaxy_read task | cut -f1)"
  [ -n "$to" ] || to="$who"
  galaxy_member_name "$to"
}

# Their words, turned round to be said back to them: "build me a site"
# becomes "build you a site". Word by word in awk, because BSD sed has no
# word boundaries.
galaxy_said_back() {
  printf '%s' "$1" | awk '{
    for (i = 1; i <= NF; i++) {
      w = $i; lw = tolower(w); tail = ""
      if (match(lw, /[.,!?;:]+$/)) { tail = substr(w, RSTART); lw = substr(lw, 1, RSTART - 1) }
      to = ""
      if      (lw == "me")     to = "you"
      else if (lw == "my")     to = "your"
      else if (lw == "mine")   to = "yours"
      else if (lw == "myself") to = "yourself"
      else if (lw == "i")      to = "you"
      else if (lw == "i'\''m") to = "you'\''re"
      else if (lw == "i'\''ll") to = "you'\''ll"
      else if (lw == "i'\''ve") to = "you'\''ve"
      if (to != "") w = to tail
      printf "%s%s", (i > 1 ? " " : ""), w
    }
  }'
}

# ------------------------------------------------------------- status

# galaxy_status [all|mission|<member>] -> a spoken answer
#
# Only ever asked for. It reads Link's overview - who is running, what
# each is working on, what is waiting for your yes - and says the part
# that was asked about.
galaxy_status() {
  local what="${1:-all}" body lines
  what="$(printf '%s' "$what" | tr '[:upper:]' '[:lower:]')"

  if [ "$what" = mission ]; then
    _galaxy_mission_status
    return
  fi

  body="$(galaxy_call GET /v1/overview)" || return 1
  lines="$(printf '%s' "$body" | _galaxy_read overview)" || return 1
  [ -n "$lines" ] || return 1

  printf '%s\n' "$lines" | awk -F'\t' -v want="$what" '
    function join(list, n,   s, i) {
      s = ""
      for (i = 1; i <= n; i++) s = s (i == 1 ? "" : (i == n ? " and " : ", ")) list[i]
      return s
    }
    $1 == "approvals" { approvals = $2 + 0; next }
    $1 != "body" || $2 == "orbit" { next }
    want != "all" && $2 != want { next }
    {
      seen++
      if ($6 != "") {
        line = $3 " is working on " $6
        if ($7 != "") line = line ", " $7
        said = said (said == "" ? "" : " ") line "."
      } else if ($4 == "1") {
        idle[++ni] = $3
      } else {
        off[++no] = $3
      }
    }
    END {
      if (want != "all" && seen == 0) { print "I do not know a member called " want "."; exit }
      if (ni == 1) said = said (said == "" ? "" : " ") idle[1] " is running, with nothing on."
      else if (ni > 1) said = said (said == "" ? "" : " ") join(idle, ni) " are running, with nothing on."
      if (no == 1) said = said (said == "" ? "" : " ") off[1] " is not running."
      else if (no > 1) said = said (said == "" ? "" : " ") join(off, no) " are not running."
      if (want == "all") {
        if (approvals == 1) said = said " One approval is waiting for you."
        else if (approvals > 1) said = said " " approvals " approvals are waiting for you."
      }
      print said
    }' | sed -E 's/^[[:space:]]+//'
}

# The newest mission: the latest task Zenith was given, by anybody.
_galaxy_mission_status() {
  local body line title status progress
  body="$(galaxy_call GET '/v1/tasks?body=zenith')" || return 1
  line="$(printf '%s' "$body" | _galaxy_read tasks | awk -F'\t' '$1 == "zenith" { print; exit }')"
  if [ -z "$line" ]; then
    printf 'There is no mission on the go.'
    return 0
  fi
  title="$(printf '%s' "$line" | cut -f4)"
  status="$(printf '%s' "$line" | cut -f5)"
  progress="$(printf '%s' "$line" | cut -f6 | sed -E 's/[.[:space:]]+$//')"
  case "$status" in
    queued)    printf 'Your mission, %s, is waiting for Zenith to pick it up.' "$title" ;;
    claimed)   printf 'Zenith is working on %s.%s' "$title" "${progress:+ Latest: $progress.}" ;;
    done)      printf 'Zenith finished %s. The result is on your screen or phone.' "$title" ;;
    failed)    printf 'Zenith could not finish %s.' "$title" ;;
    cancelled) printf '%s was cancelled.' "$title" ;;
    *)         printf '%s is %s.' "$title" "$status" ;;
  esac
}
