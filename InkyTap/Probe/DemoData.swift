import Foundation

#if DEBUG
/// Debug-only hooks for screenshots: launch with the environment variable
/// `INKYTAP_SCREEN` set to `sendPhoto`, `probe` or `testPattern` to open that
/// screen directly with sample data. Used by scripts/screenshots.sh.
enum DemoData {
    enum Screen: String {
        case sendPhoto, probe, testPattern
    }

    static var requestedScreen: Screen? {
        ProcessInfo.processInfo.environment["INKYTAP_SCREEN"].flatMap(Screen.init(rawValue:))
    }

    static var samplePhotoData: Data? {
        Bundle.main.url(forResource: "SamplePhoto", withExtension: "jpg").flatMap { try? Data(contentsOf: $0) }
    }

    /// The probe result captured from a Tapmora 4-inch Spectra 6 on 2026-11-01.
    static let probeResult: DeviceProbeResult = {
        func hex(_ s: String) -> Data {
            var bytes: [UInt8] = []
            var chars = Array(s)
            while chars.count >= 2 {
                bytes.append(UInt8(String(chars[0...1]), radix: 16)!)
                chars.removeFirst(2)
            }
            return Data(bytes)
        }
        func record(_ name: String, _ command: [UInt8], _ status: String, _ payload: String = "") -> DeviceProbeResult.CommandRecord {
            let sw = hex(status)
            return .init(name: name, command: command, response: APDUResponse(payload: hex(payload), sw1: sw[0], sw2: sw[1]))
        }
        let config = "A007F0076001900130A10700FFFFFFFFFFFFB10110B20114B30100C004201EA001C1049E25C71DD10701200000000000E00E46E0008001810283038205860785"
        return DeviceProbeResult(
            tagIdentifier: hex("9E25C71D"),
            selectedAID: "D2760000850101",
            historicalBytes: hex("909E25C71D00"),
            records: [
                record("Verify PIN", EPaperCommand.verifyPIN, "6D00"),
                record("Get Config Info", EPaperCommand.getConfigInfo, "9000", config),
                record("Get Image SN", EPaperCommand.getImageSN, "9000", "00"),
                record("Get Image Info", EPaperCommand.getImageInfo, "6D00"),
                record("Get EPD Info", EPaperCommand.getEPDInfo, "6D00"),
                record("Get Busy Status", EPaperCommand.getBusyStatus, "9000", "01"),
            ],
            deviceInfo: EPaperDeviceInfo(payload: hex(config))
        )
    }()
}
#endif
