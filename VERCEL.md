# Deploying the console to Vercel

The site is static files. Import this repository at
[vercel.com/new](https://vercel.com/new) and deploy — the `vercel.json`
at the root points at `macos-daily-welcome/web/orbitai` and turns the
build off, so there is nothing to configure and nothing to install.

Every page runs in the visitor's browser and talks to their own Mac.
Nothing about anybody's assistant passes through Vercel.

## The one setting afterwards

The Mac refuses a page it has not been told about, so on the Mac:

```sh
echo 'ORBIT_CONSOLE_ORIGINS="https://your-project.vercel.app"' \
  >> ~/.config/daily-welcome/config.sh
orbit console --bridge
```

That prints a pairing token. The address and the token go in the two
boxes at the top of the console.

Preview deployments get their own subdomain, so either add each one, or
set `ORBIT_CONSOLE_VERCEL="your-project"` to accept the project and its
previews. That is not a security boundary — every request still has to
carry the token — so name the exact host if you want one.

## Safari

An HTTPS page reaching `http://127.0.0.1` is mixed content. Chrome
treats loopback as trustworthy and allows it; Safari does not, and there
is no setting for it. In Safari use the copy served by the Mac itself:
`orbit console`.
