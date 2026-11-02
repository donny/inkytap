import CoreNFC
import Foundation

/// What happened during one upload-and-refresh pass, for the on-screen log.
struct UploadReport: Sendable, Equatable {
    var layout: String
    var chunks: Int
    var rawBytes: Int
    var compressedBytes: Int
    var fragments: Int
    var pinStatus: String
    var uploadSeconds: Double
    var refreshStatus: String
    var refreshSeconds: Double
    var busyAfter: String

    var text: String {
        """
        Layout: \(layout)
        \(chunks) image slots, raw \(rawBytes) B → LZO \(compressedBytes) B in \(fragments) fragments
        PIN: \(pinStatus)
        Upload: \(String(format: "%.1f", uploadSeconds)) s
        Refresh: \(refreshStatus) after \(String(format: "%.1f", refreshSeconds)) s
        Busy after refresh: \(busyAfter)
        """
    }
}

enum EPaperUploader {
    static let blockSize = 2000
    static let fragmentSize = 250

    /// Builds the F0 D3 command sequence that stores `image` at `imageIndex`.
    static func uploadCommands(for image: Data, imageIndex: UInt8) -> (commands: [[UInt8]], blocks: Int, compressedBytes: Int) {
        var commands: [[UInt8]] = []
        var compressedTotal = 0
        var blockCount = 0

        var offset = 0
        while offset < image.count {
            let end = min(offset + blockSize, image.count)
            let block = image.subdata(in: offset..<end)
            let compressed = LZO.compress(block)
            compressedTotal += compressed.count

            var fragmentOffset = 0
            var fragmentIndex = 0
            while fragmentOffset < compressed.count {
                let fragmentEnd = min(fragmentOffset + fragmentSize, compressed.count)
                let fragment = compressed.subdata(in: fragmentOffset..<fragmentEnd)
                let isLast = fragmentEnd == compressed.count

                var command: [UInt8] = [0xF0, 0xD3, imageIndex, isLast ? 0x01 : 0x00, UInt8(fragment.count + 2)]
                command.append(UInt8(blockCount))
                command.append(UInt8(fragmentIndex))
                command.append(contentsOf: fragment)
                commands.append(command)

                fragmentOffset = fragmentEnd
                fragmentIndex += 1
            }

            blockCount += 1
            offset = end
        }
        return (commands, blockCount, compressedTotal)
    }

    /// Uploads each chunk to consecutive image slots starting at 0, then
    /// triggers a blocking refresh of slot 0.
    static func send(
        chunks: [Data],
        layoutDescription: String,
        tag: any NFCISO7816Tag,
        setMessage: @Sendable @escaping (String) -> Void
    ) async throws -> UploadReport {
        // Older firmware wants the default PIN; the Tapmora answers 6D00. Either is fine.
        let pin = try await tag.send(EPaperCommand.verifyPIN)

        var allCommands: [[UInt8]] = []
        var compressedBytes = 0
        for (index, chunk) in chunks.enumerated() {
            let (commands, _, compressed) = uploadCommands(for: chunk, imageIndex: UInt8(index))
            allCommands.append(contentsOf: commands)
            compressedBytes += compressed
        }

        setMessage("Uploading 0%")
        let uploadStart = Date()
        var lastShown = -1
        for (index, command) in allCommands.enumerated() {
            try await tag.sendExpectingSuccess(command)
            let percent = (index + 1) * 100 / allCommands.count
            if percent / 5 != lastShown {
                lastShown = percent / 5
                setMessage("Uploading \(percent)%")
            }
        }
        let uploadSeconds = Date().timeIntervalSince(uploadStart)

        setMessage("Refreshing display. Keep the phone still…")
        let refreshStart = Date()
        let refresh = try await tag.send([0xF0, 0xD4, 0x85, 0x00, 0x00])
        let refreshSeconds = Date().timeIntervalSince(refreshStart)

        let busy = (try? await tag.send(EPaperCommand.getBusyStatus)).map {
            "\($0.statusHex) \($0.payload.hexString)"
        } ?? "n/a"

        setMessage(refresh.isSuccess ? "Done." : "Refresh returned \(refresh.statusHex)")

        return UploadReport(
            layout: layoutDescription,
            chunks: chunks.count,
            rawBytes: chunks.reduce(0) { $0 + $1.count },
            compressedBytes: compressedBytes,
            fragments: allCommands.count,
            pinStatus: pin.statusHex,
            uploadSeconds: uploadSeconds,
            refreshStatus: refresh.statusHex,
            refreshSeconds: refreshSeconds,
            busyAfter: busy
        )
    }
}
