// Orbit on a phone.
//
// The phone is not the assistant - the Mac is. This is a way to reach it
// from the sofa, and the honest shape of that is a text box and a Send
// button: iOS Safari has no speech recognition of its own, but every iOS
// keyboard has a dictation key, which is the same thing and works. For
// hands-free, the Siri shortcut on the iPhone page is the real answer.
//
// Two states, and only ever one on screen: signed in, or not.

let signedIn = false;

on("pair-phone", () => pair());
on("ask", () => ask());
on("quick", (text) => ask(text));
on("confirm", (answer) => settle(answer));
on("listen", (action) => listen(action));
on("forget-phone", () => forget());

// ------------------------------------------------------------- signing in

async function begin() {
  // /api/hello answers before the token is checked, so this works before
  // signing in - which is the only way to tell "wrong address" apart from
  // "right address, not signed in".
  let hello = null;
  try {
    const response = await fetch((store.bridge || "") + "/api/hello");
    hello = await response.json();
  } catch (error) {
    hello = null;
  }

  if (!hello || !hello.orbit) {
    show("signin");
    $("signinWhere").textContent =
      "Nothing answered at this address. Is the Mac awake, and is " +
      "`orbit console --phone` still running on it?";
    return;
  }

  const mac = String(hello.name || "your Mac").replace(/\.local$/, "");
  if (hello.paired || (store.token && await works())) {
    signedIn = true;
    show("app");
    heartbeat();
    return;
  }

  show("signin");
  $("signinWhere").textContent = hello.pairing
    ? `Connected to ${mac}. Enter the code it is showing.`
    : `Connected to ${mac}, but it is not offering a code. ` +
      `On the Mac, run: orbit console --phone`;
}

// A token can be stored and stale - the Mac may have been reinstalled
// since. Better to find out now than on the first thing you ask it.
async function works() {
  try {
    await api("/api/state");
    return true;
  } catch (error) {
    return false;
  }
}

function pair() {
  const code = $("pairCode").value.replace(/\D/g, "");
  if (code.length !== 6) return out("signinOut", "Six digits, from the Mac's screen.");
  return act("signinOut", "Checking…", async () => {
    let answer;
    try {
      const response = await fetch((store.bridge || "") + "/api/pair", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code }),
      });
      answer = await response.json();
      if (!response.ok) throw new Error(answer.error || "that did not work");
    } catch (error) {
      $("pairCode").value = "";
      throw error;
    }
    store.token = answer.token;
    $("pairCode").value = "";
    signedIn = true;
    show("app");
    heartbeat();
    return "";
  });
}

function forget() {
  if (!confirm("Sign this phone out of Orbit?")) return;
  store.clear();
  signedIn = false;
  show("signin");
  $("signinWhere").textContent =
    "Signed out. Run `orbit console --phone` on the Mac for a new code.";
}

function show(which) {
  $("signin").hidden = which !== "signin";
  $("app").hidden = which !== "app";
}

// ------------------------------------------------------------------ using

let waiting = "";   // the plan token a yes would run

function ask(preset) {
  const text = (preset || $("askText").value).trim();
  if (!text) return say("Type something first, or tap the mic on the keyboard.");
  hideConfirm();
  say("…");
  return act(null, null, async () => {
    let answer;
    try {
      answer = await api("/api/ask", { text });
    } catch (error) {
      return say(explain(error));
    }
    if (!preset) $("askText").value = "";
    say(answer.speak || "It did that.");
    if (answer.confirm && answer.token) {
      waiting = answer.token;
      $("confirmText").textContent = answer.speak || "Go ahead?";
      $("confirm").hidden = false;
    }
  });
}

function settle(answer) {
  const plan = waiting;
  hideConfirm();
  if (!plan) return;
  say("…");
  return act(null, null, async () => {
    try {
      const result = await api(answer === "yes" ? "/api/run" : "/api/cancel",
                               { token: plan });
      say(result.speak || (answer === "yes" ? "Done." : "Cancelled."));
    } catch (error) {
      say(explain(error));
    }
  });
}

function hideConfirm() {
  waiting = "";
  $("confirm").hidden = true;
}

function listen(action) {
  say("…");
  return act(null, null, async () => {
    try {
      const result = await api("/api/listen", { action });
      say(result.output || "Done.");
    } catch (error) {
      say(explain(error));
    }
  });
}

function say(text) { $("reply").textContent = text; }

document.addEventListener("DOMContentLoaded", begin);
