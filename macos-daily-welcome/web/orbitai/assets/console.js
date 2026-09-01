// Console page: status, settings, and a way to talk to it from the keyboard.
let state = null;

async function load() {
  state = await api("/api/state");
  drawTiles();
  drawSettings();
  drawHeard();
  return state;
}
window.onConnected = () => load();

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

function drawHeard() {
  const heard = state.status.heard || [];
  out("heard", heard.length ? heard.join("\n") : "Nothing logged yet.");
}

function drawSettings() {
  $("settings").innerHTML = state.settings.map((setting) => {
    const control = setting.kind === "toggle"
      ? `<button class="switch" role="switch" aria-checked="${setting.value === "1"}"
                 onclick="toggle('${setting.key}', this)"></button>`
      : `<input type="${setting.kind === "number" ? "number" : "text"}" step="0.05"
                value="${esc(setting.value)}" onchange="save('${setting.key}', this.value)">`;
    return `<div class="row"><div><span>${esc(setting.label)}</span>
      <span class="help">${esc(setting.help)}</span></div>
      <div class="control">${control}</div></div>`;
  }).join("");
}

async function save(key, value) {
  await api("/api/setting", { key, value });
  out("out", "Saved " + key + ". The app restarted so it takes effect.");
}

async function toggle(key, element) {
  const next = element.getAttribute("aria-checked") !== "true";
  element.setAttribute("aria-checked", String(next));
  await save(key, next ? "1" : "0");
}

async function listen(action) {
  out("out", "Working...");
  out("out", (await api("/api/listen", { action })).output);
  setTimeout(load, 1500);
}

async function say() {
  const text = $("sayText").value.trim();
  if (!text) return;
  out("out", "Speaking...");
  const result = await api("/api/say", { text });
  out("out", result.ok ? "Said it." : result.output);
}

async function command() {
  const text = $("cmdText").value.trim();
  if (!text) return;
  out("out", "Thinking...");
  const r = (await api("/api/command", { text })).result || {};
  out("out", r.speak + (r.confirm ? "\n\nWaiting on a yes - say it out loud." : ""));
}

async function selftest() { out("out", "Running..."); out("out", (await api("/api/selftest")).output); }
async function briefing() { out("out", "Building..."); out("out", (await api("/api/briefing")).output); }

load().catch(() => {});
