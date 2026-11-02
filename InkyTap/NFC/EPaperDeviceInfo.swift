import Foundation

/// Decoded view of the Get Config Info (D1) response.
///
/// Field meanings combine the vendor manual (section 7.4) with what the
/// community found on 2- and 4-color units. Anything marked "guess" is
/// unverified for the Spectra 6 panel; the probe exists to settle it.
struct EPaperDeviceInfo: Sendable, Equatable {
    var tlvs: [TLV]

    // A0: panel description
    var manufacturer: UInt8?
    var sizeCode: UInt8?
    var colorCode: UInt8?
    var x: Int?
    var y: Int?

    // A1: scan / orientation
    var scanMode: UInt8?

    var imageCapacity: Int?
    var userDataKB: Int?
    var batteryPowered: Bool?
    var name: String?
    var uid: UInt32?
    var compressionSupported: Bool?
    var firmwareVersion: UInt8?

    init(payload: Data) {
        tlvs = payload.parseTLV()
        for tlv in tlvs {
            let v = tlv.value
            switch tlv.tag {
            case 0xA0 where v.count >= 7:
                manufacturer = v[v.startIndex]
                sizeCode = v[v.startIndex + 1]
                colorCode = v[v.startIndex + 2]
                x = Int(v[v.startIndex + 3]) << 8 | Int(v[v.startIndex + 4])
                y = Int(v[v.startIndex + 5]) << 8 | Int(v[v.startIndex + 6])
            case 0xA1 where v.count >= 1:
                scanMode = v[v.startIndex]
            case 0xB1 where v.count >= 1:
                imageCapacity = Int(v[v.startIndex])
            case 0xB2 where v.count >= 1:
                userDataKB = Int(v[v.startIndex])
            case 0xB3 where v.count >= 1:
                batteryPowered = v[v.startIndex] == 1
            case 0xC0:
                name = String(data: v, encoding: .ascii)?
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\0 "))
            case 0xC1 where v.count == 4:
                uid = v.reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
            case 0xD1 where v.count >= 2:
                compressionSupported = v[v.startIndex] == 1
                firmwareVersion = v[v.startIndex + 1]
            default:
                break
            }
        }
    }

    /// Human-readable interpretation of the A0 record, with the candidate
    /// bit depths implied by the X/Y pair for a 600x400 (or 400x600) panel.
    var panelNotes: [String] {
        var notes: [String] = []
        if let manufacturer {
            notes.append(manufacturer == 0xF0
                ? "Manufacturer F0 = custom driver flow (expected for color panels)"
                : String(format: "Manufacturer code %02X", manufacturer))
        }
        if let colorCode {
            let known: [UInt8: String] = [0x20: "black/white", 0x30: "black/white/red", 0x31: "black/white/yellow"]
            notes.append(String(format: "Color code %02X", colorCode) + (known[colorCode].map { " = \($0)" } ?? " (not in manual)"))
        }
        if let x, let y {
            notes.append("A0 X×Y = \(x)×\(y)")
            for (w, h) in [(600, 400), (400, 600)] {
                if x == w, y % h == 0 { notes.append("If width=\(w): height \(h) × \(y / h) bpp") }
                if y == w, x % h == 0 { notes.append("If width=\(w) (swapped): height \(h) × \(x / h) bpp") }
            }
        }
        if let scanMode {
            notes.append(String(format: "A1 scan mode %02X ", scanMode) + (scanMode == 0x01 ? "(horizontal/normal)" : scanMode == 0x00 ? "(vertical/rotated)" : "(unknown)"))
        }
        return notes
    }
}
