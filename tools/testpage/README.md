# Blocking test page

A tiny page that requests four scripts and one image from known ad hosts
(`googlesyndication.com`, `doubleclick.net`), inserts an ad slot and offers a
popup button. It reports how many of those requests **actually loaded** — a
working blocker shows `0` while the request count finishes.

```bash
cd tools/testpage
python3 -m http.server 8099
```

Then open one of these as an app:

- Android emulator: `http://10.0.2.2:8099/`
- Android device / iOS simulator / macOS: `http://<host-ip>:8099/`
  (the iOS simulator and macOS share the host network, so `127.0.0.1:8099` works)
- PWA: `http://localhost:8099/` in a tab (no blocking expected — the web build
  cannot intercept another origin's requests)

What to expect: the big number stays at `0`, "AD SLOT — should be hidden" never
appears, and the native shield counter rises (Android counts network blocks,
iOS/macOS count cosmetic and popup filtering).

> Runs an HTTP server with no auth on your LAN. Stop it when you are done.
