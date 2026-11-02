import Foundation
import Testing
@testable import InkyTap

struct LZOTests {
    private func roundTrip(_ bytes: [UInt8], _ label: String) throws {
        let input = Data(bytes)
        let compressed = LZO.compress(input)
        let output = try LZO.decompress(compressed)
        #expect(output == input, "round trip failed for \(label) (\(bytes.count) bytes)")
    }

    @Test func emptyAndTiny() throws {
        try roundTrip([], "empty")
        try roundTrip([7], "one byte")
        try roundTrip([1, 2, 3], "three bytes")
        try roundTrip([1, 2, 3, 4], "four bytes")
        try roundTrip([5, 5, 5, 5, 5, 5, 5, 5, 5, 5], "ten repeats")
    }

    @Test func repetitiveBlocks() throws {
        try roundTrip([UInt8](repeating: 0x11, count: 2000), "solid block")
        try roundTrip((0..<2000).map { UInt8($0 % 7) }, "period 7")
        try roundTrip((0..<2000).map { ($0 / 304) % 2 == 0 ? 0x01 : 0x23 }, "striped rows")
        try roundTrip((0..<121_600).map { UInt8(($0 / 304 / 40) & 0x0F) }, "full framebuffer sized")
    }

    @Test func randomData() throws {
        var generator = SystemRandomNumberGenerator()
        for size in [1, 2, 3, 4, 17, 18, 19, 238, 239, 255, 256, 1999, 2000, 2001, 5000, 60_000] {
            let bytes = (0..<size).map { _ in UInt8.random(in: 0...255, using: &generator) }
            try roundTrip(bytes, "random \(size)")
        }
    }

    @Test func mixedLiteralsAndMatches() throws {
        var bytes: [UInt8] = []
        var generator = SystemRandomNumberGenerator()
        for i in 0..<300 {
            if i % 3 == 0 {
                bytes += (0..<Int.random(in: 1...40, using: &generator)).map { _ in UInt8.random(in: 0...255, using: &generator) }
            } else {
                bytes += [UInt8](repeating: UInt8(i & 0xFF), count: Int.random(in: 1...600, using: &generator))
            }
        }
        try roundTrip(bytes, "mixed")
    }

    @Test func longDistanceMatches() throws {
        // Matches beyond 16 KB and beyond 32 KB exercise the M4 encoder.
        var generator = SystemRandomNumberGenerator()
        let chunk = (0..<100).map { _ in UInt8.random(in: 0...255, using: &generator) }
        var bytes = chunk
        bytes += (0..<20_000).map { _ in UInt8.random(in: 0...255, using: &generator) }
        bytes += chunk
        bytes += (0..<20_000).map { _ in UInt8.random(in: 0...255, using: &generator) }
        bytes += chunk
        try roundTrip(bytes, "long distance")
    }
}
