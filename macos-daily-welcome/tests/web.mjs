// Load every page in a real browser, click every control, and fail on
// anything that breaks.
//
// The buttons on this site died once with no error and nothing on screen:
// Chromium had grown a `command` property on button elements, which
// shadowed the global function an inline onclick was trying to call. The
// only way to know that had happened was to click them in the browser
// people actually use, so that is what this does.
import { createRequire } from 'module';
import { execSync } from 'child_process';
import http from 'http';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const require = createRequire(import.meta.url);

// Playwright is not part of installing this, and asking somebody to
// install a browser automation framework to run the tests is a good way
// to have nobody run the tests. If it is here, the site gets driven; if
// it is not, that is said out loud and everything else still runs.
function findPlaywright() {
  const roots = [];
  try { roots.push(execSync('npm root -g', { encoding: 'utf8' }).trim()); } catch {}
  roots.push('/opt/node22/lib/node_modules', '/usr/lib/node_modules',
             '/usr/local/lib/node_modules', '/opt/homebrew/lib/node_modules');
  for (const root of roots) {
    try { return require(path.join(root, 'playwright')); } catch {}
  }
  try { return require('playwright'); } catch {}
  return null;
}

const playwright = findPlaywright();
if (!playwright) {
  console.log('  web: skipped - playwright is not installed');
  console.log('    npm install -g playwright && npx playwright install chromium');
  console.log('TALLY 0 0');
  process.exit(0);
}
const { chromium } = playwright;

const HERE = path.dirname(fileURLToPath(import.meta.url));
const SITE = process.argv[2] || path.join(HERE, '..', 'web', 'orbitai');
const TYPES = { '.html': 'text/html', '.css': 'text/css', '.js': 'text/javascript',
                '.json': 'application/json', '.svg': 'image/svg+xml' };

// Served the way the Mac serves it: /voice finds voice.html, the way
// Vercel's cleanUrls does. If those two ever disagree, every link in the
// navigation breaks on one of them.
// A bridge that answers the way the real one does. Without it every
// control fails at the first fetch and the interesting half of each
// handler - the part that renders what came back - is never reached.
const BRIDGE = {
  // The exact shape web/server.py returns. Mocking a shape of one's own
  // proves the mock works and nothing else.
  '/api/state': () => ({
    settings: [
      { key: 'WELCOME_NAME', kind: 'text', label: 'Your name', help: 'what it calls you', value: 'Arjun' },
      { key: 'WELCOME_SPEAK', kind: 'toggle', label: 'Speak', help: 'out loud', value: '1' },
      { key: 'WELCOME_PAUSE_MS', kind: 'number', label: 'Pause', help: 'at a comma', value: '210' },
      { key: 'WELCOME_ELEVEN_VOICE_ID', kind: 'text', label: 'Voice', help: '', value: 'veda-sky' },
      { key: 'WELCOME_ELEVEN_SPEED', kind: 'number', label: 'Speed', help: '', value: '1.0' },
      { key: 'WELCOME_VOLUME', kind: 'number', label: 'Volume', help: '', value: '0.8' },
      { key: 'ORBIT_MATCH_TONE', kind: 'toggle', label: 'Match tone', help: '', value: '1' },
      { key: 'WELCOME_HONORIFIC', kind: 'text', label: 'Honorific', help: '', value: 'sir' },
    ],
    status: {
      app_running: true,
      listener: { state: 'listening', wake: 'hey orbit', updated: '2026-09-02T19:00:00Z' },
      heard: ['what time is it', 'hey orbit'],
      last_greeting: '2026-09-02',
      on_call: '',
    },
    contacts: [{ name: 'Mama', value: '+15551234567' }],
    macros: [{ name: 'good night', value: 'dark mode; turn off wifi' }],
  }),
  '/api/voices':   () => ({ ok: true, output: 'Ava (Premium)\nZoe (Premium)' }),
  '/api/selftest': () => ({ ok: true, output: 'everything works' }),
  '/api/briefing': () => ({ ok: true, output: 'Good evening, Arjun.' }),
  '/api/setting':  () => ({ ok: true }),
  '/api/say':      () => ({ ok: true, output: 'said it' }),
  '/api/command':  () => ({ ok: true, result: { speak: "It's seven o'clock in the evening.",
                                                confirm: false, token: '' } }),
  '/api/listen':   () => ({ ok: true, output: 'listening' }),
  '/api/key':      () => ({ ok: true, output: 'stored' }),
  '/api/contacts': () => ({ ok: true }),
  '/api/macros':   () => ({ ok: true }),
};

