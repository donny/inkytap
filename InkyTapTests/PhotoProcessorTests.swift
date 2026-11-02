import Foundation
import Testing
import UIKit
@testable import InkyTap

struct PhotoProcessorTests {
    /// A landscape gradient with strongly colored quadrants.
    private func syntheticPhoto() -> Data {
        let size = CGSize(width: 800, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let colors: [UIColor] = [.red, .green, .blue, .yellow]
            for (i, color) in colors.enumerated() {
                color.setFill()
                let x = CGFloat(i % 2) * 400, y = CGFloat(i / 2) * 300
                context.fill(CGRect(x: x, y: y, width: 400, height: 300))
            }
            UIColor.black.setFill()
            context.fill(CGRect(x: 300, y: 200, width: 200, height: 200))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 150, height: 150))
        }
        return image.pngData()!
    }

    @Test func producesPanelSizedImageWithAllColors() {
        let image = PhotoProcessor.process(imageData: syntheticPhoto(), settings: .init())
        #expect(image != nil)
        guard let image else { return }
        #expect(image.width == 300 && image.height == 400)
        let used = Set(image.pixels)
        for color in SpectraColor.allCases {
            #expect(used.contains(color.rawValue), "missing \(color.name)")
        }
        #expect(used.isSubset(of: Set(SpectraColor.allCases.map(\.rawValue))))
    }

    @Test func nearestColorWithoutDither() {
        var settings = PhotoProcessor.Settings()
        settings.dither = false
        settings.saturation = 1
        settings.contrast = 1
        let image = PhotoProcessor.process(imageData: syntheticPhoto(), settings: settings)!
        // Rotated landscape: the original top-left white square ends up top-right.
        #expect(image[299, 0] == SpectraColor.white.rawValue)
        // The black center square stays near the center.
        #expect(image[150, 200] == SpectraColor.black.rawValue)
    }

    @Test func garbageInputIsRejected() {
        #expect(PhotoProcessor.process(imageData: Data([1, 2, 3]), settings: .init()) == nil)
    }
}
