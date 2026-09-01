// Voice page: the key, which voice, and how it delivers a line.
const VOICE_KEYS = ["WELCOME_ELEVEN_VOICE_ID", "WELCOME_ELEVEN_SPEED",
                    "WELCOME_ELEVEN_STABILITY", "WELCOME_VOLUME"];
const TONE_KEYS = ["ORBIT_MATCH_TONE", "WELCOME_HONORIFIC", "ORBIT_SIGNOFF", "ORBIT_GREETING"];

let state = null;

async function load() {
  state = await api("/api/state");
  draw("voiceSettings", VOICE_KEYS);
  draw("toneSettings", TONE_KEYS);
  return state;
}
window.onConnected = () => load();

function draw(target, keys) {
  $(target).innerHTML = state.settings.filter(s => keys.includes(s.key)).map((setting) => {
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
  out("voiceOut", "Saved " + key + ".");
}

async function toggle(key, element) {
  const next = element.getAttribute("aria-checked") !== "true";
  element.setAttribute("aria-checked", String(next));
  await save(key, next ? "1" : "0");
}

async function setKey() {
  const key = $("apiKey").value.trim();
  if (!key) return;
  out("voiceOut", "Saving...");
  const result = await api("/api/key", { key });
  $("apiKey").value = "";
  out("voiceOut", result.output);
}

async function voices() { out("voiceOut", "Asking ElevenLabs..."); out("voiceOut", (await api("/api/voices")).output); }

async function previewVoice() {
  const text = $("preview").value.trim();
  if (!text) return;
  out("voiceOut", "Speaking...");
  const result = await api("/api/say", { text });
  out("voiceOut", result.ok ? "Played on the Mac." : result.output);
}

load().catch(() => {});
