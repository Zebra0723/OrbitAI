// Macros and people: two editable lists, saved back to the config files.
let state = null;

async function load() {
  state = await api("/api/state");
  drawPairs("macros", state.macros);
  drawPairs("contacts", state.contacts);
  return state;
}
window.onConnected = () => load();

function rowHtml(name = "", value = "") {
  return `<tr>
    <td class="slim"><input type="text" value="${esc(name)}" placeholder="name"></td>
    <td><input type="text" value="${esc(value)}" placeholder="value"></td>
    <td class="act"><button class="quiet" onclick="this.closest('tr').remove()">-</button></td>
  </tr>`;
}

function drawPairs(id, rows) {
  $(id).innerHTML = (rows.length ? rows : [{ name: "", value: "" }])
    .map(r => rowHtml(r.name, r.value)).join("");
}

function addRow(id) {
  $(id).insertAdjacentHTML("beforeend", rowHtml());
}

async function savePairs(id) {
  const rows = $$("tr", $(id)).map((tr) => {
    const [name, value] = $$("input", tr);
    return { name: name.value, value: value.value };
  });
  await api("/api/" + id, { rows });
  out("pairsOut", "Saved.");
}

load().catch(() => {});
