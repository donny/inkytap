import Foundation
import Testing
@testable import InkyTap

struct FramebufferTests {
    /// Upright image with a distinct code in a few known places.
    private var sample: PixelImage {
        var image = PixelImage(width: PanelLayout.panelWidth, height: PanelLayout.panelHeight, fill: .white)
        image[0, 0] = SpectraColor.black.rawValue      // top-left
        image[0, 1] = SpectraColor.red.rawValue        // just below top-left
        image[299, 0] = SpectraColor.blue.rawValue     // top-right
        image[0, 399] = SpectraColor.green.rawValue    // bottom-left
        image[299, 399] = SpectraColor.yellow.rawValue // bottom-right
        return image
    }

    private func nativeRow(_ data: Data, _ row: Int) -> [UInt8] {
        let n = PanelLayout.bytesPerNativeRow
        return Array(data[(row * n)..<((row + 1) * n)])
    }

    @Test func sizes() {
        let data = Framebuffer.pack(sample, layout: PanelLayout())
        #expect(data.count == 60_800)
        let chunks = Framebuffer.imageChunks(data)
        #expect(chunks.count == 4)
        #expect(chunks.allSatisfy { $0.count == 15_200 })
        #expect(chunks.reduce(Data(), +) == data)
    }

    @Test func defaultLayout() {
        // Column 0 of the image is native row 0, top pixel in the high nibble of byte 0.
        let data = Framebuffer.pack(sample, layout: PanelLayout())
        let row0 = nativeRow(data, 0)
        #expect(row0[0] == 0x03)          // black (0) then red (3)
        #expect(row0[1] == 0x11)          // white, white
        #expect(row0[199] == 0x16)        // white then green at the bottom
        let row299 = nativeRow(data, 299)
        #expect(row299[0] == 0x51)        // blue then white
        #expect(row299[199] == 0x12)      // white then yellow
        // Padding rows 300...303 are white.
        for r in 300..<304 {
            #expect(nativeRow(data, r).allSatisfy { $0 == 0x11 })
        }
    }

    @Test func mirrorColumns() {
        var layout = PanelLayout()
        layout.mirrorColumns = true
        let data = Framebuffer.pack(sample, layout: layout)
        #expect(nativeRow(data, 0)[0] == 0x51)     // image column 299 comes first
        #expect(nativeRow(data, 299)[0] == 0x03)
    }

    @Test func mirrorRows() {
        var layout = PanelLayout()
        layout.mirrorRows = true
        let data = Framebuffer.pack(sample, layout: layout)
        let row0 = nativeRow(data, 0)
        #expect(row0[0] == 0x61)       // bottom-left green first, then white
        #expect(row0[199] == 0x30)     // red then black at the end of the column
    }

    @Test func lowNibbleFirst() {
        var layout = PanelLayout()
        layout.lowNibbleFirst = true
        let data = Framebuffer.pack(sample, layout: layout)
        #expect(nativeRow(data, 0)[0] == 0x30)     // red in high nibble, black in low
    }

    @Test func paddingAtStart() {
        var layout = PanelLayout()
        layout.padAtStart = true
        layout.paddingColor = .black
        let data = Framebuffer.pack(sample, layout: layout)
        for r in 0..<4 {
            #expect(nativeRow(data, r).allSatisfy { $0 == 0x00 })
        }
        #expect(nativeRow(data, 4)[0] == 0x03)
        #expect(nativeRow(data, 303)[0] == 0x51)
    }

    @Test func uploadCommandsAreWellFormed() {
        let image = TestPattern.colorBars.render()
        let chunks = Framebuffer.imageChunks(Framebuffer.pack(image, layout: PanelLayout()))
        for (slot, chunk) in chunks.enumerated() {
            let (commands, blocks, _) = EPaperUploader.uploadCommands(for: chunk, imageIndex: UInt8(slot))
            #expect(blocks == 8)
            for command in commands {
                #expect(command[0] == 0xF0 && command[1] == 0xD3 && command[2] == UInt8(slot))
                #expect(command[3] == 0x00 || command[3] == 0x01)
                #expect(Int(command[4]) == command.count - 5)
                #expect(command.count - 7 <= EPaperUploader.fragmentSize)
            }
            var reassembled = Data()
            var blockIndex = 0
            var compressed = Data()
            var blockLengths: [Int] = []
            for command in commands {
                #expect(Int(command[5]) == blockIndex)
                compressed.append(contentsOf: command[7...])
                if command[3] == 0x01 {
                    let block = try! LZO.decompress(compressed)
                    blockLengths.append(block.count)
                    reassembled.append(block)
                    compressed.removeAll()
                    blockIndex += 1
                }
            }
            #expect(blockLengths == [2000, 2000, 2000, 2000, 2000, 2000, 2000, 1200])
            #expect(reassembled == chunk)
        }
    }
}
