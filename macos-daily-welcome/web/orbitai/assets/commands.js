// The command reference. Static, because it documents what the rules
// understand - and the rules are in the repo, not on the Mac.
const COMMANDS = [
  ["Messages", "message Mama saying I'm running late", "Sends an iMessage after reading it back"],
  ["Messages", "text Priya saying dinner at eight", "Same, shorter phrasing"],
  ["Calls", "call Mama", "Dials through FaceTime, relayed by your iPhone"],
  ["Calls", "facetime Priya", "Video call"],
  ["Calls", "hang up", "Ends the current call"],
  ["Claude", "tell Claude to fix the flaky test in the dailyos repo", "Runs Claude Code there, reports back in the next briefing"],
  ["Claude", "go to Claude and say this: rewrite the parser", "Same, said the way people actually say it"],
  ["Mail", "reply to all emails awaiting reply saying I'm on vacation", "Drafts them all, sends on your yes"],
  ["Mail", "any new email", "Reads out who and what"],
  ["Sound", "volume up / down / set volume to 40 / mute", "Immediate"],
  ["Display", "brighter, dimmer, dark mode, light mode", "Immediate"],
  ["Music", "play, pause, next song, previous track", "Music, then Spotify, then the media key"],
  ["Music", "play bohemian rhapsody on spotify", "Searches Spotify"],
  ["Apps", "open Spotify / quit Slack / switch to Safari", "Quitting is confirmed first"],
  ["Apps", "in Safari click New Private Window", "Clicks the real menu item, so it works for any app"],
  ["Windows", "minimise, full screen, close this window, hide everything", "Immediate"],
  ["System", "lock my Mac, go to sleep, turn off the display", "Sleep is confirmed first"],
  ["System", "restart, shut down", "Confirmed first"],
  ["Network", "turn wifi on / off, bluetooth on / off", "Bluetooth needs blueutil"],
  ["Files", "take a screenshot, empty the trash, find the file taxes 2025", "Trash is confirmed first"],
  ["Web", "search for flights to Delhi", "Opens your search engine"],
  ["Bits", "what time is it, how much battery, read my clipboard", "Answered locally, instantly"],
  ["Making things", "remind me to call the dentist", "Adds to Reminders"],
  ["Making things", "make a note saying buy milk", "Adds to Notes"],
  ["Making things", "set a timer for ten minutes", "Tells you when it is up"],
  ["Reading back", "brief me", "The full briefing again"],
  ["Reading back", "what's on my calendar, read my messages", "Just that section"],
  ["Questions", "how long do I boil an egg", "Answered by Claude, in a sentence or two"],
  ["Screen", "what's this error", "Screenshots, reads it, explains it"],
  ["Talking", "thank you, that's all", "Ends the conversation"],
  ["Talking", "stop", "Cuts it off mid-sentence"],
  ["Talking", "stop talking, be quiet, shut up", "Stops the voice - your Mac's own sound is left alone"],
  ["Talking", "stop listening, leave me alone, go away", "Closes the microphone until you ask for it back"],
  ["Talking", "wake up, listen again", "Opens it again - so do Option Space and the menu bar item"],
  ["Calls", "(nothing to say)", "Listening stops on its own while another app is using the microphone"],
  ["Calls", "Option Space during a call", "Overrides that for a minute, if you want it anyway"],
];

function drawCommands(filter = "") {
  const needle = filter.toLowerCase();
  $("commands").innerHTML = COMMANDS
    .filter(([tag, phrase, what]) =>
      !needle || (tag + phrase + what).toLowerCase().includes(needle))
    .map(([tag, phrase, what]) => `
      <div class="cmd"><span class="tag">${esc(tag)}</span>
        <div class="phrase">${esc(phrase)}</div>
        <div class="what">${esc(what)}</div></div>`).join("")
    || `<p class="muted">Nothing matches that.</p>`;
}

on("filter-commands", () => drawCommands($("filter").value));
drawCommands();
