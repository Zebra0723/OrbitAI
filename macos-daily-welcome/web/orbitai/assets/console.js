// Console page: status, settings, and a way to talk to it from the keyboard.
//
// Every handler goes through act(), so a control always reports what
// happened. Before that, a call made with no bridge rejected into nothing
// and the button looked dead.
let state = null;

const OFFLINE_TILES = [
  ["App", "not connected"], ["Ears", "not connected"],
  ["Sound", "not connected"], ["Wake word", "not connected"],
];

async function load() {
  state = await api("/api/state");
  drawTiles();
  drawMute();
  drawSettings();
  drawHeard();
  return state;
}
window.onConnected = () => load().catch((error) => out("out", explain(error)));

function drawTiles() {
  const s = state.status;
  // A call takes the microphone out of Orbit's hands, and from the outside
  // that is indistinguishable from the ears having died.
  const listening = s.on_call ? "on hold" : (s.listener.state || "never started");
  const alive = ["listening", "woken", "capturing", "speaking"].includes(listening);
  $("tiles").innerHTML = [
    ["App", s.app_running ? "Running" : "Not running", s.app_running],
    ["Ears", listening, alive],
    ["Microphone", s.on_call ? s.on_call + " has it" : "free", !s.on_call],
    ["Sound", muteText(s.muted), !s.muted],
    ["Wake word", s.listener.wake || "hey orbit", true],
  ].map(([k, v, ok]) =>
    `<div class="tile"><div class="k">${esc(k)}</div>
     <div class="v ${ok ? "on" : "off"}">${esc(v)}</div></div>`).join("");
}

// "" means it may speak; "never" is muted until unmuted; else an epoch second.
function muteText(muted) {
  if (!muted) return "on";
  if (muted === "never") return "muted until unmuted";
  const until = new Date(Number(muted) * 1000);
  return "muted until " + until.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

function drawMute() {
  const muted = state.status.muted;
  const now = $("muteNow");
  now.textContent = muted ? muteText(muted) : "Sound on";
  now.classList.toggle("on", Boolean(muted));
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
  $("settings").innerHTML = state.settings.map(settingRow).join("");
}

on("listen", (action) => listen(action));
on("selftest", () => selftest());
on("command", () => command());
on("say", () => say());
on("mute", (length) => mute(length || ""));
on("mute-for", () => {
  const length = $("muteFor").value.trim();
  if (!length) return out("out", "Say how long first: 45m, 3h, until 7:30.");
  return mute(length);
});
on("unmute", () => mute(null));
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

// null unmutes; "" mutes until unmuted; anything else is a length.
function mute(length) {
  return act("out", "Working...", async () => {
    const result = await api("/api/mute", length === null ? { off: true } : { length });
    if (result.ok && length) $("muteFor").value = "";
    load().catch(() => {});
    return result.output || (result.ok ? "Done." : "That didn't work.");
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

load().catch((error) => { drawOffline(); out("out", explain(error)); });
