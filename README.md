# InkyTap

An account-free iOS app for sending photos to battery-free NFC e-paper
displays, such as the Tapmora 4-inch Spectra 6 photo magnet and other displays
built on Good Display's FM1280 NFC module. Hold the phone to the display,
and the image is uploaded and refreshed over NFC. No sign-up, no server.

Built with SwiftUI for iOS 26+. The protocol is documented in
[`docs/nfc-protocol-notes.md`](docs/nfc-protocol-notes.md).

## Building

The Xcode project is generated from `project.yml` with
[xcodegen](https://github.com/yonaskolb/XcodeGen), so `InkyTap.xcodeproj` is
not committed.

```sh
make project   # regenerate InkyTap.xcodeproj
make sim       # run on the iPhone 17 simulator
make device    # build + install + launch on a USB-connected iPhone
make open      # open in Xcode
```

Core NFC only works on a physical iPhone. Set your own team and bundle ID in
`project.yml` before deploying.

## Status

- Verified on a Tapmora 4-inch Spectra 6 (300x400, six colors).
- Other display sizes and color modes reported by the device are not yet
  supported.

## Disclaimer

InkyTap is an independent project. It is not affiliated with, endorsed by, or
supported by Tapmora, Good Display (Guangdong SID Technology), Fudan
Microelectronics, E Ink, or the makers of the Einky app. Product names are
used only to describe compatibility and remain the property of their owners.

The protocol was implemented from the publicly published FM1280 developer
manual and existing open-source projects, for interoperability. Nothing from
the Einky app was copied or decompiled.

Use at your own risk. Writing to a display with an unsupported configuration
may leave it showing garbage until the next successful upload.

## License

MIT, see [LICENSE](LICENSE). Third-party code is listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
