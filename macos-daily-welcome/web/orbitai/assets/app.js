// Shared front end for every page.
//
// Served from the Mac, the bridge is same-origin and needs nothing. Served
// from Vercel, the page runs in your browser and talks straight to
// 127.0.0.1 - so it has to be told where the bridge is, and prove it was
// invited. Without the token any site you visited could drive your Mac.

const $ = (id) => document.getElementById(id);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

// ---------------------------------------------------------------- actions
//
// Nothing on this site uses an inline onclick. An inline handler resolves
// its names against the ELEMENT first and the window last, and browsers
// keep adding element properties: HTMLButtonElement recently gained
// `command`, so `onclick='command()'` began calling a string and threw
// "command is not a function" - the Run button simply stopped working,
// with nothing on screen to say why. Handlers are registered by name here
// and bound once, so a new element property can never shadow one.

const ACTIONS = {};

function on(name, fn) { ACTIONS[name] = fn; }

function fire(el, name) {
  const fn = ACTIONS[name];
  if (fn) fn(el.dataset.arg, el);
}

document.addEventListener("click", (event) => {
  const el = event.target.closest("[data-act]");
  if (!el) return;
  event.preventDefault();
  fire(el, el.dataset.act);
});

document.addEventListener("change", (event) => {
  const el = event.target.closest("[data-change]");
  if (el) fire(el, el.dataset.change);
});

document.addEventListener("input", (event) => {
  const el = event.target.closest("[data-input]");
  if (el) fire(el, el.dataset.input);
});

// Enter submits whichever box you are typing in.
document.addEventListener("keydown", (event) => {
  if (event.key !== "Enter") return;
  const el = event.target.closest("[data-enter]");
  if (el) fire(el, el.dataset.enter);
});


const LOCAL = ["127.0.0.1", "localhost"].includes(location.hostname);
const store = {
  get bridge() { return LOCAL ? "" : (localStorage.getItem("orbit.bridge") || "http://127.0.0.1:7717"); },
  set bridge(v) { localStorage.setItem("orbit.bridge", v); },
  get token() { return LOCAL ? "" : (localStorage.getItem("orbit.token") || ""); },
  set token(v) { localStorage.setItem("orbit.token", v); },
};

async function api(path, body) {
  const options = {
    headers: { "Content-Type": "application/json" },
    ...(body ? { method: "POST", body: JSON.stringify(body) } : {}),
  };
  if (!LOCAL && store.token) options.headers["X-Orbit-Token"] = store.token;

  const response = await fetch(store.bridge + path, options);
  if (response.status === 403) throw new Error("not paired");
  if (!response.ok) throw new Error("bridge said " + response.status);
  return response.json();
}

// One settings row, drawn the same way on every page.
//
// The label used to be a span sitting next to the control and nothing
// more, so a screen reader announced "edit text, blank" for every setting
// on the page. aria-label ties the two together. Both pages drew their
// own near-identical copy of this; now there is one.
function settingRow(setting) {
  const name = esc(setting.label);
  let control;
  if (setting.kind === "toggle") {
    control = `<button class="switch" role="switch" aria-label="${name}"
               aria-checked="${setting.value === "1"}"
               data-act="toggle" data-arg="${esc(setting.key)}"></button>`;
  } else if (setting.kind === "select" && Array.isArray(setting.choices)) {
    // A list of what is actually available beats a box you have to know
    // what to type into. The voices come from this Mac; the rest are
    // fixed lists that used to live in a --help somewhere.
    const options = setting.choices.map((c) =>
      `<option value="${esc(c)}"${c === setting.value ? " selected" : ""}>${esc(c)}</option>`
    ).join("");
    control = `<select aria-label="${name}" data-change="save"
                       data-arg="${esc(setting.key)}">${options}</select>`;
  } else {
    control = `<input type="${setting.kind === "number" ? "number" : "text"}" step="0.05"
              aria-label="${name}" value="${esc(setting.value)}"
              data-change="save" data-arg="${esc(setting.key)}">`;
  }
  return `<div class="row"><div><span>${name}</span>
    <span class="help">${esc(setting.help)}</span></div>
    <div class="control">${control}</div></div>`;
}

function esc(value) {
  return String(value ?? "").replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function out(id, text) { const el = $(id); if (el) el.textContent = text || ""; }

// Every control on every page goes through here.
//
// Without it, a control was an async function called straight from an
// onclick: the moment the bridge wasn't there the call rejected, nothing
// caught it, and the button appeared to do nothing whatsoever. On the
// deployed copy that is the state of the page until you pair, so most of
// the site read as broken. Now a failure says which failure it was.
async function act(outId, working, fn) {
  out(outId, working);
  try {
    const result = await fn();
    out(outId, typeof result === "string" ? result : "");
  } catch (error) {
    out(outId, explain(error));
  }
}

function explain(error) {
  const message = String((error && error.message) || error);
  if (message === "not paired") {
    return "Not connected.\n\n" +
      "Enter the bridge address and pairing token at the top of this page.\n" +
      "On the Mac, run: orbit console --bridge";
  }
  if (message.startsWith("bridge said")) {
    return message + ".\n\nThe bridge answered, but not with what was asked for.";
  }
  return "No answer from " + (store.bridge || "the bridge on this Mac") + ".\n\n" +
    "Start it on the Mac with: orbit console --bridge\n" +
    "Safari blocks HTTPS pages from reaching local addresses - there, run\n" +
    "orbit console and use the copy served from the Mac itself.";
}

// True once a state fetch has succeeded. Pages use it to tell "nothing
// here yet" apart from "not connected".
let connected = false;

// The connection light in the nav, on every page.
async function heartbeat() {
  const dot = $("navDot");
  const label = $("navState");
  if (!dot) return null;
  try {
    const state = await api("/api/state");
    const listening = state.status.listener.state || "idle";
    const alive = state.status.app_running;
    dot.className = "dot " + (alive ? "on" : "off");
    if (label) label.textContent = alive ? listening : "app not running";
    connected = true;
    return state;
  } catch (error) {
    dot.className = "dot off";
    if (label) label.textContent = LOCAL ? "bridge down" : "not connected";
    connected = false;
    return null;
  }
}

// Pairing, shown only on the deployed copy and only until it works.
function mountPairing() {
  const box = $("pairing");
  if (!box || LOCAL) return;
  box.hidden = false;
  $("bridgeUrl").value = store.bridge;
  $("bridgeToken").value = store.token;
}

on("pair", pair);
async function pair() {
  store.bridge = $("bridgeUrl").value.trim().replace(/\/$/, "") || "http://127.0.0.1:7717";
  store.token = $("bridgeToken").value.trim();
  out("pairOut", "Connecting...");
  const state = await heartbeat();
  out("pairOut", state ? "Connected to " + store.bridge : "No answer. Is `orbit console --bridge` running?");
  if (state && typeof window.onConnected === "function") window.onConnected(state);
}

// Marks the current page in the nav without every page hardcoding it.
function markNav() {
  const here = location.pathname.replace(/\/$/, "").split("/").pop() || "index";
  $$(".nav a.link").forEach((a) => {
    const target = a.getAttribute("href").replace(/^\.\//, "").replace(/\.html$/, "") || "index";
    if (target === here || (here === "index" && target === "")) a.setAttribute("aria-current", "page");
  });
}

document.addEventListener("DOMContentLoaded", () => {
  markNav();
  mountPairing();
  heartbeat();
  setInterval(heartbeat, 20000);
});
