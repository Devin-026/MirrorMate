import Foundation
import Darwin

public struct CommandResult {
    public let status: Int32
    public let output: String
    public var succeeded: Bool { status == 0 }
    public init(status: Int32, output: String = "") { self.status = status; self.output = output }
}

public protocol CommandRunning {
    func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) throws -> CommandResult
}

public enum MateError: LocalizedError {
    case command(String), unsupported(String), access, busy, invalidBackup, rollback(String)
    public var errorDescription: String? {
        switch self {
        case .command(let text), .unsupported(let text): return text
        case .access: return "MirrorMate needs access to your local pairing folder. Choose Allow folder access, then check again."
        case .busy: return "Another repair is running. Wait for it to finish."
        case .invalidBackup: return "This is not an intact MirrorMate backup for this macOS user. Nothing was changed."
        case .rollback(let text): return "Automatic recovery could not finish. Your original backup is preserved. " + text
        }
    }
}

public struct SystemCommands: CommandRunning {
    public init() {}
    public func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["LANG"] = "en_US.UTF-8"
        process.environment = environment
        // A temporary output file avoids pipe-buffer deadlocks for system_profiler and log.
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("mirrormate-" + UUID().uuidString)
        FileManager.default.createFile(atPath: outputURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }
        process.standardOutput = handle
        process.standardError = handle
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()
        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 2)
            }
            throw MateError.command("A system check timed out. Nothing further was changed.")
        }
        try handle.synchronize()
        let text = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        return CommandResult(status: process.terminationStatus, output: text)
    }
}
