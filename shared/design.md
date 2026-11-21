# LinkDeck — product & UI spec

**One-liner:** Your links, as apps. Save any site to a deck; open it full-screen with
no browser chrome, no ads, no popups.

**Targets:** Android · iOS · macOS · PWA (same product, native feel on each platform).

Not in scope: any site-specific integration, DRM/streaming workarounds, or account systems.
The apps are general-purpose launchers and do not ship with any preinstalled links.

---

## 1. Core behaviour

Each saved link is an **app** with: `id` (uuid), `name`, `url`, `addedAt`, `blocked`
(cumulative blocked requests). Data is stored locally only. No accounts, no sync, no analytics.

### URL entry
- Trim whitespace. If no scheme, prepend `https://`.
- Reject strings that are not a valid http(s) URL with a dot in the host.
- Suggested name: host without `www.`, with the TLD dropped and the first label capitalized
  (`www.arte.tv` → `Arte`). User can edit the name. Max 40 chars.
- Favicon: `https://icons.duckduckgo.com/ip3/<host>.ico` (no cookies/referrer), cached.
  Fallback: letter tile using the first alphanumeric character, white text on a deterministic
  gradient derived from the host hash. Never show a broken-image icon.

### Opening an app
Full-screen in-app web view. No URL bar, no browser chrome. A slim floating header appears
over the page and can be dismissed/recalled by tapping the top edge:

`‹ back` | `site.com` (with lock glyph) | `shield N` | `⋯ menu`

- Thin progress bar under the header while loading.
- Back stack: system back / back button goes back in history, closes the view at the root.
- Menu: Reload · Desktop site · Open in system browser · Pin as app (macOS) ·
  Remove from deck · (Android: Add to Home screen).
- Media: video fullscreen, autoplay allowed for muted media, playback keeps screen on,
  third-party cookies allowed (many embedded players need them) with a settings note.
- Links that would open a new window open in the same view instead.

### Ad & tracker blocking (all platforms, per-app toggle + global default)
- Host list: `shared/blocklist.txt`, one suffix-matched domain per line; `#` comments.
  A request is blocked when `host == entry` or `host` ends with `.<entry>`.
- Blocked requests return an empty response so pages degrade gracefully.
- Count blocked requests per session and add to the app's cumulative count. Show the count
  in the header shield and on the deck tile.
- Cosmetic pass: inject `shared/cosmetic.js` at document start in all frames (hides obvious
  ad slots, kills 1×1 tracker iframes, suppresses popups that were not triggered by a real tap).
- Never block the top-level navigation. If a user deliberately opens a blocked domain as an
  app, warn once but still let it load.
- Blocking must be a single toggle in Settings and one in the header (session override).

### Pinning an app (the "link → app" part)
- **Android:** `ShortcutManagerCompat.requestPinShortcut` → real launcher icon (favicon bitmap
  or letter tile) that boots straight into that site, no deck. Also expose it from the tile menu.
- **macOS:** create a real `.app` in `~/Applications/LinkDeck/<Name>.app` with the favicon as its
  icon. Relaunching that bundle opens that site directly, in its own Dock presence.
  Implementation: duplicate the LinkDeck bundle, set `Info.plist` id/name/icon, add
  `Contents/Resources/PinnedLink.json`; LinkDeck checks for that file at launch.
- **iOS:** apps cannot add home-screen web clips programmatically. Use the in-app deck as the
  home screen, and provide a "Add to Home Screen" tip that opens the site in Safari with
  short instructions. Be honest about this in the UI.
- **PWA:** each app can be launched from its own start URL (`?app=<id>`) and the PWA manifest
  plus "Add to Home Screen"/"Add to Dock" gives an app-like window. Also support opening
  individual saved links in a standalone window via the browser when available.

---

## 2. Visual language

Dark, calm, one accent. No drop-shadow noise, no gradients except the icon and tile art.

| Token | Value |
| --- | --- |
| `bg` | `#0B0D10` |
| `surface` | `#14171C` |
| `surface-2` | `#1C2027` |
| `stroke` | `#272D36` |
| `text` | `#F2F5F7` |
| `muted` | `#98A2B3` |
| `muted-2` | `#6B7482` |
| `accent` | `#7C6BFF` |
| `accent-2` | `#A78BFA` |
| `success` (shield / blocked) | `#34D399` |
| `danger` | `#F87171` |

- Type: platform system font (SF Pro / Roboto). Deck title 30–34 semibold, tile name 15
  semibold, host 12 regular muted, body 15, labels 12 uppercase muted-2 with letter-spacing.
- Deck layout: header (title + subtitle, settings button) then an adaptive grid of tiles,
  min tile 150 pt/dp, 12 pt gap, 20 pt corners, 20 pt screen margins. Generous top padding.
- Tile: surface fill, 1 px stroke; 44 pt icon rounded 12 (favicon) or letter tile; name,
  host, and a small shield pill with the blocked count (muted, only when > 0).
  Tap = open. Long-press / right-click = context menu (Open, Pin/Add to Home screen, Rename, Remove).
- Empty state: centered icon, "Nothing here yet", one line of copy, primary button.
- Add sheet: URL field (auto-focused, keyboard type URL, no autocapitalize), name field,
  primary "Add to deck" button; validation inline.
- Settings sheet: blocking toggle, popup toggle, clear data, version, short "how it works".
- Motion: 150–200 ms ease-out; tiles fade+rise 8 pt on first appearance. Resist bounce effects.
- Accessibility: 44 pt targets, labels on icon-only buttons, dynamic type, no color-only meaning.

Copy:
- Deck subtitle: `3 links · 1,284 blocked` (singular/plural correct).
- Empty: title `Nothing here yet`; body `Paste a link and it becomes an app on your deck — no
  browser chrome, no ads.`; action `Add a link`.
- Add sheet title: `Add a link`; subtitle `Anything with a web address works.`
- Settings: `Settings`; sections `Blocking`, `Data`, `About`.
- Browser menu: `Reload`, `Desktop site`, `Open in Safari`/`Open in browser`,
  `Add to Home screen` (Android), `Pin as app` (macOS), `Remove from deck`.

---

## 3. Platform notes

| | Android | iOS | macOS | PWA |
| --- | --- | --- | --- | --- |
| Stack | Kotlin, Views + Material 3 | SwiftUI + WKWebView | SwiftUI/AppKit + WKWebView | Vanilla JS/CSS |
| Blocking | `shouldInterceptRequest` | `WKContentRuleList` | `WKContentRuleList` | not possible (state this clearly) |
| Pin | launcher shortcut | Safari tip | generated `.app` | manifest + start URL |
| Persist | SharedPreferences JSON | JSON in Application Support | JSON in Application Support | localStorage |

Every platform must ship with **no preinstalled links** and an honest note about what the
platform can and cannot do (especially PWA ad blocking and iOS home-screen pinning).

## 4. Shared files

```
shared/blocklist.txt     6,603 suffix-matched domains (AdAway + curated networks)
shared/cosmetic.js       injected cosmetic filter + popup guard
shared/icon/             all generated icons (PNG, .icns, Android mipmaps)
```
