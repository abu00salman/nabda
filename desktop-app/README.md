# Nabda for Windows and macOS

An Electron shell around the live site (https://playnabda.com). It loads the deployed
game, so web updates reach desktop users without a new installer. The native layer adds
its own window and icon, a single running instance, and navigation that stays on
playnabda.com (other links open in the default browser). No permissions are granted.

## Build

Installers are built on GitHub's own runners, using `.github/workflows/desktop-build.yml`:

- **Windows**: `Nabda-<version>-x64.exe` (NSIS installer)
- **macOS**: `Nabda-<version>.dmg` and `.zip`

Open the Actions tab, pick "Build Nabda desktop apps", and download the artifacts.

Local builds (on the matching OS):

```bash
cd desktop-app
npm ci
npm start              # run the app
npm run dist:win       # Windows installer (run on Windows)
npm run dist:mac       # macOS disk image (run on macOS)
```

## Signing

The builds are unsigned, so the OS will warn on first launch:

- **Windows** SmartScreen: "More info" then "Run anyway".
- **macOS** Gatekeeper: right-click the app, choose Open, then confirm.

Removing these warnings requires a code-signing certificate (Windows) and an Apple
Developer ID with notarization (macOS). Both need paid accounts and secrets, so they
aren't wired up yet.
