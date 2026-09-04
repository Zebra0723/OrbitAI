// People: recording a voice, and deciding who it answers.
//
// Everything here was a terminal command until now, and the two that
// matter most - recording somebody, and turning the gate on - are exactly
// the two you should not have to read a manual to use. Recording blocks
// on the Mac while it waits for somebody to speak, so this page says so
// while it waits rather than sitting there looking broken.

const GATE_KEYS = ["ORBIT_SPEAKER_ID", "ORBIT_SPEAKER_REQUIRE_ENROLLED",
                   "ORBIT_BYPASS_CODE"];

let settings = null;
let roster = null;

on("toggle", (key, element) => toggle(key, element));
on("save", (key, element) => save(key, element));
on("enroll", () => enroll());
on("people", () => people());
on("who", () => ask("peopleOut", "Listening back...", "/api/who"));
on("scores", () => ask("peopleOut", "Scoring...", "/api/scores"));
on("refusals", () => ask("gateOut", "Picking a few...", "/api/refusals"));
on("banlast", () => banLast());
on("person", (arg) => person(arg));
on("setup-speaker", () => setupSpeaker());

window.onConnected = () => start();

async function start() {
  await Promise.all([loadSettings(), people()]);
}

async function loadSettings() {
  settings = await api("/api/state");
  $("gateSettings").innerHTML =
    settings.settings.filter(s => GATE_KEYS.includes(s.key)).map(settingRow).join("");
}

function save(key, element) {
  return act("gateOut", "Saving...", async () => {
    await api("/api/setting", { key, value: element.value });
    return "Saved.";
  });
}

function toggle(key, element) {
  const next = element.getAttribute("aria-checked") !== "true";
  element.setAttribute("aria-checked", String(next));
  return act("gateOut", "Saving...", async () => {
    try {
      // The gate has its own command, because turning it on also checks
      // whether it is ready to be on and says so. Writing the setting
      // straight would skip that.
      if (key === "ORBIT_SPEAKER_REQUIRE_ENROLLED") {
        const result = await api("/api/gate", { action: next ? "on" : "off" });
        await people();
        return result.output;
      }
      await api("/api/setting", { key, value: next ? "1" : "0" });
    } catch (error) {
      element.setAttribute("aria-checked", String(!next));
      throw error;
    }
    return "Saved.";
  });
}

// ------------------------------------------------------------- the roster

async function people() {
  try {
    roster = await api("/api/people");
  } catch (error) {
    $("people").innerHTML = `<p class="muted" style="margin:0">This loads once
      the page is connected to your Mac.</p>`;
    $("voiceState").textContent = "Not connected to a Mac yet.";
    return;
  }
  drawState();
  drawRoster();
}

function drawState() {
  const el = $("voiceState");
  if (!roster.installed) {
    el.innerHTML = `Voice recognition is not installed yet. It is a one-off
      download of about ninety megabytes, and it runs entirely on your Mac -
      no recording ever leaves it.
      <div class="bar" style="margin-top:10px">
        <button data-act="setup-speaker">Install it</button></div>`;
    return;
  }
  const bits = [];
  bits.push(roster.enabled ? "Recognising voices."
                           : "Installed, but switched off below.");
  bits.push(roster.gate ? "Voices it does not know are turned away."
                        : "It refuses nobody it has not been told to.");
  if (roster.bypass) bits.push(`A bypass is open for another ${esc(roster.bypass)} minutes.`);
  el.textContent = bits.join(" ");
}

function drawRoster() {
  const rows = roster.people || [];
  if (!rows.length) {
    $("people").innerHTML = `<p class="muted" style="margin:0">Nobody is
      enrolled yet. Put a name in the box above and press Record.</p>`;
    return;
  }
  $("people").innerHTML = rows.map((p) => {
    const name = esc(p.name);
    const count = `${p.samples} recording${p.samples === 1 ? "" : "s"}`;
    const flag = p.banned ? ' <span class="help">refused</span>' : "";
    const ban = p.banned
      ? `<button class="quiet" data-act="person" data-arg="unban:${name}">Allow</button>`
      : `<button class="quiet" data-act="person" data-arg="ban:${name}">Refuse</button>`;
    return `<div class="row"><div><span>${name}</span>
      <span class="help">${count}${flag}</span></div>
      <div class="control">
        <button class="quiet" data-act="person" data-arg="check:${name}">Check</button>
        <button class="quiet" data-act="person" data-arg="prune:${name}">Prune</button>
        ${ban}
        <button class="quiet" data-act="person" data-arg="forget:${name}">Forget</button>
      </div></div>`;
  }).join("");
}

// data-arg carries "verb:name", because a name can be anything and a
// second attribute per button is one more thing to get out of step.
function person(arg) {
  const cut = String(arg || "").indexOf(":");
  if (cut < 0) return;
  const action = arg.slice(0, cut);
  const name = arg.slice(cut + 1);
  if (action === "forget" &&
      !confirm(`Forget ${name}? Their recordings are deleted, and Orbit stops recognising them.`)) return;
  return act("peopleOut", `${action} ${name}...`, async () => {
    const result = await api("/api/person", { action, name });
    await people();
    return result.output;
  });
}

// ------------------------------------------------------------- recording

function enroll() {
  const name = $("personName").value.trim();
  if (!name) return out("enrollOut", "Put a name in first - it is what Orbit will call them.");
  return act("enrollOut",
    `Recording. Speak now, in your ordinary voice, for a few seconds.\n` +
    `Orbit will not answer and is not listening for the wake word.`,
    async () => {
      const result = await api("/api/enroll", { name });
      $("personName").value = "";
      await people();
      return result.output;
    });
}

function banLast() {
  const label = $("banLabel").value.trim();
  return act("banOut", "Keeping that voice...", async () => {
    const result = await api("/api/banlast", label ? { label } : {});
    $("banLabel").value = "";
    await people();
    return result.output;
  });
}

on("bypass", (action) => act("gateOut", "...", async () => {
  const result = await api("/api/bypass", { action });
  await people();
  return result.output;
}));

function setupSpeaker() {
  return act("peopleOut",
    "Downloading. This takes a few minutes the first time and nothing else\n" +
    "on this page will answer until it finishes.",
    async () => {
      const result = await api("/api/setup", { what: "speaker" });
      await people();
      return result.output;
    });
}

function ask(target, working, path) {
  return act(target, working, async () => (await api(path)).output);
}

start().catch(() => {
  $("gateSettings").innerHTML = `<p class="muted" style="margin:0">These load
    once this page is connected to your Mac.</p>`;
});
