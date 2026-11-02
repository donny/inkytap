import CoreNFC
import Foundation

/// A parsed ISO 7816 response: payload plus the two status words.
struct APDUResponse: Sendable, Equatable {
    var payload: Data
    var sw1: UInt8
    var sw2: UInt8

    var isSuccess: Bool { sw1 == 0x90 && sw2 == 0x00 }
    var statusHex: String { String(format: "%02X%02X", sw1, sw2) }
}

enum APDUError: LocalizedError {
    case invalidCommand
    case failed(command: String, status: String)

    var errorDescription: String? {
        switch self {
        case .invalidCommand:
            "Malformed APDU."
        case let .failed(command, status):
            "\(command) failed with status \(status)."
        }
    }
}

/// Commands understood by the Fudan FM1280 ("FMSC") e-paper controller.
/// See docs/nfc-protocol-notes.md.
enum EPaperCommand {
    /// VERIFY PIN with the factory default user PIN 20 09 12 10.
    static let verifyPIN: [UInt8] = [0x00, 0x20, 0x00, 0x01, 0x04, 0x20, 0x09, 0x12, 0x10]
    /// Get Config Info: TLV describing panel, capacity and firmware.
    static let getConfigInfo: [UInt8] = [0x00, 0xD1, 0x00, 0x00, 0x00]
    /// Get Image SN: index of the image currently shown.
    static let getImageSN: [UInt8] = [0x00, 0xD5, 0x00, 0x00, 0x00]
    /// Read image flip flags (seen in community drivers, undocumented).
    static let getImageInfo: [UInt8] = [0x00, 0xEB, 0x00, 0x00, 0x02]
    /// Get EPD Info (listed in the vendor manual, format unknown).
    static let getEPDInfo: [UInt8] = [0x00, 0xDC, 0x00, 0x00, 0x00]
    /// Get EPD Busy Status: 00 idle, 01 refreshing.
    static let getBusyStatus: [UInt8] = [0xF0, 0xDE, 0x00, 0x00, 0x01]
}

extension NFCISO7816Tag {
    /// Sends a raw APDU and returns the response without interpreting the status.
    func send(_ bytes: [UInt8]) async throws -> APDUResponse {
        guard let apdu = NFCISO7816APDU(data: Data(bytes)) else {
            throw APDUError.invalidCommand
        }
        let (payload, sw1, sw2) = try await sendCommand(apdu: apdu)
        return APDUResponse(payload: payload, sw1: sw1, sw2: sw2)
    }

    /// Sends an APDU and throws unless the status is 9000.
    @discardableResult
    func sendExpectingSuccess(_ bytes: [UInt8]) async throws -> APDUResponse {
        let response = try await send(bytes)
        guard response.isSuccess else {
            throw APDUError.failed(command: Data(bytes).hexString, status: response.statusHex)
        }
        return response
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined()
    }

    /// Parses simple 1-byte-tag / 1-byte-length TLV records, preserving order.
    func parseTLV() -> [TLV] {
        var result: [TLV] = []
        var index = startIndex
        while index + 1 < endIndex {
            let tag = self[index]
            let length = Int(self[index + 1])
            let valueStart = index + 2
            let valueEnd = valueStart + length
            guard valueEnd <= endIndex else { break }
            result.append(TLV(tag: tag, value: Data(self[valueStart..<valueEnd])))
            index = valueEnd
        }
        return result
    }
}

struct TLV: Sendable, Equatable, Identifiable {
    var tag: UInt8
    var value: Data
    var id: UInt8 { tag }
}
