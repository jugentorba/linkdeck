# LinkDeck for Android

Your links, as apps. Save any site to a deck, open it full-screen without browser
chrome, and block ads, trackers and popups while you browse.

Kotlin · minSdk 26 · targetSdk 36 · Material 3 · no third-party services, no accounts.

## Build

```bash
cd apps/android
./gradlew assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

Release build (minified):

```bash
./gradlew assembleRelease
```

`local.properties` must point at the Android SDK (`sdk.dir=...`). JDK 17+ is required.

## What it does

- **Deck** — grid of saved links with favicons (or deterministic letter tiles) and a
  cumulative blocked-request count per app. Long-press a tile for Open / Add to Home
  screen / Rename / Remove.
- **Add a link** — paste any address. `https://` is added automatically, the name is
  suggested from the host, and the URL is validated before saving.
- **In-app browser** — full-screen WebView with a floating header (back, host, shield,
  menu). The header hides on scroll and comes back with a tap at the top edge or an
  upward scroll. Desktop-site toggle, reload, open in system browser, remove.
- **Ad & tracker blocking** — 6,597 domain suffixes loaded from
  `app/src/main/assets/blocklist.txt`. Requests are blocked in
  `shouldInterceptRequest` (never the main document), counted in the shield, and
  persisted per app. Cosmetic filtering + popup suppression run from
  `assets/cosmetic.js` as a document-start script.
- **Add to Home screen** — a real pinned launcher shortcut with the site favicon that
  boots straight into the site (no deck).
- **Video** — full-screen video via `onShowCustomView`, immersive mode, keep-screen-on,
  third-party cookies for embedded players, autoplay allowed.
- No preinstalled links; no analytics; nothing leaves the device except the page you
  open and the favicon lookup (`icons.duckduckgo.com`).

## Layout

```
app/src/main/java/dev/linkdeck/app/
  LinkDeckApp.kt          app wiring (settings, store, blocklist, favicons)
  data/                   DeckStore (JSON prefs), Settings, BlockList, UrlTools
  media/                  IcoDecoder (ICO/BMP/PNG), FaviconLoader + letter tiles
  ui/                     MainActivity, BrowserActivity, sheets, adapter, shortcuts
app/src/main/assets/      blocklist.txt + cosmetic.js (synced from ../../shared)
```

## How blocking works

`BlockList.isBlocked(host)` suffix-matches the request host against the bundled set,
so `doubleclick.net` also covers `ad.doubleclick.net`. Blocked subresources get an empty
200 response; top-level navigations are never intercepted. The blocklist is immutable
after background loading and shared across WebView request threads.

The shield counts blocked subresource requests exactly. Cosmetic removals and blocked
popups are additional (not counted in this build).

## Notes & limits

- Blocking is conservative: it will not defeat server-side ad insertion, and some
  sites may detect an empty response and show a placeholder.
- WebView is the system WebView; DRM-protected streaming may depend on device support.
- Clear data from Settings removes the deck, cookies, site storage, favicon cache and
  blocked counts.
- `usesCleartextTraffic` and mixed content are enabled for compatibility with older
  embedded players; only browse sites you trust.

## Test page

`../../tools/testpage/index.html` loads known ad hosts, an ad slot and a popup button.
Serve it and open it in the app to watch the shield count rise:

```bash
cd tools/testpage && python3 -m http.server 8099
# open http://10.0.2.2:8099/ on the emulator, or http://<your-ip>:8099/ on a device
```
