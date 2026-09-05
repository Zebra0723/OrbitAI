// The iPhone page. Instructions, plus the one secret the Siri shortcut
// needs typed into it.
//
// The key is behind a button rather than printed on load: this page is
// most likely to be open on a Mac with somebody looking over your
// shoulder at the steps, and a key on screen for the whole of that is a
// key on screen for the whole of that.

on("show-token", () => showToken());
on("hide-token", () => hideToken());

function showToken() {
  return act("tokenOut", "Asking the Mac…", async () => {
    const result = await api("/api/token");
    return "X-Orbit-Token\n" + result.token + "\n\n" +
      "Type it into the header field in step 2. It does not expire, and\n" +
      "anything holding it can drive this Mac - so it goes in the shortcut\n" +
      "and nowhere else.";
  });
}

function hideToken() { out("tokenOut", ""); }
