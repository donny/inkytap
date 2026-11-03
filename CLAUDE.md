# InkyTap

SwiftUI iOS app (iOS 26+, Swift 6 strict concurrency). Project file is generated: edit `project.yml`, never `InkyTap.xcodeproj` (gitignored).

- `make project` regenerates the Xcode project (run after adding/removing files or changing `project.yml`).
- `make sim` builds and launches on the iPhone 17 simulator.
- `make device` builds, installs and launches on a USB-connected iPhone via `scripts/deploy-device.sh` (uses `xcrun devicectl`).
- Bundle ID `io.github.donny.inkytap`, automatic signing. The Apple team ID lives in the gitignored `Signing.xcconfig` (copy from `Signing.xcconfig.example`); never commit it or put it in `project.yml`.
- This repo is the developer/lab version. The App Store app lives in a separate private repo; keep store-specific identifiers (its bundle ID, team, org name) out of here.
- Build output goes to `build/DerivedData` (gitignored).
- `scripts/screenshots.sh` regenerates `docs/screenshots/*.png` on the simulator via the debug-only `INKYTAP_SCREEN` env var (see `InkyTap/Probe/DemoData.swift`).