const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  if (url.startsWith('/api/')) {
    const handler = BRIDGE[url];
    res.writeHead(handler ? 200 : 404, { 'Content-Type': 'application/json' });
    // Recorded, so a control that calls an endpoint nobody implements is
    // a finding rather than a shrug.
    if (!handler) missingApi.add(url); else served.push(url);
    return res.end(JSON.stringify(handler ? handler() : { error: 'no such thing' }));
  }
  let name = url.replace(/^\/+/, '') || 'index.html';
  let file = path.join(SITE, name);
  if (!fs.existsSync(file) || fs.statSync(file).isDirectory()) file = path.join(SITE, name + '.html');
  if (!fs.existsSync(file)) { res.writeHead(404); return res.end('no'); }
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'text/plain' });
  res.end(fs.readFileSync(file));
});
await new Promise(r => server.listen(0, r));
const base = `http://127.0.0.1:${server.address().port}/`;

let pass = 0, fail = 0;
const missingApi = new Set();
let served = [];
const say = (okay, what, detail) => {
  if (okay) pass++;
  else { fail++; console.log(`  web: ${what}\n    ${detail}\n`); }
};

// The bridge is not running here, and there is no network. Neither is
// the page's fault.
const expected = (text) =>
  /127\.0\.0\.1:(?!PORT)|localhost:|fonts\.googleapis|fonts\.gstatic/.test(text) ||
  /ERR_CONNECTION_(REFUSED|RESET)|Failed to load resource/.test(text);

const files = fs.readdirSync(SITE).filter(f => f.endsWith('.html')).sort();
let browser;
try {
  browser = await chromium.launch();
} catch (error) {
  console.log('  web: skipped - playwright has no browser to drive');
  console.log('    ' + String(error.message).split('\n')[0]);
  console.log('TALLY 0 0');
  server.close();
  process.exit(0);
}

