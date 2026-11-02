import CoreGraphics
import Foundation
import UIKit

enum TestPattern: String, CaseIterable, Identifiable, Sendable {
    case colorBars = "Color bars + corner marks"
    case quadrants = "Quadrants"
    case solidWhite = "Solid white"
    case solidBlack = "Solid black"

    var id: String { rawValue }

    static let panelWidth = PanelLayout.panelWidth
    static let panelHeight = PanelLayout.panelHeight

    func render() -> PixelImage {
        var image = PixelImage(width: Self.panelWidth, height: Self.panelHeight, fill: .white)
        switch self {
        case .colorBars:
            // Six vertical bars, left to right: white, black, yellow, red, blue, green.
            let order: [SpectraColor] = [.white, .black, .yellow, .red, .blue, .green]
            let barWidth = image.width / order.count
            for (i, color) in order.enumerated() {
                image.fillRect(x: i * barWidth, y: 0, width: barWidth, height: image.height, color: color)
            }
            // Black square top-left (on the white bar), white square bottom-right (on the green bar).
            image.fillRect(x: 8, y: 8, width: 34, height: 34, color: .black)
            image.fillRect(x: image.width - 42, y: image.height - 42, width: 34, height: 34, color: .white)
            // A thin red line along the top edge and a thin blue line along the left edge.
            image.fillRect(x: 0, y: 0, width: image.width, height: 4, color: .red)
            image.fillRect(x: 0, y: 0, width: 4, height: image.height, color: .blue)
        case .quadrants:
            let w = image.width / 2, h = image.height / 2
            image.fillRect(x: 0, y: 0, width: w, height: h, color: .red)
            image.fillRect(x: w, y: 0, width: w, height: h, color: .yellow)
            image.fillRect(x: 0, y: h, width: w, height: h, color: .blue)
            image.fillRect(x: w, y: h, width: w, height: h, color: .green)
            image.fillRect(x: w - 30, y: h - 30, width: 60, height: 60, color: .black)
        case .solidWhite:
            break
        case .solidBlack:
            image.fillRect(x: 0, y: 0, width: image.width, height: image.height, color: .black)
        }
        return image
    }
}

extension PixelImage {
    /// Renders the palette image to a UIImage for previewing.
    func uiImage() -> UIImage? {
        var rgba = [UInt8](repeating: 0xFF, count: width * height * 4)
        for i in 0..<(width * height) {
            let (r, g, b) = SpectraColor(rawValue: pixels[i])?.previewRGB ?? (0xFF, 0x00, 0xFF)
            rgba[i * 4] = r
            rgba[i * 4 + 1] = g
            rgba[i * 4 + 2] = b
        }
        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
              ) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
