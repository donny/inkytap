# InkyTap

SwiftUI iOS app (iOS 26+, Swift 6 strict concurrency). Project file is generated: edit `project.yml`, never `InkyTap.xcodeproj` (gitignored).

- `make project` regenerates the Xcode project (run after adding/removing files or changing `project.yml`).
- `make sim` builds and launches on the iPhone 17 simulator.
- `make device` builds, installs and launches on a USB-connected iPhone via `scripts/deploy-device.sh` (uses `xcrun devicectl`).
- Bundle ID `io.github.donny.inkytap`, team `YOURTEAMID`, automatic signing.
- Build output goes to `build/DerivedData` (gitignored).
