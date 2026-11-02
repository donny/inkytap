import Foundation

/// Native pixel codes of an E Ink Spectra 6 panel, as confirmed by the
/// Tapmora's E0 color-table record (low nibbles 0,1,2,3,5,6).
enum SpectraColor: UInt8, CaseIterable, Sendable {
    case black = 0
    case white = 1
    case yellow = 2
    case red = 3
    case blue = 5
    case green = 6

    var rgb: (UInt8, UInt8, UInt8) {
        switch self {
        case .black: (0x00, 0x00, 0x00)
        case .white: (0xFF, 0xFF, 0xFF)
        case .yellow: (0xFF, 0xD5, 0x00)
        case .red: (0xD0, 0x00, 0x00)
        case .blue: (0x00, 0x30, 0xC0)
        case .green: (0x00, 0x90, 0x30)
        }
    }

    var name: String {
        switch self {
        case .black: "Black"
        case .white: "White"
        case .yellow: "Yellow"
        case .red: "Red"
        case .blue: "Blue"
        case .green: "Green"
        }
    }
}

/// A palette-indexed image, row-major, one pixel code per byte.
struct PixelImage: Equatable, Sendable {
    var width: Int
    var height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, fill: SpectraColor = .white) {
        self.width = width
        self.height = height
        pixels = Array(repeating: fill.rawValue, count: width * height)
    }

    subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    mutating func fillRect(x: Int, y: Int, width w: Int, height h: Int, color: SpectraColor) {
        for yy in max(0, y)..<min(height, y + h) {
            for xx in max(0, x)..<min(width, x + w) {
                self[xx, yy] = color.rawValue
            }
        }
    }
}

/// How the Tapmora's framebuffer is laid out, as established by the test
/// patterns on 2026-11-01.
///
/// The chip's per-image size is 15200 bytes (A0: 400 × 304 bits). A refresh
/// needs 4 images (E0 header 0x46), and they are concatenated into one 60800-byte
/// 4-bit-per-pixel buffer: 304 native rows of 200 bytes (400 pixels). Each
/// native row is drawn as a vertical column of the upright 300 × 400 panel, so a
/// native row is a logical column and 4 of the 304 rows are padding.
struct PanelLayout: Equatable, Sendable {
    /// Native row 0 is the rightmost column instead of the leftmost.
    var mirrorColumns = false
    /// Pixel 0 of a native row is the bottom of the column instead of the top.
    var mirrorRows = false
    /// First pixel of a byte goes in the low nibble instead of the high one.
    var lowNibbleFirst = false
    /// Put the 4 padding rows before the image instead of after it.
    var padAtStart = false
    /// Pixel code used for padding rows.
    var paddingColor: SpectraColor = .white

    static let panelWidth = 300
    static let panelHeight = 400
    static let nativeRows = 304
    static let bytesPerNativeRow = panelHeight / 2  // 200
    static let imageBytes = 15_200
    static let imageCount = 4
    static let totalBytes = nativeRows * bytesPerNativeRow  // 60800

    var summary: String {
        var parts: [String] = []
        if mirrorColumns { parts.append("mirrorColumns") }
        if mirrorRows { parts.append("mirrorRows") }
        parts.append(lowNibbleFirst ? "lowNibbleFirst" : "highNibbleFirst")
        parts.append(padAtStart ? "padStart" : "padEnd")
        return parts.joined(separator: " ")
    }
}

enum Framebuffer {
    /// Packs an upright 300 × 400 palette image into the 60800-byte native buffer.
    static func pack(_ image: PixelImage, layout: PanelLayout) -> Data {
        precondition(image.width == PanelLayout.panelWidth && image.height == PanelLayout.panelHeight)
        let pad = layout.paddingColor.rawValue
        let padByte = (pad << 4) | pad
        var out = [UInt8](repeating: padByte, count: PanelLayout.totalBytes)
        let firstImageRow = layout.padAtStart ? PanelLayout.nativeRows - PanelLayout.panelWidth : 0

        for column in 0..<PanelLayout.panelWidth {
            let x = layout.mirrorColumns ? PanelLayout.panelWidth - 1 - column : column
            let base = (firstImageRow + column) * PanelLayout.bytesPerNativeRow
            for b in 0..<PanelLayout.bytesPerNativeRow {
                let i0 = b * 2
                let y0 = layout.mirrorRows ? PanelLayout.panelHeight - 1 - i0 : i0
                let y1 = layout.mirrorRows ? y0 - 1 : y0 + 1
                let p0 = image[x, y0] & 0x0F
                let p1 = image[x, y1] & 0x0F
                out[base + b] = layout.lowNibbleFirst ? (p1 << 4) | p0 : (p0 << 4) | p1
            }
        }
        return Data(out)
    }

    /// Splits the native buffer into the chip's fixed-size image slots.
    static func imageChunks(_ buffer: Data) -> [Data] {
        precondition(buffer.count == PanelLayout.totalBytes)
        return (0..<PanelLayout.imageCount).map { i in
            buffer.subdata(in: (i * PanelLayout.imageBytes)..<((i + 1) * PanelLayout.imageBytes))
        }
    }
}
