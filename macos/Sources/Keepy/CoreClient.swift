import Foundation

struct CoreError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
}

// A serial pipe keeps secret arguments out of argv, files, sockets and logs.
final class CoreClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.keepy.core")
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    private var sequence = 0
    private var startupError: Error?
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase; return decoder
    }()
    init(executable: URL? = nil) {
        process.executableURL = executable ?? Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("keepy-core")
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in
            DispatchQueue.main.async { NotificationCenter.default.post(name: .coreStopped, object: nil) }
        }
        do { try process.run() } catch { startupError = CoreError(message: "The vault service could not start. Reinstall the application.") }
    }
    func request(_ command: String, _ arguments: [String: Any] = [:]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    if let startupError { throw startupError }
                    guard process.isRunning else { throw CoreError(message: "The vault service stopped. Reopen the application.") }
                    sequence += 1
                    var request = arguments; request["id"] = sequence; request["command"] = command
                    var encoded = try JSONSerialization.data(withJSONObject: request)
                    encoded.append(10)
                    defer { encoded.resetBytes(in: 0..<encoded.count) }
                    try input.fileHandleForWriting.write(contentsOf: encoded)
                    while !buffer.contains(10) {
                        let data = output.fileHandleForReading.availableData
                        guard !data.isEmpty else {
                            throw CoreError(message: "The vault service disconnected. Close any other copy of Keepy, then reopen the application.")
                        }
                        buffer.append(data)
                        guard buffer.count <= 72 * 1024 * 1024 else { throw CoreError(message: "Vault response is too large.") }
                    }
                    let end = buffer.firstIndex(of: 10)!
                    var line = Data(buffer[..<end]); buffer.removeSubrange(...end)
                    defer { line.resetBytes(in: 0..<line.count) }
                    guard let response = try JSONSerialization.jsonObject(with: line) as? [String: Any], response["id"] as? Int == sequence else {
                        throw CoreError(message: "Invalid vault service response.")
                    }
                    if let error = response["error"] as? String { throw CoreError(message: error) }
                    let result = response["result"] ?? NSNull()
                    continuation.resume(returning: try JSONSerialization.data(withJSONObject: result, options: [.fragmentsAllowed]))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                try? input.fileHandleForWriting.close()
                let deadline = Date().addingTimeInterval(3)
                while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
                if process.isRunning { process.terminate() }
                buffer.resetBytes(in: 0..<buffer.count); buffer.removeAll()
                continuation.resume()
            }
        }
    }

    // Keep dedicated Keychain material out of view models and published state.
    func unlockBiometric(vaultID: String, ticket: String, credential: Data) async throws -> Data {
        guard credential.count <= 4096,
              let value = try JSONSerialization.jsonObject(with: credential) as? [String: Any] else {
            throw TouchIDError.missing
        }
        return try await request("unlock_biometric", ["vault_id": vaultID, "ticket": ticket, "credential": value])
    }

}
extension Notification.Name { static let coreStopped = Notification.Name("KeepyCoreStopped") }
