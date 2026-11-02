# Tapmora / NFC e-paper protocol notes

Research gathered 2026-11-01. Sources at the bottom.

## What the Tapmora is

- Battery-free 4-inch E Ink Spectra 6 photo magnet, 600x400 px (E Ink EL040EF1 / GoodDisplay GDEP040E01 panel).
- Powered and updated over NFC. The official app is **Einky** (iOS id6762123207, Android package `cn.gdsid.inky`).
  "GDSID" = Guangdong SID Technology = Good Display (GooDisplay). Tapmora is a rebrand of a Good Display NFC module.
- NFC controller: Fudan Microelectronics **FM1280** ("FMSC" ESL chip). ISO 14443-A + ISO 7816 APDUs. AID `D2760000850101`.
- The chip is a dumb bridge: the phone uploads a framebuffer, the chip replays a stored "driver flow" (SPI init
  sequence) to the panel and pushes the framebuffer into panel RAM. Firmware needs no changes from us.

## Command set (verified on 2-color and 4-color siblings by three independent projects)

| Step | APDU | Notes |
|---|---|---|
| Verify PIN | `00 20 00 01 04 20 09 12 10` | Default PIN `20091210`. Expect `9000`. |
| Get config | `00 D1 00 00 00` | TLV reply. `A0` = [flags, colorMode, rowsPerBlock, heightRaw(2, BE), width(2, BE)]; heightRaw = height x bpp. `A1[0]` = scan/orientation. `C0` = 10-char name. `C1` = UID. `D1` = [compressionSupported, version, ...]. |
| Upload | `F0 D3 00 P2 Lc blk frag data...` | Framebuffer split into 2000-byte blocks, each LZO1X-1 compressed, each compressed block split into 250-byte fragments. P2 = 1 on the last fragment of a block. |
| Upload (raw) | `F0 D2 idx pkt Lc data...` | Uncompressed alternative, 250-byte packets. |
| Refresh | `F0 D4 85 00 00` | P2 bit7 = 0 blocks until the panel is done (use this on iOS: Core NFC drops the session 20 s after connect, but a pending APDU keeps it alive). P2 = `80` returns immediately. |
| Poll | `F0 DE 00 00 01` | Reply `00` done, `01` busy. |

Known colorMode values: `0x01` 2-color 1bpp, `0x47` 2-color 1bpp (4.2"), `0x07` 4-color 2bpp (B/W/Y/R = 0,1,2,3).

Pixel packing (from the 2/4-color implementations): rows top to bottom; within a row the bytes are stored right-to-left,
pixel index 0 of each byte in the low bits. Some panels need 90-degree rotation or a horizontal flip; `A1[0]` hints at it.

## Probe results from the Tapmora (2026-11-01)

```
A0 (7): F0 07 60 0190 0130   manufacturer F0 (custom driver flow), size code 07, color code 60, X=400, Y=304
A1 (7): 00 FFFFFFFFFFFF      scan mode 00
B1 (1): 10                   image capacity 16
B2 (1): 14                   user data 20 KB
B3 (1): 00                   NFC powered
C0 (4): 201EA001             APPID
C1 (4): 9E25C71D             UID (also the ISO 14443 UID)
D1 (7): 01 20 00...          LZO supported, firmware 0x20
E0 (14): 46E0 0080 0181 0283 0382 0586 0785
```

- `00 20` VERIFY PIN returns 6D00 (not supported): no PIN on this firmware.
- `00 D5` image SN returns 00. `00 EB` and `00 DC` are not supported. `F0 DE` returned 01 before any refresh.
- E0 reads as a color table: header 0x46 = 4 bpp, 6 colors; pairs map host color type → panel code (low nibble):
  black 0, white 1, red 3, yellow 2, green 6, blue 5. These are the Spectra 6 native codes.
- 400 × 304 = 121600 bytes = 600×400 px at 4 bpp (120000) plus 4 bytes per row of padding (304 = 300 rounded up to 16).
  Working hypothesis: 400 rows of 304 bytes, 2 px per byte. Orientation, nibble order and padding position
  are exposed as toggles in the Test Pattern screen.

## Confirmed Tapmora framebuffer format (2026-11-01, verified with test patterns)

- Panel is **300 × 400 upright** (portrait), Spectra 6, 4 bits per pixel, codes 0 black, 1 white, 2 yellow, 3 red, 5 blue, 6 green.
  Undefined codes such as 0xF render as a green-gray.
- The chip's image slot is 15200 bytes (A0 400 × 304 bits ÷ 8). A refresh uses **4 slots** (E0 header 0x46 = 4 images, 6 colors),
  concatenated into one 60800-byte buffer = **304 native rows × 200 bytes (400 px)**.
- **Each native row is one column of the upright panel**, native row 0 = leftmost column, pixel 0 = top, first pixel in the
  high nibble. Rows 300–303 are padding (placed after the image; white works).
- Upload: for slot i in 0..<4, `F0 D3 i P2 Lc blk frag data` with the slot's 15200 bytes in 2000-byte LZO1X-1 blocks
  (last block 1200 bytes; the chip verifies the decompressed length, status 6993 otherwise) and 250-byte fragments.
- Refresh: `F0 D4 85 00 00` (blocking). Returns 9000 after ~17.6 s on iPhone 16 Pro. `F0 DE` then reports 01.
- No PIN (VERIFY returns 6D00). Whole upload of a test pattern takes ~1 s; a dithered photo will be larger.

Dead ends, for the record: a 600×400 panel, a single 4-bpp image of 121600 bytes (6993 on block 7), and four 1-bit planes
(uploads fine but renders as stripes because the chip concatenates slots rather than composing bits).

## iOS requirements

- Entitlement `com.apple.developer.nfc.readersession.formats` = [`TAG`] (App ID needs "NFC Tag Reading").
- Info.plist `com.apple.developer.nfc.readersession.iso7816.select-identifiers` = [`D2760000850101`], plus `NFCReaderUsageDescription`.
- Core NFC `NFCTagReaderSession` with `.iso14443`, then `NFCISO7816Tag.sendCommand`.

## Sources

- Protocol write-up (Yoshimasa Niwa): https://gist.github.com/niw/3885b22d502bb1e145984d41568f202d
- Swift implementation, MIT: https://github.com/niw/EPaperNFCSwift
- Python implementation + device table: https://github.com/alt-core/nfc-eink
- Python driver for the 4-color badge, includes driver-flow notes: https://github.com/CompassSecurity/nfcink
- Official FM1280 manual (older, covers 1-bit/3-color screens only): https://www.good-display.com/companyfile/1835.html
- Tapmora product page: https://tapmora.net/products/battery-free-e-ink-photo-magnet
- Panel datasheet: https://www.eink.com/product/detail/EL040EF1
