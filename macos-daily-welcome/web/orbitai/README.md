# OrbitAI console

The page that manages the assistant. It is a static site with no backend:
everything it shows comes from a bridge running on your own Mac, and every
request goes browser to localhost, never through this site.

## Deploy

```bash
cd macos-daily-welcome/web/orbitai
vercel deploy --prod
```

Then, on the Mac, tell the bridge which deployment may talk to it:

```bash
orbit console --allow https://your-project.vercel.app
orbit console --bridge          # prints the pairing token, keeps running
```

Open the deployed page, paste the bridge address and token once, and it
remembers them.

## Why a token

A browser will let any page talk to `127.0.0.1`. Since this assistant can
send mail and place calls, the bridge refuses cross-origin requests unless
they carry the token it printed, and only from an origin you allowed.

Safari blocks pages served over HTTPS from reaching a local address at all.
Chrome and Firefox allow it. If you use Safari, run the console locally
instead - `orbit console` serves the same page from the Mac.
