import AppKit
import SwiftUI
import MirrorMateCore

enum ProjectLinks {
    static let repository = URL(string: "https://github.com/Devin-026/MirrorMate")!
}

@MainActor final class MateModel: ObservableObject {
    @Published var report: DiagnosticReport?
    @Published var isBusy = false
    @Published var activity = ""
    @Published var notice: String?
    @Published var failure: String?
    @Published var backupRecords: [BackupRecord] = []
    @Published var showRepairConfirmation = false
    @Published var showBackups = false
    @Published var showAbout = false
    let preview: Bool
    private var scopedFolder: URL?

    init(preview: Bool = false) {
        self.preview = preview
        if preview {
            report = DiagnosticReport(checks: [CheckItem("mac", "This Mac", "desktopcomputer", "Compatible", .pass), CheckItem("wifi", "Wi-Fi", "wifi", "On", .pass), CheckItem("bluetooth", "Bluetooth", "bluetooth", "On", .pass), CheckItem("pairing", "System pairing", "link", "In progress", .attention), CheckItem("session", "Mirroring session", "rectangle.on.rectangle", "Not connected", .unknown)], pairing: .pending, hasRepeatedPairingFailure: true, recentFrame: false, osVersion: "27.2.1", architecture: "arm64", checkedAt: Date())
        } else if let data = UserDefaults.standard.data(forKey: "PairingFolderBookmark") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale), !stale, url.startAccessingSecurityScopedResource() { scopedFolder = url }
        }
        refreshBackups()
    }
    var checks: [CheckItem] { report?.checks ?? Diagnostics.initialChecks }
    var title: String { isBusy ? "Working on your connection" : report?.summary ?? "A little help connecting" }
    var detail: String { isBusy ? activity : report?.detail ?? "Check what’s getting between your Mac and iPhone. Everything stays on this Mac." }
    var checkedLabel: String {
        guard let date = report?.checkedAt else { return "Local checks only" }
        return "Checked " + date.formatted(date: .omitted, time: .shortened)
    }
    func scan() {
        guard !isBusy, !preview else { return }
        isBusy = true; activity = "Checking Mac, wireless connections, and pairing…"; failure = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { Diagnostics().run() }.value
            report = result; isBusy = false
        }
    }
    func refreshBackups() { backupRecords = preview ? [] : RepairEngine().backups() }
    func openMirroring() { NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/iPhone Mirroring.app"), configuration: NSWorkspace.OpenConfiguration()) }
    func showBackupFolder() {
        let url = RepairPaths.live.backups
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]); NSWorkspace.shared.open(url) }
        catch { failure = error.localizedDescription }
    }
    func copyReport() {
        guard let report else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report.shareableText, forType: .string)
        notice = "A report without personal details was copied."
    }
    func allowFolder() {
        let panel = NSOpenPanel()
        panel.title = "Allow access to the pairing folder"
        panel.message = "Choose group.com.apple.replicatord. MirrorMate uses this folder only to inspect, back up, or rebuild local pairing."
        panel.prompt = "Allow folder access"
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.directoryURL = RepairPaths.live.cache.deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard url.standardizedFileURL.path == RepairPaths.live.cache.deletingLastPathComponent().standardizedFileURL.path else { failure = "Choose the group.com.apple.replicatord folder shown in the dialog."; return }
        scopedFolder?.stopAccessingSecurityScopedResource()
        if url.startAccessingSecurityScopedResource() { scopedFolder = url }
        if let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { UserDefaults.standard.set(bookmark, forKey: "PairingFolderBookmark") }
        scan()
    }
    func repair() {
        guard !isBusy, report?.canRepair == true, !preview else { return }
        isBusy = true; failure = nil; notice = nil; activity = "Checking again before making changes…"
        Task {
            do {
                let backup = try await Task.detached(priority: .userInitiated) { [weak self] () throws -> BackupRecord in
                    let fresh = Diagnostics().run()
                    guard fresh.canRepair else { throw MateError.unsupported("Pairing no longer appears stuck. Run another check before repairing.") }
                    let engine = RepairEngine()
                    try engine.preflight()
                    return try engine.rebuild { message in Task { @MainActor [weak self] in self?.activity = message } }
                }.value
                refreshBackups()
                notice = "Pairing cache rebuilt. Your original backup is saved. Open iPhone Mirroring and complete setup."
                activity = "Waiting for your iPhone to pair…"
                let result = await Task.detached(priority: .utility) { () async -> DiagnosticReport in
                    let commands = SystemCommands()
                    for _ in 0..<20 {
                        let query = try? commands.run("/usr/bin/sqlite3", ["-readonly", RepairPaths.live.cache.appendingPathComponent("replicatord.sql").path, "SELECT State FROM PairingRelationship;"], timeout: 2)
                        if let query, Diagnostics.parsePairing(query.output, status: query.status) == .paired { break }
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                    }
                    return Diagnostics().run()
                }.value
                report = result; isBusy = false
                _ = backup
                openMirroring()
            } catch { failure = error.localizedDescription; isBusy = false; refreshBackups() }
        }
    }
    func restore(_ backup: BackupRecord) {
        guard !isBusy, !preview else { return }
        showBackups = false; isBusy = true; failure = nil; notice = nil; activity = "Restoring your selected backup…"
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { [weak self] in
                    try RepairEngine().restore(backup.url) { message in Task { @MainActor [weak self] in self?.activity = message } }
                }.value
                notice = "Backup restored. The cache from before this restore was also preserved."
                report = await Task.detached { Diagnostics().run() }.value
                isBusy = false; refreshBackups(); openMirroring()
            } catch { failure = error.localizedDescription; isBusy = false; refreshBackups() }
        }
    }
}
