# PlayNabda for Android

A native Android shell around the real, deployed Nabda web app
(https://playnabda.com) — not a generic WebView wrapper with no thought behind it.
See `MainActivity.kt` for the full implementation; this file explains *why* it's
built the way it is, how to build it, and what to check before you ship it.

## Before you build: this project was written, not tested, here

This was written entirely from a cloud sandbox with **no Android SDK available**
(network policy blocks `dl.google.com`, the only source for Android
platform/build-tools). That means:

- Nothing here has been compiled. `./gradlew assembleDebug` has never actually been
  run against this code.
- Nothing has been tested on any device, emulator, or Android Studio instance. No
  cloud sandbox has physical hardware attached, so that step was always going to fall
  to you regardless of the SDK issue.

Every file was written carefully and reviewed by hand against the real Nabda web
source (`index.html`) — see "Architecture" below for what was actually investigated —
but "carefully hand-reviewed" is not "compiled and run." **Open this in Android
Studio, let it sync, and fix whatever it flags before trusting any of it.** If
something doesn't compile, that's expected to be possible, not a sign you did
something wrong.

## Quickstart

```bash
cd android-app
./gradlew assembleDebug
# APK: app/build/outputs/apk/debug/app-debug.apk
```

Open the `android-app/` folder directly in Android Studio (not the repo root — this
is a separate Gradle project, deliberately not nested inside the website's own build)
and it should sync on its own. Android Studio may offer to upgrade the Android
Gradle Plugin, Gradle, or Kotlin — that's normal and fine to accept; the versions
pinned in `gradle/libs.versions.toml` are a known-good floor as of when this was
written, not a ceiling.

## Architecture: why this isn't "bundle index.html into the APK"

The obvious-looking approach — copy `index.html`/`sw.js`/etc. into
`app/src/main/assets` and serve it locally — was deliberately **not** taken. Nabda
already ships a service worker (`sw.js`) that precaches the page shell and static
assets, giving it a complete, already-working, already-tested offline story on the
web. Bundling a second copy of the same assets into the APK would mean:

- Two copies of the game to keep in sync (the live site and whatever snapshot got
  baked into the last Android build) — the app would silently serve a stale build
  until someone remembered to rebuild and re-publish the APK, independent of web
  deploys to playnabda.com.
- The leaderboard (`worker.js` on Cloudflare) is already a separate network service
  either way — bundling the page doesn't make the game work offline end-to-end, it
  only risks the *shell* going stale.

So `MainActivity` just points the WebView at `https://playnabda.com/`
(`BuildConfig.BASE_URL`) and lets the *existing* service worker do exactly what it
already does in a browser tab. First launch needs network; every launch after that
loads the cached shell instantly, same as the PWA already does.

## What's native vs. what's already in the web app

Before writing any native code, the actual Nabda source (`index.html`) was read end
to end. Most of what a game shell needs **already exists in the web app** and needed
zero native reimplementation:

- Touch input, the whole accuracy-zone hit detection, difficulty curve, combo
  scoring, pause/resume, themes, day/night mode, leaderboard, nickname — all in
  `index.html`'s single `<script type="module">`.
- Haptic feedback via `navigator.vibrate` (`HapticManager` in `index.html`) — Chromium
  WebView implements this the same as desktop/mobile Chrome; the only native piece
  needed is the `VIBRATE` permission in the manifest, since without it every call is
  silently a no-op.
- `touch-action: manipulation`, `user-select: none`, `overscroll-behavior: none`,
  double-tap/context-menu prevention — already wired globally in `index.html`'s CSS
  and JS. No scrolling/zooming/text-selection fights to solve natively.
- `100dvh` + `env(safe-area-inset-*)` — already wired through the CSS; edge-to-edge
  native layout (`WindowCompat.setDecorFitsSystemWindows(window, false)`) is all
  that's needed for insets/cutouts to resolve correctly on the web side.
- Offline caching of the shell — `sw.js`.

What's actually native, and why each exists:

| Native piece | Why it can't be the web app's job |
|---|---|
| Hardware-accelerated, locked-down `WebView` config (`configureWebView()`) | `WebSettings`, layer type, mixed-content policy — Android-only API |
| `VIBRATE` permission | Without it, the page's own `navigator.vibrate` calls are silent no-ops |
| Back button pauses an active round instead of exiting | Reuses the page's *existing* `'p'`-key pause toggle via a synthetic keydown — no new pause code path on the web side, just a one-way `evaluateJavascript` read of `window.__nabdaDebug.S` to decide whether a round is running |
| Splash screen | Android 12+ SplashScreen API, released as soon as the first page paints |
| Native error screen | Only for a failure *before* the page ever loaded — e.g. no network on first-ever launch; nothing in `index.html` renders its own offline screen |
| App icon | Redrawn from `icon.svg` as Android adaptive-icon vector drawables (`ic_launcher_foreground.xml`/`ic_launcher_background.xml`) — same ring/arc/dot mark, scaled to fit the adaptive-icon safe zone so OEM launcher masks (circle, squircle, rounded square) don't clip it |

There is **no `@JavascriptInterface` bridge** (contrast with a game that needs one for
file import, blob downloads, etc.) — Nabda's page never needs to call into native
code. The only native↔web communication is the one-way Back-button state read
described above, which changes nothing about how the page behaves on its own.

## Signing

Release builds fall back to the **debug keystore** until you provide a real one, so
`./gradlew assembleRelease` / `bundleRelease` work out of the box without any extra
setup — the resulting APK/AAB just isn't signed for Play Store distribution yet.

To add real signing (needed before Play Store upload, not needed for "install this
APK directly on my phone"):

```bash
keytool -genkeypair -v -keystore playnabda-release.keystore -alias playnabda \
  -keyalg RSA -keysize 2048 -validity 10000
```

Then create `android-app/keystore.properties` (gitignored — never commit it):

```properties
storeFile=../playnabda-release.keystore
storePassword=...
keyAlias=playnabda
keyPassword=...
```

`app/build.gradle.kts` picks this up automatically if the file exists.

## Debugging against a local server instead of production

Debug builds point at `BuildConfig.BASE_URL = "https://playnabda.com/"` by default
(there's no staging server). To point a debug build at a local static server instead:

1. Run e.g. `python3 -m http.server 8080` from the repo root (where `index.html`
   lives).
2. Edit the `debug` block's `buildConfigField("String", "BASE_URL", ...)` in
   `app/build.gradle.kts` to `"http://10.0.2.2:8080/"` (emulator) or your machine's
   LAN IP (physical device).
3. `app/src/debug/res/xml/network_security_config.xml` already permits cleartext for
   `10.0.2.2`/`localhost`/`127.0.0.1` *only in debug builds* — release stays
   HTTPS-only, enforced by `app/src/main/res/xml/network_security_config.xml` +
   `usesCleartextTraffic="false"`.

## Minimum SDK: 26 (Android 8.0)

Chosen deliberately, not as a default: it's the API level adaptive icons shipped in,
so there's no legacy raster-mipmap fallback to maintain (`mipmap-anydpi-v26/` is the
only icon resource needed). Covers the overwhelming majority of active devices.

## What to actually test once it builds

Launch → confirm splash shows the Nabda mark and the real page loads → play through
the first-time tutorial → play a full round and confirm haptics fire on
PERFECT/GREAT/GOOD/MISS → rotate to landscape and back (must not reload the page or
lose game state — `android:configChanges` on `MainActivity` is what prevents that) →
background the app mid-round and return (round should still be there, not reset) →
press Back while a round is running (should pause, not exit) → press Back on the
home screen / with an overlay open (should behave like a normal browser-tab Back,
i.e. exit since there's no history to go back to) → submit a score to the
leaderboard and confirm it appears → toggle dark/light mode and the 6 color themes
in Settings → turn off mobile data before first-ever launch and confirm the native
error screen (not a blank WebView) appears, then confirm a real device after one
successful load still opens offline → confirm no white screen on any of the above →
and, at the end, all of it again on a real phone. None of this has been exercised
once — this list is where to start, not a checklist of things already confirmed
working.
