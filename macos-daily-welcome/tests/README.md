# Tests

```
tests/run              everything, about ten seconds
tests/run intents      just the suites whose names match
daily-welcome --test   the same thing, from anywhere
```

No network, no API keys, no Mac. Every test runs against a throwaway
state directory with `ORBIT_NLU=rules`, so nothing here touches your real
Orbit or reaches a model, and the browser suite is cut off from the
network entirely. That is deliberate: a test suite only earns its keep if
it is quick enough to run without thinking about it.

The one optional part is `web`, which needs Playwright and a copy of
Chromium. Without them it says so and everything else still runs:

```
npm install -g playwright && npx playwright install chromium
```

Exit status is 0 when everything passes, 1 when something does not, 2 when
the name you gave matches no suite.

## What is covered

| suite | what it protects |
| --- | --- |
| `intents` | what Orbit understands, one case per sentence that has broken |
| `durations` | timers: "two hours" is not two minutes |
| `numbers` | numbers said as words, including "twenty five" |
| `disfluency` | "um", false starts, and which hedges are content |
| `speech` | how it sounds: pauses, clocks, tidying, sentence case |
| `natural` | sounding like a person rather than a machine reading |
| `sources` | the briefing's contents, and the order they come in |
| `memory` | what it remembers and what it lets go of |
| `messages` | unread iMessages, against a real chat.db shape |
| `applescript` | the scripts Mail is sent, as they come out |
| `slots` | the half-finished request, and the way out of one |
| `speaker` | the voice store: matching, banning, and strangers |
| `freeform` | the denylist on model-written commands, and its wiring |
| `bypass` | letting one voice in, and the greeting that names you |
| `backend` | choosing how to speak, without dying in the attempt |
| `unbound` | every variable read is one something declares |
| `install` | build before replace; every Swift file and usage string |
| `doctor` | it names the voice you will hear, and every fix is doable |
| `static` | every file parses; Swift balances; no inline `onclick` |
| `plans` | `orbit plan` and `orbit run` agree on the field names |
| `prompts` | every prompt reaches its own last line |
| `sourcing` | every function called is one that exists and is loaded |
| `web` | every page and control, in a real browser |
| `bridge` | who the console bridge lets in, and what it runs |

## Writing one

A suite is `tests/<name>.test.sh`, sourced by the runner, using the
helpers in `tests/helpers.sh`:

```bash
test_sandbox      # a throwaway state directory, no config, no model
load_orbit        # everything bin/orbit loads, in the order it loads it

ok       "what this proves" "$expected" "$actual"
contains "what this proves" "$needle"   "$haystack"
lacks    "what this proves" "$needle"   "$haystack"
succeeds "what this proves" some-command --with args
```

Suites are sourced into the runner's own shell, so give local variables
names nobody else would pick.

A Python suite is `tests/<name>.py` and a Node one `tests/<name>.mjs`,
each run on its own, printing failures to stdout and ending with a line
`TALLY <passed> <failed>`. A suite that reports `TALLY 0 0` is treated as
skipped rather than passed.

## The rule

Every case in here is a thing that actually went wrong. When something
breaks, the fix comes with the sentence that broke it - which is how
`"did the pain go away?"` (which used to close the microphone) and
`"set a timer for two hours"` (which used to run for two minutes) ended
up as tests rather than as a second bug report.
