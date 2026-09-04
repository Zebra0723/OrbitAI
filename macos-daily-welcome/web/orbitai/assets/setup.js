// Setup: everything between "it is installed" and "it works".
//
// The install line at the top is the only terminal on this page, and it
// stays because a Mac with nothing on it has no other way to be given
// something. Everything after it is a button, including the four or five
// things that were `daily-welcome --something` until now.

const BRAIN_KEYS = ["ORBIT_NLU", "ORBIT_OPENAI_BASE", "ORBIT_OPENAI_MODEL",
                    "ORBIT_FREEFORM"];
const WAKE_KEYS = ["ORBIT_WAKE_WORD", "ORBIT_WAKE_ALIASES", "ORBIT_ONDEVICE"];

let state = null;

on("save", (key, element) => save(key, element));
on("toggle", (key, element) => toggle(key, element));
on("copy", (id) => copy(id));
on("doctor", () => ask("setupOut", "Looking over this Mac...", "/api/doctor"));
on("selftest", () => ask("setupOut", "Running...", "/api/selftest"));
on("permissions", () => post("setupOut", "Clearing what macOS remembered...", "/api/permissions"));
on("models", () => ask("brainOut", "Asking the service what it serves...", "/api/models"));
on("braintest", () => ask("brainOut", "Sending it something to understand...", "/api/braintest"));
on("brain-key", () => brainKey());
on("find-claude", () => ask("claudeOut", "Looking everywhere node puts things...", "/api/claude"));
on("claude-at", () => claudeAt());
on("install-claude", () => act("claudeOut",
  "Looking first, then installing if it really is missing.\nA few minutes if it downloads.",
  async () => (await api("/api/installclaude", {})).output));
on("heard", () => heard());
on("setup-piper", () => piper());
on("preview", () => post("piperOut", "Speaking...", "/api/preview"));

window.onConnected = () => load();

async function load() {
  state = await api("/api/state");
  draw("brainSettings", BRAIN_KEYS);
  draw("wakeSettings", WAKE_KEYS);
  return state;
}

function draw(target, keys) {
  // In the order this page talks about them, not the order the bridge
  // happens to send them.
  const rows = keys.map(k => state.settings.find(s => s.key === k)).filter(Boolean);
  $(target).innerHTML = rows.map(settingRow).join("");
}

function save(key, element) {
  return act("setupOut", "Saving...", async () => {
    await api("/api/setting", { key, value: element.value });
    return "Saved. The app restarts to pick it up.";
  });
}

function toggle(key, element) {
  const next = element.getAttribute("aria-checked") !== "true";
  element.setAttribute("aria-checked", String(next));
  return act("setupOut", "Saving...", async () => {
    try {
      await api("/api/setting", { key, value: next ? "1" : "0" });
    } catch (error) {
      element.setAttribute("aria-checked", String(!next));
      throw error;
    }
    return "Saved.";
  });
}

function copy(id) {
  const box = $(id);
  if (!box) return;
  box.select();
  // Clipboard access can be refused, and a button that silently does
  // nothing is worse than one that says what to do instead.
  const done = () => out("setupOut", "Copied. Paste it into Terminal.");
  if (navigator.clipboard) {
    navigator.clipboard.writeText(box.value).then(done,
      () => out("setupOut", "Your browser would not let this page copy. " +
                            "The line is selected - press command-C."));
    return;
  }
  out("setupOut", "The line is selected - press command-C.");
}

function brainKey() {
  const key = $("brainKey").value.trim();
  if (!key) return out("brainOut", "Paste the key first.");
  return act("brainOut", "Storing it in the Keychain...", async () => {
    const result = await api("/api/modelkey", { key });
    $("brainKey").value = "";
    return result.output;
  });
}

function claudeAt() {
  const path = $("claudePath").value.trim();
  if (!path) return out("claudeOut", "Put the path in first, or press Look for it.");
  return act("claudeOut", "Trying it...", async () => {
    const result = await api("/api/claudeat", { path });
    return result.output;
  });
}

function heard() {
  return act("heardOut", "Reading the log...", async () => {
    const fresh = await api("/api/state");
    const lines = (fresh.status.heard || []);
    if (!lines.length) {
      return "Nothing yet. Say something near the Mac and press this again.";
    }
    return lines.join("\n");
  });
}

function piper() {
  return act("piperOut",
    "Downloading. A few minutes the first time, and nothing else on this\n" +
    "page will answer until it finishes.",
    async () => (await api("/api/setup", { what: "piper" })).output);
}

function ask(target, working, path) {
  return act(target, working, async () => (await api(path)).output);
}

function post(target, working, path) {
  return act(target, working, async () => (await api(path, {})).output);
}

load().catch((error) => {
  const message = `<p class="muted" style="margin:0">These load once this page
    is connected to your Mac. The install line above works without it.</p>`;
  $("brainSettings").innerHTML = message;
  $("wakeSettings").innerHTML = message;
  out("setupOut", explain(error));
});
