import Foundation
import Darwin

public struct RepairPaths {
    public let cache: URL
    public let backups: URL
    public init(cache: URL, backups: URL) { self.cache = cache; self.backups = backups }
    public static var live: RepairPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return RepairPaths(cache: home.appendingPathComponent("Library/Group Containers/group.com.apple.replicatord/replicatord"), backups: home.appendingPathComponent("Library/Application Support/MirrorMate/Backups"))
    }
}

public protocol PairingService {
    func stop() throws
    func start() throws
}

public struct LaunchdPairingService: PairingService {
    let commands: CommandRunning
    let domain = "gui/\(getuid())"
    var service: String { domain + "/com.apple.replicatord" }
    public init(commands: CommandRunning = SystemCommands()) { self.commands = commands }
    private func checked(_ args: [String]) throws {
        let result = try commands.run("/bin/launchctl", args, timeout: 20)
        guard result.succeeded else { throw MateError.command("The pairing service could not complete a restart. No account or network settings were changed.") }
    }
    public func stop() throws {
        _ = try commands.run("/usr/bin/killall", ["-TERM", "iPhone Mirroring"], timeout: 5)
        let loaded = try commands.run("/bin/launchctl", ["print", service], timeout: 5)
        if loaded.succeeded { try checked(["bootout", service]) }
        for _ in 0..<50 {
            let running = try commands.run("/usr/bin/pgrep", ["-u", String(getuid()), "-x", "replicatord"], timeout: 3)
            if running.status == 1 { return }
            guard running.status == 0 else { throw MateError.command("Could not verify that the pairing service stopped. Cache files were left in place.") }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw MateError.command("The pairing service is still running. Cache files were left in place.")
    }
    public func start() throws {
        let result = try commands.run("/bin/launchctl", ["print", service], timeout: 5)
        if !result.succeeded { try checked(["bootstrap", domain, "/System/Library/LaunchAgents/com.apple.replicatord.plist"]) }
        try checked(["kickstart", service])
    }
}

public struct BackupManifest: Codable {
    public let formatVersion: Int
    public let userID: UInt32
    public let createdAt: Date
    public let application: String
    public init() { formatVersion = 1; userID = getuid(); createdAt = Date(); application = "MirrorMate" }
}

public struct BackupRecord: Identifiable {
    public let url: URL
    public let createdAt: Date
    public var id: String { url.lastPathComponent }
    public init(url: URL, createdAt: Date) { self.url = url; self.createdAt = createdAt }
}

private final class RepairLock {
    let descriptor: Int32
    init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        descriptor = Darwin.open(directory.appendingPathComponent(".repair.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw MateError.access }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 { close(descriptor); throw MateError.busy }
    }
    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

public struct RepairEngine {
    public let paths: RepairPaths
    public let service: PairingService
    private let files = FileManager.default
    public init(paths: RepairPaths = .live, service: PairingService = LaunchdPairingService()) { self.paths = paths; self.service = service }
    private func verifyDirectory(_ url: URL) throws {
        let info = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard info.isDirectory == true, info.isSymbolicLink != true,
              url.standardizedFileURL.path == url.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw MateError.unsupported("The pairing folder uses an unexpected path or symbolic link. Nothing was changed.")
        }
    }
    public func preflight(commands: CommandRunning = SystemCommands()) throws {
        guard getuid() != 0 else { throw MateError.unsupported("Run MirrorMate as your normal macOS user, without administrator privileges.") }
        try verifyDirectory(paths.cache)
        let query = try commands.run("/usr/bin/sqlite3", ["-readonly", "-cmd", ".timeout 1500", paths.cache.appendingPathComponent("replicatord.sql").path, "SELECT State FROM PairingRelationship LIMIT 1;"], timeout: 5)
        guard query.succeeded else { throw MateError.unsupported("The pairing cache is unreadable or its format has changed. MirrorMate has not modified it.") }
    }
    public func backups() -> [BackupRecord] {
        let folders = (try? files.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { folder -> BackupRecord? in
            guard let record = try? validateBackup(folder) else { return nil }
            return record
        }.sorted { $0.createdAt > $1.createdAt }
    }
    public func validateBackup(_ folder: URL) throws -> BackupRecord {
        let root = paths.backups.standardizedFileURL
        guard folder.deletingLastPathComponent().standardizedFileURL.path == root.path else { throw MateError.invalidBackup }
        try verifyDirectory(folder)
        try verifyDirectory(folder.appendingPathComponent("pairing-cache"))
        let data = try Data(contentsOf: folder.appendingPathComponent("manifest.json"))
        let manifest = try JSONDecoder().decode(BackupManifest.self, from: data)
        guard manifest.formatVersion == 1, manifest.application == "MirrorMate", manifest.userID == getuid(), files.fileExists(atPath: folder.appendingPathComponent("pairing-cache/replicatord.sql").path) else { throw MateError.invalidBackup }
        return BackupRecord(url: folder, createdAt: manifest.createdAt)
    }
    // The transaction can be tested against temporary directories and a simulated service.
    // Production callers must complete preflight before invoking it.
    public func rebuild(progress: (String) -> Void = { _ in }) throws -> BackupRecord {
        try verifyDirectory(paths.cache)
        let lock = try RepairLock(directory: paths.backups.deletingLastPathComponent())
        return try withExtendedLifetime(lock) {
            try files.createDirectory(at: paths.backups, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let folder = paths.backups.appendingPathComponent(UUID().uuidString)
            try files.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let manifest = BackupManifest()
            try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
            let original = folder.appendingPathComponent("pairing-cache")
            var moved = false
            do {
                progress("Closing mirroring and stopping the pairing service…")
                try service.stop()
                progress("Saving the original pairing cache…")
                try files.moveItem(at: paths.cache, to: original)
                moved = true
                progress("Starting a fresh pairing service…")
                try service.start()
                return BackupRecord(url: folder, createdAt: manifest.createdAt)
            } catch {
                let failure = error
                if moved {
                    do {
                        try service.stop()
                        if files.fileExists(atPath: paths.cache.path) { try files.moveItem(at: paths.cache, to: folder.appendingPathComponent("incomplete-new-cache")) }
                        try files.moveItem(at: original, to: paths.cache)
                        try service.start()
                    } catch { throw MateError.rollback("The backup remains in MirrorMate’s Backups folder. Restart your Mac before trying recovery.") }
                } else { try? service.start() }
                throw failure
            }
        }
    }
    public func restore(_ folder: URL, progress: (String) -> Void = { _ in }) throws {
        _ = try validateBackup(folder)
        let lock = try RepairLock(directory: paths.backups.deletingLastPathComponent())
        try withExtendedLifetime(lock) {
            let original = folder.appendingPathComponent("pairing-cache")
            let current = folder.appendingPathComponent("cache-before-restore-" + UUID().uuidString)
            var saved = false
            var restored = false
            do {
                progress("Stopping the pairing service…")
                try service.stop()
                if files.fileExists(atPath: paths.cache.path) {
                    try verifyDirectory(paths.cache)
                    try files.moveItem(at: paths.cache, to: current)
                    saved = true
                }
                progress("Restoring the selected backup…")
                try files.moveItem(at: original, to: paths.cache)
                restored = true
                try service.start()
            } catch {
                let failure = error
                do {
                    try service.stop()
                    if restored { try files.moveItem(at: paths.cache, to: original) }
                    if saved { try files.moveItem(at: current, to: paths.cache) }
                    try service.start()
                } catch { throw MateError.rollback("Both caches remain preserved in the selected backup folder. Restart your Mac before trying recovery.") }
                throw failure
            }
        }
    }
}
