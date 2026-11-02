import CoreNFC
import Foundation

/// Everything one probe tap learned about the tag, kept raw so nothing is lost.
struct DeviceProbeResult: Sendable, Equatable {
    struct CommandRecord: Sendable, Equatable, Identifiable {
        var name: String
        var command: [UInt8]
        var response: APDUResponse
        var id: String { name }
    }

    var tagIdentifier: Data
    var selectedAID: String
    var historicalBytes: Data?
    var records: [CommandRecord]
    var deviceInfo: EPaperDeviceInfo?

    func record(named name: String) -> CommandRecord? {
        records.first { $0.name == name }
    }

    /// Plain-text report suitable for pasting into a chat or bug tracker.
    var report: String {
        var lines: [String] = []
        lines.append("InkyTap device probe")
        lines.append("Tag UID: \(tagIdentifier.hexString)")
        lines.append("Selected AID: \(selectedAID)")
        lines.append("Historical bytes: \(historicalBytes?.hexString ?? "-")")
        lines.append("")
        for record in records {
            lines.append("\(record.name) [\(Data(record.command).hexString)] -> \(record.response.statusHex) \(record.response.payload.hexString)")
        }
        if let deviceInfo {
            lines.append("")
            lines.append("Config TLVs:")
            for tlv in deviceInfo.tlvs {
                lines.append(String(format: "  %02X (%d): ", tlv.tag, tlv.value.count) + tlv.value.hexString)
            }
            lines.append("")
            lines.append("Interpretation:")
            if let name = deviceInfo.name { lines.append("  Name: \(name)") }
            if let uid = deviceInfo.uid { lines.append(String(format: "  UID: %08X", uid)) }
            lines.append(contentsOf: deviceInfo.panelNotes.map { "  " + $0 })
            if let imageCapacity = deviceInfo.imageCapacity { lines.append("  Image slots: \(imageCapacity)") }
            if let userDataKB = deviceInfo.userDataKB { lines.append("  User data: \(userDataKB) KB") }
            if let batteryPowered = deviceInfo.batteryPowered { lines.append("  Power: \(batteryPowered ? "battery" : "NFC field")") }
            if let compressionSupported = deviceInfo.compressionSupported { lines.append("  LZO upload: \(compressionSupported ? "supported" : "not supported")") }
            if let firmwareVersion = deviceInfo.firmwareVersion { lines.append(String(format: "  Firmware: %02X", firmwareVersion)) }
        }
        return lines.joined(separator: "\n")
    }
}

enum DeviceProbe {
    /// Authenticates with the default PIN, reads the config TLV, and tries a
    /// few read-only commands. Nothing here writes to the tag or refreshes the panel.
    static func run() async throws -> DeviceProbeResult {
        try await EPaperTagSession.run(alertMessage: "Hold your iPhone on the e-ink display.") { tag, setMessage in
            setMessage("Reading device info…")

            var records: [DeviceProbeResult.CommandRecord] = []
            func probe(_ name: String, _ command: [UInt8]) async throws {
                let response = try await tag.send(command)
                records.append(.init(name: name, command: command, response: response))
            }

            try await probe("Verify PIN", EPaperCommand.verifyPIN)
            try await probe("Get Config Info", EPaperCommand.getConfigInfo)
            try await probe("Get Image SN", EPaperCommand.getImageSN)
            try await probe("Get Image Info", EPaperCommand.getImageInfo)
            try await probe("Get EPD Info", EPaperCommand.getEPDInfo)
            try await probe("Get Busy Status", EPaperCommand.getBusyStatus)

            let config = records.first { $0.name == "Get Config Info" }?.response
            let deviceInfo = config.flatMap { $0.isSuccess ? EPaperDeviceInfo(payload: $0.payload) : nil }

            setMessage("Done.")
            return DeviceProbeResult(
                tagIdentifier: tag.identifier,
                selectedAID: tag.initialSelectedAID,
                historicalBytes: tag.historicalBytes,
                records: records,
                deviceInfo: deviceInfo
            )
        }
    }
}
