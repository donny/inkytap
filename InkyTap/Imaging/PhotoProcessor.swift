import CoreGraphics
import Foundation
import UIKit

/// Turns an arbitrary photo into a 300 × 400 six-color PixelImage.
enum PhotoProcessor {
    struct Settings: Equatable, Sendable {
        /// Floyd–Steinberg error diffusion; otherwise nearest color only.
        var dither = true
        /// Multiplier on chroma before quantizing. Spectra 6 benefits from a boost.
        var saturation: Double = 1.3
        /// Multiplier around mid-gray.
        var contrast: Double = 1.1
        /// Added to every channel, in 0...1 units.
        var brightness: Double = 0.0
        /// Rotate the photo 90° so landscape shots fill the portrait panel.
        var rotateLandscape = true
    }

    /// Approximate sRGB appearance of each Spectra 6 primary, used for both
    /// quantization and preview. Tuned towards how the panel actually looks.
    static let palette: [(color: SpectraColor, r: Double, g: Double, b: Double)] = [
        (.black, 0.08, 0.08, 0.08),
        (.white, 0.92, 0.92, 0.90),
        (.yellow, 0.95, 0.80, 0.10),
        (.red, 0.72, 0.16, 0.14),
        (.blue, 0.14, 0.30, 0.65),
        (.green, 0.22, 0.47, 0.30),
    ]

    /// Decodes `data`, aspect-fills it into the panel size, and quantizes.
    static func process(imageData: Data, settings: Settings) -> PixelImage? {
        guard let source = UIImage(data: imageData) else { return nil }
        let rgb = aspectFillRGB(source, settings: settings)
        return quantize(rgb: rgb, settings: settings)
    }

    /// Draws the photo into a 300 × 400 RGB float buffer, rotating landscape input if asked.
    static func aspectFillRGB(_ image: UIImage, settings: Settings) -> [Double] {
        let width = PanelLayout.panelWidth
        let height = PanelLayout.panelHeight

        var image = image
        if settings.rotateLandscape, image.size.width > image.size.height, let rotated = image.rotated90() {
            image = rotated
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        let drawn = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let scale = max(CGFloat(width) / image.size.width, CGFloat(height) / image.size.height)
            let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let origin = CGPoint(x: (CGFloat(width) - drawSize.width) / 2, y: (CGFloat(height) - drawSize.height) / 2)
            image.draw(in: CGRect(origin: origin, size: drawSize))
        }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        guard let cg = drawn.cgImage,
              let context = CGContext(
                data: &rgba, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return [Double](repeating: 1, count: width * height * 3) }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var out = [Double](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            for c in 0..<3 {
                out[i * 3 + c] = Double(rgba[i * 4 + c]) / 255
            }
        }
        return out
    }

    /// Applies the tone settings and quantizes to the palette with optional dithering.
    static func quantize(rgb input: [Double], settings: Settings) -> PixelImage {
        let width = PanelLayout.panelWidth
        let height = PanelLayout.panelHeight
        var rgb = input

        // Tone adjustments.
        for i in 0..<(width * height) {
            var r = rgb[i * 3], g = rgb[i * 3 + 1], b = rgb[i * 3 + 2]
            let luma = 0.299 * r + 0.587 * g + 0.114 * b
            r = luma + (r - luma) * settings.saturation
            g = luma + (g - luma) * settings.saturation
            b = luma + (b - luma) * settings.saturation
            r = (r - 0.5) * settings.contrast + 0.5 + settings.brightness
            g = (g - 0.5) * settings.contrast + 0.5 + settings.brightness
            b = (b - 0.5) * settings.contrast + 0.5 + settings.brightness
            rgb[i * 3] = r
            rgb[i * 3 + 1] = g
            rgb[i * 3 + 2] = b
        }

        var result = PixelImage(width: width, height: height)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 3
                let r = min(max(rgb[i], 0), 1)
                let g = min(max(rgb[i + 1], 0), 1)
                let b = min(max(rgb[i + 2], 0), 1)

                var best = 0
                var bestDistance = Double.infinity
                for (index, entry) in palette.enumerated() {
                    let dr = r - entry.r, dg = g - entry.g, db = b - entry.b
                    // Weighted so luminance errors matter more than hue errors.
                    let distance = 0.3 * dr * dr + 0.59 * dg * dg + 0.11 * db * db
                    if distance < bestDistance {
                        bestDistance = distance
                        best = index
                    }
                }
                let chosen = palette[best]
                result[x, y] = chosen.color.rawValue

                guard settings.dither else { continue }
                let er = r - chosen.r, eg = g - chosen.g, eb = b - chosen.b
                func spread(_ dx: Int, _ dy: Int, _ weight: Double) {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, nx < width, ny < height else { return }
                    let j = (ny * width + nx) * 3
                    rgb[j] += er * weight
                    rgb[j + 1] += eg * weight
                    rgb[j + 2] += eb * weight
                }
                spread(1, 0, 7.0 / 16)
                spread(-1, 1, 3.0 / 16)
                spread(0, 1, 5.0 / 16)
                spread(1, 1, 1.0 / 16)
            }
        }
        return result
    }
}

extension UIImage {
    /// Returns the image rotated 90° clockwise, baking in any EXIF orientation.
    func rotated90() -> UIImage? {
        let newSize = CGSize(width: size.height, height: size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { context in
            context.cgContext.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.cgContext.rotate(by: .pi / 2)
            draw(in: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
        }
    }
}

extension SpectraColor {
    /// Preview color matching the quantization palette.
    var previewRGB: (UInt8, UInt8, UInt8) {
        let entry = PhotoProcessor.palette.first { $0.color == self }!
        return (UInt8(entry.r * 255), UInt8(entry.g * 255), UInt8(entry.b * 255))
    }
}
