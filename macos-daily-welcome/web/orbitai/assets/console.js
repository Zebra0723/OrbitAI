// Console page: status, settings, and a way to talk to it from the keyboard.
//
// Every handler goes through act(), so a control always reports what
// happened. Before that, a call made with no bridge rejected into nothing
// and the button looked dead.
let state = null;

const OFFLINE_TILES = [
  ["App", "not connected"], ["Ears", "not connected"],
  ["Last greeting", "not connected"], ["Wake word", "not connected"],
];

async function load() {
  state = await api("/api/state");
  drawTiles();
  drawSettings();
  drawHeard();
  return state;
}
window.onConnected = () => load().catch((error) => out("out", explain(error)));

function drawTiles() {
  const s = state.status;
  const listening = s.listener.state || "never started";
  const alive = ["listening", "woken", "capturing", "speaking"].includes(listening);
  $("tiles").innerHTML = [
    ["App", s.app_running ? "Running" : "Not running", s.app_running],
    ["Ears", listening, alive],
    ["Last greeting", s.last_greeting || "none yet", !!s.last_greeting],
    ["Wake word", s.listener.wake || "hey orbit", true],
  ].map(([k, v, ok]) =>
    `<div class="tile"><div class="k">${esc(k)}</div>
     <div class="v ${ok ? "on" : "off"}">${esc(v)}</div></div>`).join("");
}

// An empty page is indistinguishable from a broken one, so say which.
function drawOffline() {
  $("tiles").innerHTML = OFFLINE_TILES.map(([k, v]) =>
    `<div class="tile"><div class="k">${esc(k)}</div>
     <div class="v off">${esc(v)}</div></div>`).join("");
  $("settings").innerHTML =
    `<p class="muted" style="margin:0">Settings load once this page is
     connected to your Mac.</p>`;
  out("heard", "Not connected.");
}

function drawHeard() {
  const heard = state.status.heard || [];
  out("heard", heard.length ? heard.join("\n") : "Nothing logged yet.");
}

function drawSettings() {
  $("settings").innerHTML = state.settings.map((setting) => {
    const control = setting.kind === "toggle"
      ? `<button class="switch" role="switch" aria-checked="${setting.value === "1"}"
                 data-act="toggle" data-arg="${esc(setting.key)}"></button>`
      : `<input type="${setting.kind === "number" ? "number" : "text"}" step="0.05"
                value="${esc(setting.value)}" data-change="save" data-arg="${esc(setting.key)}">`;
    return `<div class="row"><div><span>${esc(setting.label)}</span>
      <span class="help">${esc(setting.help)}</span></div>
      <div class="control">${control}</div></div>`;
  }).join("");
}

on("listen", (action) => listen(action));
on("selftest", () => selftest());
on("briefing", () => briefing());
on("command", () => command());
on("say", () => say());
on("toggle", (key, element) => toggle(key, element));
on("save", (key, element) => save(key, element));

function save(key, element) {
  const value = element.value;
  return act("out", "Saving...", async () => {
    await api("/api/setting", { key, value });
    return "Saved " + key + ". The app restarted so it takes effect.";
  });
}

function toggle(key, element) {
  const next = element.getAttribute("aria-checked") !== "true";
  element.setAttribute("aria-checked", String(next));
  return act("out", "Saving...", async () => {
    try {
      await api("/api/setting", { key, value: next ? "1" : "0" });
    } catch (error) {
      // Put the switch back: it should never show a state the Mac isn't in.
      element.setAttribute("aria-checked", String(!next));
      throw error;
    }
    return "Saved " + key + ". The app restarted so it takes effect.";
  });
}

function listen(action) {
  return act("out", "Working...", async () => {
    const result = await api("/api/listen", { action });
    load().catch(() => {});
    return result.output || "Done.";
  });
}

function say() {
  const text = $("sayText").value.trim();
  if (!text) return out("out", "Type something for it to say first.");
  return act("out", "Speaking...", async () => {
    const result = await api("/api/say", { text });
    return result.ok ? "Said it." : result.output;
  });
}

function command() {
  const text = $("cmdText").value.trim();
  if (!text) return out("out", "Type a command first.");
  return act("out", "Thinking...", async () => {
    const r = (await api("/api/command", { text })).result || {};
    return (r.speak || "Nothing came back.") +
      (r.confirm ? "\n\nWaiting on a yes - say it out loud." : "");
  });
}

function selftest() {
  return act("out", "Running...", async () => (await api("/api/selftest")).output);
}

function briefing() {
  return act("out", "Building...", async () => (await api("/api/briefing")).output);
}

load().catch((error) => { drawOffline(); out("out", explain(error)); });
