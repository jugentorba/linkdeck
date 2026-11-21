# LinkDeck for macOS

Your links, as apps. Save any site to a deck, then open it in a clean window with
no browser chrome, no ads, and no popups.

LinkDeck is a native SwiftUI + AppKit app. Each deck entry opens a `WKWebView`
with a floating header that gets out of the way. The signature feature is
**Pin as app**: LinkDeck generates a real `.app` in `~/Applications/LinkDeck`,
using the site's favicon as its icon. Launching that app goes straight to the
site, with its own Dock icon and its own window.

## Features

- **Deck** — adaptive grid of tiles with favicons, names, hosts, and cumulative
  blocked counts. Right-click a tile for Open, Pin as app, Rename, or Remove.
- **Add a link** — `⌘N`, or the `+` button. URLs without a scheme get `https://`.
  The name is suggested from the host and can be edited. No links ship with the
  app.
- **App window** — a hidden-title-bar window with visible traffic lights, filled
  by the site. The floating header shows back, lock + host, session shield count,
  and a menu. It auto-hides after three seconds; click the slim bar at the top
  edge to bring it back.
- **Blocking** — 6,603 suffix-matched ad/tracker domains compiled into a cached
  `WKContentRuleList`, plus cosmetic filtering and a popup guard injected at
  document start in every frame. Top-level navigation is never blocked.
- **Pin as app** — generated `.app` bundles in `~/Applications/LinkDeck`, with a
  custom `.icns` made from the site favicon. A `PinnedLink.json` marker makes the
  copy open the site directly instead of the deck.
- **Local-only data** — `~/Library/Application Support/LinkDeck/deck.json`.
  Settings live in `UserDefaults`. There is no account, sync, or analytics.

## Build and run

Requirements: macOS 14 or later, Xcode (tested with Xcode 27.2), XcodeGen.

```sh
cd apps/macos
./build.sh
open build/LinkDeck.app
```

`build.sh` exports `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`,
runs `xcodegen generate`, builds the Release configuration with
`CODE_SIGNING_ALLOWED=NO`, copies the product to `build/LinkDeck.app`, and
ad-hoc signs it. It is idempotent.

The Xcode project is generated from `project.yml`; edit that file rather than
`LinkDeck.xcodeproj`. The bundle identifier is `dev.linkdeck.mac`, deployment
target is macOS 14.0, and the app category is Productivity.

### Self-test

The app has a headless diagnostic mode. It exercises URL normalization, name
suggestions, deck persistence, rule-list generation, and (optionally) a complete
pin-as-app build in a temporary folder, then exits with status 0 or 1.

```sh
./build/LinkDeck.app/Contents/MacOS/LinkDeck --self-test
./build/LinkDeck.app/Contents/MacOS/LinkDeck --self-test --pin-test
```

The pin test never writes to `~/Applications` and never adds links to the real
deck.

## Pin as app

From a deck tile's context menu, or the app-window `⋯` menu, choose **Pin as
app**. LinkDeck:

1. copies the running bundle from `Bundle.main.bundleURL` to
   `~/Applications/LinkDeck/<Name>.app` (appending ` 2`, ` 3`, … if the name is
   taken);
2. writes a unique `CFBundleIdentifier`, `CFBundleName`, and
   `CFBundleDisplayName` into the copy's `Info.plist`;
3. downloads the site favicon (or draws a deterministic letter tile), builds
   `icon_16x16` … `icon_512x512@2x` with `sips`, converts the iconset with
   `iconutil`, and installs it as `Contents/Resources/AppIcon.icns`;
4. writes `Contents/Resources/PinnedLink.json` with `{name, url}`;
5. ad-hoc signs the copy with `codesign --force --deep -s -`.

The alert after creation offers **Reveal in Finder**. Generated apps work when
LinkDeck itself is running from DerivedData or `build/` because the copy is
signed after its `Info.plist` is modified.

To remove a pinned app, quit it and move
`~/Applications/LinkDeck/<Name>.app` to the Trash. Removing a link from the deck
does **not** delete already-generated apps; the Settings sheet says so.

## Limitations

- **Blocked counts are honest but incomplete.** `WKContentRuleList` has no
  per-request statistics. The number shown on tiles and in the header counts
  cosmetic removals and popup blocks reported by `cosmetic.js`; network requests
  stopped by the rule list are not counted. The blocker itself still runs at the
  network layer.
- **DRM and some streaming players** may refuse to play in `WKWebView` (Widevine
  is unavailable; FairPlay support depends on the site). LinkDeck does not
  attempt DRM workarounds; use “Open in Safari” when a site requires it.
- **Favicons** are fetched from `icons.duckduckgo.com` with a cookie-free session.
  If the request fails, the deterministic letter tile is used. Favicon requests
  are the only network calls LinkDeck makes on its own.
- **Blocking relies on the host list.** A first-party ad served from the site's
  own domain will not match a suffix entry.
- Sites that require third-party cookies may still behave differently from a
  full browser; LinkDeck uses the default persistent `WKWebsiteDataStore`, so
  cookies and logins survive between launches.
- Pinned apps are snapshots of the LinkDeck bundle. Rebuild LinkDeck and pin
  again to pick up app updates; existing pinned apps are not updated
  automatically.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘N` | Add a link |
| `⌘R` | Reload the active app window |
| `⌘W` | Close the active window |
| `⌘,` | Settings |
| `Esc` | Close the add/settings sheet |

## Layout

```
apps/macos/
  project.yml           XcodeGen project definition
  build.sh              build + stage + ad-hoc sign
  Support/Info.plist    bundle metadata, ATS, category
  Resources/            blocklist.txt, cosmetic.js, AppIcon.icns
  LinkDeck/
    App/                entry point, app delegate, menu, self-test
    Models/             link model, deck storage, settings, URL input
    Services/           rule list, favicons, pinning, icon rendering
    Views/              deck, tiles, sheets, web app view + model
    Windows/            NSWindow controllers
```
