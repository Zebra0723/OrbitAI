// Macros and people: two editable lists, saved back to the config files.
let state = null;

async function load() {
  state = await api("/api/state");
  drawPairs("macros", state.macros);
  drawPairs("contacts", state.contacts);
  return state;
}
window.onConnected = () => load().catch((error) => out("pairsOut", explain(error)));

function rowHtml(name = "", value = "") {
  return `<tr>
    <td class="slim"><input type="text" value="${esc(name)}" placeholder="name"></td>
    <td><input type="text" value="${esc(value)}" placeholder="value"></td>
    <td class="act"><button class="quiet" data-act="drop-row" title="Remove">-</button></td>
  </tr>`;
}

// Rows live in an explicit tbody. Appending a <tr> straight to <table>
// makes the parser open a SECOND tbody, and then "the last row" means two
// different rows depending on who is asking.
function body(id) {
  const table = $(id);
  let tbody = table.querySelector("tbody");
  if (!tbody) { tbody = document.createElement("tbody"); table.appendChild(tbody); }
  return tbody;
}

function drawPairs(id, rows) {
  body(id).innerHTML = (rows.length ? rows : [{ name: "", value: "" }])
    .map(r => rowHtml(r.name, r.value)).join("");
}

on("add-row", (id) => addRow(id));
on("save-pairs", (id) => savePairs(id));
on("drop-row", (_arg, el) => {
  const table = el.closest("table");
  el.closest("tr").remove();
  // A table with no rows has nothing to type into, so keep one blank.
  if (table && !table.querySelector("tr")) { drawPairs(table.id, []); }
});

function addRow(id) {
  body(id).insertAdjacentHTML("beforeend", rowHtml());
}

function savePairs(id) {
  const rows = $$("tr", $(id)).map((tr) => {
    const [name, value] = $$("input", tr);
    return { name: name.value, value: value.value };
  }).filter((r) => r.name.trim() || r.value.trim());
  return act("pairsOut", "Saving...", async () => {
    await api("/api/" + id, { rows });
    return "Saved " + rows.length + (rows.length === 1 ? " row." : " rows.");
  });
}

// Offline the tables still draw, empty. Editing them locally is harmless
// and beats staring at a panel with nothing in it.
load().catch((error) => {
  drawPairs("macros", []);
  drawPairs("contacts", []);
  out("pairsOut", explain(error));
});
