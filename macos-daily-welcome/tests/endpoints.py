"""Every service speaks chat-completions, and then disagrees at the edges.

JSON mode exists on some models and not others; a few insist temperature
is 1; a few want max_completion_tokens rather than max_tokens. The
failure is a 400 naming the field. All three are niceties - guaranteed
JSON, no creativity, a length cap - and none is worth failing the whole
request over, so it is asked again without whatever was named.

Runs a small server that rejects one named field, the way the non-OpenAI
endpoints do, and checks an intent still comes back.
"""
import json, http.server, os, pathlib, socketserver, subprocess, sys, threading

ROOT = pathlib.Path(__file__).resolve().parent.parent
PASS = FAIL = 0


def check(what, want, got):
    global PASS, FAIL
    if want == got:
        PASS += 1
    else:
        FAIL += 1
        print("  endpoints: %s\n    wanted: %r\n    got:    %r\n" % (what, want, got))


def serve(reject=None, status=200):
    """A server that 400s on one field, like Groq and Gemini do."""
    class H(http.server.BaseHTTPRequestHandler):
        def log_message(self, *a):
            pass

        def _send(self, code, obj):
            body = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_POST(self):
            length = int(self.headers.get("Content-Length", 0))
            sent = json.loads(self.rfile.read(length) or b"{}")
            self.server.seen.append(sent)
            if status != 200:
                return self._send(status, {"error": {"message": "Invalid API Key"}})
            if reject and reject in sent:
                return self._send(400, {"error": {
                    "message": "'%s' is not supported with this model" % reject,
                    "param": reject}})
            return self._send(200, {"choices": [{"message": {"content": json.dumps(
                {"intent": "system", "arg1": "volume_up", "arg2": ""})}}]})

    httpd = socketserver.TCPServer(("127.0.0.1", 0), H)
    httpd.seen = []
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd


def ask(httpd):
    env = dict(os.environ,
               OPENAI_API_KEY="test-key",
               ORBIT_OPENAI_BASE="http://127.0.0.1:%d/v1" % httpd.server_address[1],
               ORBIT_OPENAI_MODEL="whatever")
    done = subprocess.run([sys.executable, str(ROOT / "lib" / "openai_intent.py"),
                           "turn the volume up"],
                          capture_output=True, text=True, env=env, timeout=30)
    return done.stdout.strip(), done.stderr.strip()


for field in (None, "response_format", "temperature", "max_tokens"):
    httpd = serve(field)
    try:
        out, err = ask(httpd)
        name = field or "nothing"
        # stdout is stripped, so the trailing empty field goes with it.
        check("an endpoint rejecting %s still answers" % name,
              "system\tvolume_up", out)
        if field:
            check("and says what it dropped (%s)" % name, True,
                  ("without " + field) in err)
            check("and did not send it again (%s)" % name, False,
                  field in httpd.seen[-1])
    finally:
        httpd.shutdown()

# Anything that is not a 400 is a real failure and must not be retried
# into silence - a refused key especially.
httpd = serve(status=401)
try:
    out, err = ask(httpd)
    check("a refused key is reported, not retried", "", out)
    check("and says so plainly", True, "401" in err)
    check("and is asked exactly once", 1, len(httpd.seen))
finally:
    httpd.shutdown()

print("TALLY %d %d" % (PASS, FAIL))
sys.exit(1 if FAIL else 0)
