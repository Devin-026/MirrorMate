import Foundation
import Darwin

public enum CheckState: String, Codable { case pass, attention, unknown, fail }
public struct CheckItem: Identifiable, Codable {
    public let id: String
    public let title: String
    public let symbol: String
    public var value: String
    public var state: CheckState
    public init(_ id: String, _ title: String, _ symbol: String, _ value: String = "Not checked", _ state: CheckState = .unknown) {
        self.id = id; self.title = title; self.symbol = symbol; self.value = value; self.state = state
    }
}

public enum PairingState: String, Codable { case paired, pending, absent, inaccessible, unsupported }

public struct DiagnosticReport {
    public var checks: [CheckItem]
    public var pairing: PairingState
    public var hasRepeatedPairingFailure: Bool
    public var recentFrame: Bool
    public var osVersion: String
    public var architecture: String
    public var checkedAt: Date
    public init(checks: [CheckItem], pairing: PairingState, hasRepeatedPairingFailure: Bool, recentFrame: Bool, osVersion: String, architecture: String, checkedAt: Date) {
        self.checks = checks; self.pairing = pairing; self.hasRepeatedPairingFailure = hasRepeatedPairingFailure
        self.recentFrame = recentFrame; self.osVersion = osVersion; self.architecture = architecture; self.checkedAt = checkedAt
    }
    public var canRepair: Bool { pairing == .pending && hasRepeatedPairingFailure && checks.first(where: { $0.id == "mac" })?.state == .pass }
    public var summary: String {
        if canRepair { return "Pairing is stuck" }
        if pairing == .inaccessible { return "Folder access needed" }
        if checks.contains(where: { $0.state == .fail }) { return "One more thing to check" }
        if recentFrame { return "You’re connected" }
        if pairing == .paired { return "Pairing looks good" }
        if pairing == .pending { return "Pairing is in progress" }
        return "Let’s get you connected"
    }
    public var detail: String {
        if canRepair { return "Your Mac sees the iPhone, but pairing keeps failing. A fresh pairing cache may help." }
        if pairing == .inaccessible { return "Allow access to the pairing folder so MirrorMate can finish checking." }
        if checks.contains(where: { $0.id == "mac" && $0.state == .fail }) { return "iPhone Mirroring needs macOS 15 or later and Apple silicon or an Apple T2 chip." }
        if checks.contains(where: { $0.id == "wifi" && $0.state == .fail }) { return "Turn on Wi-Fi on your Mac and iPhone, then check again." }
        if checks.contains(where: { $0.id == "bluetooth" && $0.state == .fail }) { return "Turn on Bluetooth on your Mac and iPhone, then check again." }
        if recentFrame { return "A recent mirroring session received video from your iPhone." }
        if pairing == .paired { return "Open iPhone Mirroring. Keep your iPhone nearby and locked." }
        if pairing == .pending { return "Keep your iPhone nearby. If pairing never finishes, run another check." }
        return "Open iPhone Mirroring to finish setup. Both devices need the same Apple Account and two-factor authentication." }
    public var shareableText: String {
        (["MirrorMate diagnostic report", "macOS: \(osVersion)", "Architecture: \(architecture)", "Pairing: \(pairing.rawValue)", "Repeated pairing failures: \(hasRepeatedPairingFailure)", "Recent video frame: \(recentFrame)"] + checks.map { "\($0.title): \($0.value)" } + ["No device names, account details, serial numbers, identifiers, or raw logs are included."]).joined(separator: "\n")
    }
}

