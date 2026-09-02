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
window.onConnected = () => load().catch((error) => out("voiceOut", explain(error)));

function draw(target, keys) {
  $(target).innerHTML =
    state.settings.filter(s => keys.includes(s.key)).map(settingRow).join("");
}

on("set-key", () => setKey());
on("voices", () => voices());
on("preview-voice", () => previewVoice());
on("toggle", (key, element) => toggle(key, element));
on("save", (key, element) => save(key, element));

function save(key, element) {
  const value = element.value;
  return act("voiceOut", "Saving...", async () => {
    await api("/api/setting", { key, value });
    return "Saved " + key + ".";
  });
}

function toggle(key, element) {
  const next = element.getAttribute("aria-checked") !== "true";
  element.setAttribute("aria-checked", String(next));
  return act("voiceOut", "Saving...", async () => {
    try {
      await api("/api/setting", { key, value: next ? "1" : "0" });
    } catch (error) {
      // Never leave the switch showing a state the Mac isn't in.
      element.setAttribute("aria-checked", String(!next));
      throw error;
    }
    return "Saved " + key + ".";
  });
}

function setKey() {
  const key = $("apiKey").value.trim();
  if (!key) return out("voiceOut", "Paste your ElevenLabs key first.");
  return act("voiceOut", "Saving...", async () => {
    const result = await api("/api/key", { key });
    $("apiKey").value = "";
    return result.output;
  });
}

function voices() {
  return act("voiceOut", "Asking ElevenLabs...", async () => (await api("/api/voices")).output);
}

function previewVoice() {
  const text = $("preview").value.trim();
  if (!text) return out("voiceOut", "Type a line for it to read first.");
  return act("voiceOut", "Speaking...", async () => {
    const result = await api("/api/say", { text });
    return result.ok ? "Played on the Mac." : result.output;
  });
}

function drawOffline() {
  const message = `<p class="muted" style="margin:0">These load once this page
    is connected to your Mac.</p>`;
  $("voiceSettings").innerHTML = message;
  $("toneSettings").innerHTML = message;
}

load().catch((error) => { drawOffline(); out("voiceOut", explain(error)); });
