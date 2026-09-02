# Tests

```
tests/run              everything, about four seconds
tests/run intents      just the suites whose names match
daily-welcome --test   the same thing, from anywhere
```

No network, no API keys, no Mac. Every test runs against a throwaway
state directory with `ORBIT_NLU=rules`, so nothing here touches your real
Orbit or reaches a model. That is deliberate: a test suite only earns its
keep if it is quick enough to run without thinking about it.

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
| `memory` | what it remembers and what it lets go of |
| `slots` | the half-finished request, and the way out of one |
| `speaker` | the voice store: matching, banning, and strangers |
| `static` | every file parses; Swift balances; no inline `onclick` |
| `plans` | `orbit plan` and `orbit run` agree on the field names |
| `prompts` | every prompt reaches its own last line |
| `sourcing` | every function called is one that exists and is loaded |

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

A Python suite is `tests/<name>.py`, run on its own, printing failures to
stdout and ending with a line `TALLY <passed> <failed>`.

## The rule

Every case in here is a thing that actually went wrong. When something
breaks, the fix comes with the sentence that broke it - which is how
`"did the pain go away?"` (which used to close the microphone) and
`"set a timer for two hours"` (which used to run for two minutes) ended
up as tests rather than as a second bug report.
