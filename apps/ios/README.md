# LinkDeck for iOS

Your links, as apps. Paste a web address and it becomes a tile on a dark deck.
Tapping it opens the site full-screen in a `WKWebView` with the ads, trackers and
popups filtered out.

SwiftUI · iOS 17+ · iPhone & iPad · no accounts, no analytics, no bundled links.

## Build & run (simulator)

Requires Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`).

```sh
cd apps/ios
./build.sh          # xcodegen + simulator build (no signing)
./run.sh            # install & launch on the booted iPhone 17, writes screenshot.png
./run.sh --no-build # skip the build step
```

The project is generated from `project.yml`; edit that, not
`LinkDeck.xcodeproj`. Bundle id `dev.linkdeck.app`, deployment target iOS 17.0.

## Device build

Open the generated project, pick your team and run on a device — or build an
unsigned IPA and re-sign it with your own profile:

```sh
./build-ipa.sh      # -> LinkDeck-unsigned.ipa
```

## Tests

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild test -project LinkDeck.xcodeproj -scheme LinkDeck \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

The `LinkDeckUITests` target covers the empty deck, adding a link, the grid, the
settings sheet and the add-link sheet.

## Deep links & automation

```sh
xcrun simctl openurl booted "linkdeck://open?url=https%3A%2F%2Fexample.com&name=Example"
```

`linkdeck://open?url=…` adds a site and opens it immediately (useful from
Shortcuts or another app). For headless simulator checks, the app also accepts a
transient site without touching the deck:

```sh
SIMCTL_CHILD_LINKDECK_OPEN_URL="http://127.0.0.1:8099/" \
SIMCTL_CHILD_LINKDECK_OPEN_NAME="Ad Test" \
xcrun simctl launch booted dev.linkdeck.app
```

(Serve `tools/testpage/` first; the iOS simulator shares the Mac's network.)

## What it does

- **Deck** — adaptive 150 pt grid, DuckDuckGo favicons with deterministic letter
  fallbacks, cumulative blocked count per link. Long-press a tile for Open, Add to
  Home Screen, Rename, Remove.
- **Add a link** — URL + optional name, `https://` normalization, validation,
  duplicate check, suggested name (`www.arte.tv` → `Arte`).
- **Browser** — full-bleed `WKWebView`, floating header with back, lock + host,
  shield counter and menu (Reload, Desktop site, Open in Safari, Add to Home
  Screen, Remove). The header fades after a few seconds and returns from the top
  grabber. Edge-swipe goes back. Videos play inline and can go full screen;
  the screen stays awake while media plays.
- **Blocking** — see below.
- **Add to Home Screen** — iOS does not let apps create home-screen web clips.
  The sheet explains this, offers Open in Safari (Share → Add to Home Screen) and
  Copy Link. The deck itself is the home screen.
- **Privacy** — deck in `Application Support/deck.json`; settings in
  `UserDefaults`; cookies/site data in the normal WebKit store. Clear them from
  Settings. The only outbound calls are the pages you open and the favicon lookup.

## How blocking works

- `Resources/blocklist.txt` (6,597 domains) is compiled once into a
  `WKContentRuleList` — one suffix-match rule per domain, so `doubleclick.net`
  also covers `ad.doubleclick.net`. The compiled list is cached in
  `WKContentRuleListStore` under a hash of the blocklist (first compile ≈5 s).
- Top-level navigation is never blocked. Opening a saved link that lives on the
  blocklist shows a one-time warning and loads it anyway.
- `Resources/cosmetic.js` is injected at document start into every frame. It
  hides ad slots and 1×1 tracker iframes, guards `window.open()` behind a real
  tap, and reports how many elements it removed.
- The shield counts cosmetic removals and blocked popups, not network requests:
  WebKit does not report which `WKContentRuleList` rule fired. Cumulative counts
  are stored per link and shown on the deck.

Verified on the simulator with `tools/testpage/`: a page requesting five known ad
hosts reported **5 requests, 0 loaded**, its ad slot stayed hidden, and the shield
incremented.

## Limits

- No per-request blocking statistics on WebKit (explained above).
- DRM/streaming depends on the platform WebKit; some players may not work.
- iOS will not create per-site home-screen icons; use Safari's Add to Home Screen
  for that if you want a separate icon.
- Custom schemes (`linkdeck://`) trigger iOS's "Open in LinkDeck?" confirmation
  when launched from outside the app.
- `NSAllowsArbitraryLoads` is enabled so http sites and older embedded players
  load. Only save sites you trust.