for (const file of files) {
  const page = await browser.newPage();
  const errors = [];
  const note = (t) => { if (!expected(t)) errors.push(t); };
  page.on('pageerror', e => note('pageerror: ' + e.message));
  page.on('console', m => { if (m.type() === 'error') note('console: ' + m.text()); });
  page.on('requestfailed', r => note('failed request: ' + r.url()));

  served = [];
  // Nothing leaves this machine. Letting the font stylesheet try to
  // reach Google added thirteen seconds per page waiting for a request
  // that was never going to arrive, and made the suite too slow to run.
  await page.route('**', (route) => {
    const url = route.request().url();
    if (url.startsWith(base)) return route.continue();
    return route.abort();
  });

  const res = await page.goto(base + file, { waitUntil: 'load' });
  await page.waitForTimeout(200);

  say(res.status() === 200, `${file} is served`, 'status ' + res.status());
  say(errors.length === 0, `${file} loads clean`, errors.join('\n    '));

  const registered = await page.evaluate(() =>
    (typeof ACTIONS === 'object' && ACTIONS) ? Object.keys(ACTIONS) : null);
  const asked = await page.$$eval('[data-act],[data-change]',
    els => [...new Set(els.map(e => e.dataset.act || e.dataset.change))]);

  if (asked.length) {
    say(registered !== null, `${file} has an action registry`,
        'ACTIONS is not defined, so nothing on the page can work');
    const missing = registered ? asked.filter(a => !registered.includes(a)) : asked;
    say(missing.length === 0, `${file}: every control has a handler`,
        'no handler registered for: ' + missing.join(', '));
  }

  if (asked.length) {
    // Proof the handlers really ran, rather than the page being quiet
    // because nothing happened at all.
    say(served.length > 0, `${file}: the controls reached the bridge`,
        'not one request was made, so no handler did anything');

    // What the bridge sent, as drawn. Checked BEFORE anything is clicked:
    // some of these controls exist to remove a row, and a check after
    // them is a check of the wrong page.
    //
    // Text on the page AND what is in the boxes: a setting arrives as the
    // value of an input, which innerText does not see.
    const text = await page.evaluate(() => document.body.innerText + '\n' +
      [...document.querySelectorAll('input,textarea,select')].map(e => e.value).join('\n'));
    const want = { 'console.html': ['Arjun', 'listening', 'Running', 'hey orbit',
                                    'what time is it', '2026-09-02'],
                   'macros.html': ['Mama', '+15551234567', 'good night'],
                   'voice.html': ['veda-sky', 'sir'] }[file];
    if (want) for (const needle of want) {
      say(text.includes(needle), `${file}: shows "${needle}" from the bridge`,
          'the page fetched it and did not draw it');
    }
  }

  // Click them all. A handler that throws is a button that does nothing.
  const before = errors.length;
  for (const act of asked) {
    for (const el of await page.$$(`[data-act="${act}"]`)) {
      if (!(await el.isVisible())) continue;
      await el.click({ timeout: 2000 }).catch(e =>
        errors.push(`clicking ${act}: ${e.message.split('\n')[0]}`));
      await page.waitForTimeout(60);
    }
  }
  say(errors.length === before, `${file}: clicking every control is quiet`,
      errors.slice(before).join('\n    '));


  // Every control can be reached by name. A button whose only content is
  // an icon reads as "button" to a screen reader and to nobody else.
  const nameless = await page.$$eval('button, a, input, select, textarea', els => els
    .filter(e => {
      if (e.type === 'hidden' || e.offsetParent === null) return false;
      const name = (e.getAttribute('aria-label') || e.title ||
                    e.textContent || e.placeholder || '').trim();
      const labelled = e.id && document.querySelector(`label[for="${e.id}"]`);
      return !name && !labelled;
    })
    .map(e => e.tagName.toLowerCase() + (e.className ? '.' + e.className.split(' ')[0] : '')));
  say(nameless.length === 0, `${file}: every control has a name`,
      nameless.join(', '));

  // On a phone. A page that scrolls sideways is a page nobody reads on
  // one, and this site's whole job is being read on a small screen at
  // arm's length.
  await page.setViewportSize({ width: 375, height: 780 });
  await page.waitForTimeout(120);
  const overflow = await page.evaluate(() =>
    document.documentElement.scrollWidth - document.documentElement.clientWidth);
  say(overflow <= 1, `${file}: fits a phone`, `${overflow}px of sideways scroll at 375px`);
  await page.setViewportSize({ width: 1280, height: 800 });

  const dead = await page.$$eval('a[href]', as => as.map(a => a.getAttribute('href'))
    .filter(h => h === '#' || h === '' || h === 'javascript:void(0)'));
  say(dead.length === 0, `${file}: no link that goes nowhere`, dead.join(', '));

  // Every internal link resolves - through the same clean-URL rule the
  // Mac and Vercel both use.
  const internal = await page.$$eval('a[href]', as => as.map(a => a.getAttribute('href'))
    .filter(h => h && !/^(https?:|mailto:|#|javascript:)/.test(h)));
  for (const href of [...new Set(internal)]) {
    const url = new URL(href, base + file);
    const status = await fetch(url).then(r => r.status).catch(() => 0);
    say(status === 200, `${file}: ${href} resolves`, 'status ' + status);
  }

  // The affiliate line the site is supposed to carry.
  const dailyos = await page.$$eval('a[href*="dailyos.uk"]', as => as.length);
  say(dailyos > 0, `${file}: links to dailyos.uk`, 'no DailyOS link on the page');

  await page.close();
}

say(missingApi.size === 0, 'every endpoint a control calls exists on the bridge',
    [...missingApi].join(', ') + ' - web/server.py does not answer these');

await browser.close();
server.close();
console.log(`TALLY ${pass} ${fail}`);
process.exit(fail ? 1 : 0);
