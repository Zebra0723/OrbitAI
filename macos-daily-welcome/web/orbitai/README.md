# The OrbitAI console

Static files. Every page runs in your browser and talks straight to the
Mac; nothing about your assistant passes through whoever is hosting
this.

## Where it can live

| | |
| --- | --- |
| The Mac itself | `orbit console` — opens it, no setup, nothing to pair |
| GitHub Pages | free, static, see below |
| Vercel | free, `vercel.json` is already here |

Links between pages are written with `.html` on the end. GitHub Pages
serves files literally, so `./voice` is a 404 there; Vercel's `cleanUrls`
redirects the `.html` form to the tidy one, and the Mac's own server
accepts either. Writing the extension is the one spelling that works on
all three.

## Publishing to GitHub Pages

`.github/workflows/pages.yml` does it on every push that touches this
directory. Turn it on once: **Settings → Pages → Source → GitHub
Actions**.

Then tell the Mac to accept the page, or the bridge will refuse it:

```sh
echo 'ORBIT_CONSOLE_ORIGINS="https://YOURNAME.github.io"' \
  >> ~/.config/daily-welcome/config.sh
orbit console --bridge
```

The address and the pairing token go in the two boxes at the top of the
console. The token is printed by `orbit console --bridge`.

## What will not work, and why

**Safari.** An HTTPS page reaching a `http://127.0.0.1` address is
mixed content. Chrome treats loopback as trustworthy and allows it;
Safari does not, and there is no setting for it. In Safari, use the copy
served from the Mac: `orbit console`.

**Anything without the token.** The bridge answers same-origin requests
and requests carrying the pairing token, and refuses everything else -
including any other page you happen to have open. That is deliberate:
the thing on the other end can send mail and place calls.

**A phone that is not on your network.** The page runs on the phone and
reaches for `127.0.0.1`, which on a phone is the phone. Put the Mac and
the phone on the same Tailscale network and use the Mac's address there
as the bridge.
