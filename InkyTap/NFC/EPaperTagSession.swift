import CoreNFC
import Foundation

/// Wraps a non-Sendable value whose thread-safety we vouch for manually.
struct UncheckedSendable<Value>: @unchecked Sendable {
    let value: Value
}

enum EPaperSessionError: LocalizedError {
    case readingUnavailable
    case failedToStartSession
    case unsupportedTag

    var errorDescription: String? {
        switch self {
        case .readingUnavailable: "NFC tag reading is not available on this device."
        case .failedToStartSession: "Could not start the NFC session."
        case .unsupportedTag: "That tag is not an ISO 7816 e-paper device."
        }
    }
}

/// One Core NFC tag-reader session that connects to the first ISO 7816 tag it
/// sees and runs `operation` against it. The result is delivered through
/// async/await; the session is invalidated when the operation finishes.
final class EPaperTagSession<Result: Sendable>: NSObject, NFCTagReaderSessionDelegate, @unchecked Sendable {
    typealias Operation = @Sendable (_ tag: any NFCISO7816Tag, _ setMessage: @Sendable @escaping (String) -> Void) async throws -> Result

    private let operation: Operation
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result, any Error>?
    private var session: NFCTagReaderSession?

    private init(operation: @escaping Operation) {
        self.operation = operation
    }

    /// Starts a session showing `alertMessage` and runs `operation` on the detected tag.
    static func run(alertMessage: String, operation: @escaping Operation) async throws -> Result {
        let holder = EPaperTagSession(operation: operation)
        return try await holder.start(alertMessage: alertMessage)
    }

    private func start(alertMessage: String) async throws -> Result {
        guard NFCTagReaderSession.readingAvailable else {
            throw EPaperSessionError.readingUnavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            guard let session = NFCTagReaderSession(pollingOption: [.iso14443], delegate: self, queue: nil) else {
                continuation.resume(throwing: EPaperSessionError.failedToStartSession)
                return
            }
            lock.withLock {
                self.continuation = continuation
                self.session = session
            }
            session.alertMessage = alertMessage
            session.begin()
        }
    }

    private func finish(_ result: Swift.Result<Result, any Error>) {
        let continuation = lock.withLock {
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(with: result)
    }

    // MARK: NFCTagReaderSessionDelegate (called on the session queue)

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        if tags.count > 1 {
            session.alertMessage = "More than one tag found. Present only one."
            session.restartPolling()
            return
        }
        guard let first = tags.first, case let .iso7816(tag) = first else {
            session.invalidate(errorMessage: EPaperSessionError.unsupportedTag.localizedDescription)
            return
        }

        let boxedTag = UncheckedSendable(value: first)
        let boxedISOTag = UncheckedSendable(value: tag)
        let boxedSession = UncheckedSendable(value: session)
        let operation = self.operation

        Task {
            do {
                try await boxedSession.value.connect(to: boxedTag.value)
                let result = try await operation(boxedISOTag.value) { message in
                    boxedSession.value.alertMessage = message
                }
                self.finish(.success(result))
                boxedSession.value.invalidate()
            } catch {
                self.finish(.failure(error))
                boxedSession.value.invalidate(errorMessage: error.localizedDescription)
            }
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
        // After a successful finish this arrives as "user canceled"; finish() is then a no-op.
        finish(.failure(error))
    }
}
