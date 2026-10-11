# Nabda for iPhone

A SwiftUI app with one `WKWebView` that loads the live site (https://playnabda.com).
It follows the same design as the Android and desktop shells: web updates reach
players without an App Store release. The native layer adds the app icon, a dark
launch screen, navigation that stays on playnabda.com, and an Arabic retry screen when
the first load fails.

## Layout

- `project.yml`: the XcodeGen spec. The `.xcodeproj` is generated from it, not stored.
- `Nabda/NabdaApp.swift`: app entry point.
- `Nabda/ContentView.swift`: the web view, navigation rules, and offline screen.
- `Nabda/Assets.xcassets`: app icon (opaque, as App Store requires) and launch colour.

## Build

Requires macOS with Xcode 15 or newer.

```bash
brew install xcodegen
cd ios-app
xcodegen generate
open Nabda.xcodeproj
```

Pick an iPhone simulator and press Run. CI compiles it on every push that touches
`ios-app/` (`.github/workflows/ios-build.yml`).

## Getting it onto a real iPhone

This needs an Apple Developer account (paid, US$99 per year) and signing:

1. In `project.yml`, set `DEVELOPMENT_TEAM` to your Team ID.
2. In Xcode, use Product > Archive, then Distribute App > App Store Connect.
3. Install through TestFlight, or submit for App Store review.

Nothing in this repo contains signing certificates or Apple credentials.
