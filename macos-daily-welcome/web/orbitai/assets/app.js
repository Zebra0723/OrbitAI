// Shared front end for every page.
//
// Served from the Mac, the bridge is same-origin and needs nothing. Served
// from Vercel, the page runs in your browser and talks straight to
// 127.0.0.1 - so it has to be told where the bridge is, and prove it was
// invited. Without the token any site you visited could drive your Mac.

const $ = (id) => document.getElementById(id);
const $$ = (sel, root = document) => [...root.querySelectorAll(sel)];

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

function esc(value) {
  return String(value ?? "").replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
}

function out(id, text) { const el = $(id); if (el) el.textContent = text || ""; }

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
    return state;
  } catch (error) {
    dot.className = "dot off";
    if (label) label.textContent = LOCAL ? "bridge down" : "not connected";
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
