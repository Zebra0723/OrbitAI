#!/bin/bash
# The half-finished request.
#
# "Send mama a message" is a complete sentence and an incomplete
# instruction. A turn can end owing you a question, and the next thing you
# say fills it in - unless it plainly is not an answer.

test_sandbox
load_orbit

ok "nothing pending to start with" "1" "$(slot_pending >/dev/null 2>&1; echo $?)"

slot_save message body Mama
line="$(slot_pending)"
ok "the intent is kept"  "message" "$(printf '%s' "$line" | cut -f1)"
ok "so is the slot"      "body"    "$(printf '%s' "$line" | cut -f2)"
ok "and what we have"    "Mama"    "$(printf '%s' "$line" | cut -f3)"

slot_clear
ok "cleared is cleared" "1" "$(slot_pending >/dev/null 2>&1; echo $?)"

# A question nobody answered goes stale. Coming back an hour later and
# saying "hello" must not finish a message you had forgotten about.
slot_save message body Mama
awk -F'\t' 'BEGIN{OFS="\t"} $1=="AT"{$2=$2-99999} {print}' \
  "$WELCOME_STATE_DIR/pending-slot" > "$WELCOME_STATE_DIR/aged" \
  && mv "$WELCOME_STATE_DIR/aged" "$WELCOME_STATE_DIR/pending-slot"
ok "an old question is not still waiting" "1" "$(slot_pending >/dev/null 2>&1; echo $?)"

# ------------------------------------------------------- not an answer

gives_up() { if slot_is_abandon "$1"; then ok "\"$1\" is a way out" y y
             else ok "\"$1\" is a way out" y n; fi; }
answers()  { if slot_is_abandon "$1"; then ok "\"$1\" is an answer" n y
             else ok "\"$1\" is an answer" n n; fi; }

gives_up "never mind"
gives_up "forget it"
gives_up "cancel"
gives_up "nothing"
# There has to be a way out of a question other than answering it, but
# almost anything said after "what should I say to Mama?" IS the answer.
answers "I'm running late"
answers "tell her dinner is at eight"
answers "no idea, I'll call instead"

fresh() { if slot_is_new_command "$1"; then ok "\"$1\" is a new command" y y
          else ok "\"$1\" is a new command" y n; fi; }
still()  { if slot_is_new_command "$1"; then ok "\"$1\" is still the answer" n y
           else ok "\"$1\" is still the answer" n n; fi; }

fresh "what time is it"
fresh "stop listening"
fresh "hey orbit, brief me"
still "tell her I'm running late"
still "say I'll be there at six"