public struct Diagnostics {
    public let commands: CommandRunning
    public let cache: URL
    public init(commands: CommandRunning = SystemCommands(), cache: URL = RepairPaths.live.cache) { self.commands = commands; self.cache = cache }
    public static var initialChecks: [CheckItem] { [CheckItem("mac", "This Mac", "desktopcomputer"), CheckItem("wifi", "Wi-Fi", "wifi"), CheckItem("bluetooth", "Bluetooth", "bluetooth"), CheckItem("pairing", "System pairing", "link"), CheckItem("session", "Mirroring session", "rectangle.on.rectangle")] }
    public static func parsePairing(_ output: String, status: Int32) -> PairingState {
        if status != 0 {
            let text = output.lowercased()
            if text.contains("not permitted") || text.contains("permission denied") || text.contains("authorization denied") { return .inaccessible }
            return .unsupported
        }
        let states = output.split(whereSeparator: \.isNewline).compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if states.contains(2) { return .paired }
        if states.contains(0) || states.contains(1) { return .pending }
        return .absent
    }
    public static func parseSession(_ logs: String, appRunning: Bool) -> Bool {
        guard appRunning else { return false }
        var frame = false
        for line in logs.split(whereSeparator: \.isNewline) {
            if line.contains("receivedFirstFrame") { frame = true }
            if line.contains("Tearing down the session") || line.contains("Finished tearing down session") { frame = false }
        }
        return frame
    }
    public func run() -> DiagnosticReport {
        func command(_ path: String, _ args: [String], timeout: TimeInterval = 12) -> CommandResult { (try? commands.run(path, args, timeout: timeout)) ?? CommandResult(status: -1) }
        var items = Self.initialChecks
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let osString = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        let arch = command("/usr/bin/uname", ["-m"]).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let t2 = arch == "x86_64" && command("/usr/sbin/system_profiler", ["SPiBridgeDataType"]).output.contains("Apple T2")
        let compatible = os.majorVersion >= 15 && (arch == "arm64" || t2)
        items[0].value = compatible ? "Compatible" : "Check requirements"; items[0].state = compatible ? .pass : .fail
        let ports = command("/usr/sbin/networksetup", ["-listallhardwareports"]).output
        let lines = ports.components(separatedBy: "\n")
        let index = lines.firstIndex(where: { $0.contains("Hardware Port: Wi-Fi") })
        var interface: String?
        if let index, index + 1 < lines.count { interface = lines[index + 1].replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces) }
        if let interface, !interface.isEmpty {
            let power = command("/usr/sbin/networksetup", ["-getairportpower", interface])
            let on = power.succeeded && power.output.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(": On")
            items[1].value = on ? "On" : (power.succeeded ? "Off" : "Unavailable")
            items[1].state = on ? .pass : (power.succeeded ? .fail : .unknown)
        }
        let bluetooth = command("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"], timeout: 18)
        if let data = bluetooth.output.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let controllers = object["SPBluetoothDataType"] as? [[String: Any]], let controller = controllers.first?["controller_properties"] as? [String: Any], let state = controller["controller_state"] as? String {
            let on = state.lowercased().contains("on")
            items[2].value = on ? "On" : "Off"; items[2].state = on ? .pass : .fail
        }
        let db = cache.appendingPathComponent("replicatord.sql")
        // Query even when existence checks fail: TCC may mask a protected folder as absent.
        let sql = command("/usr/bin/sqlite3", ["-readonly", "-cmd", ".timeout 1500", db.path, "SELECT State FROM PairingRelationship;"])
        var pairing = Self.parsePairing(sql.output, status: sql.status)
        if pairing == .unsupported && sql.output.lowercased().contains("unable to open") {
            let readable = FileManager.default.isReadableFile(atPath: cache.deletingLastPathComponent().path)
            pairing = readable ? .absent : .inaccessible
        }
        items[3].value = [.paired: "Paired", .pending: "In progress", .absent: "Not set up", .inaccessible: "Allow access", .unsupported: "Unknown format"][pairing] ?? "Unknown"
        items[3].state = pairing == .paired ? .pass : (pairing == .pending ? .attention : .unknown)
        let predicate = "subsystem == \"com.apple.screensharing\" AND (eventMessage CONTAINS \"noCompatiblePhone\" OR eventMessage CONTAINS \"receivedFirstFrame\" OR eventMessage CONTAINS \"Tearing down the session\" OR eventMessage CONTAINS \"Finished tearing down session\")"
        let logs = command("/usr/bin/log", ["show", "--last", "5m", "--style", "compact", "--info", "--predicate", predicate], timeout: 18)
        let repeated = logs.output.components(separatedBy: "\n").filter { $0.contains("noCompatiblePhone") }.count >= 2
        let running = command("/usr/bin/pgrep", ["-u", String(getuid()), "-x", "iPhone Mirroring"]).succeeded
        let frame = Self.parseSession(logs.output, appRunning: running)
        items[4].value = frame ? "Recent video" : (logs.succeeded ? "Not verified" : "Logs unavailable")
        items[4].state = frame ? .pass : .unknown
        return DiagnosticReport(checks: items, pairing: pairing, hasRepeatedPairingFailure: repeated, recentFrame: frame, osVersion: osString, architecture: arch, checkedAt: Date())
    }
}
