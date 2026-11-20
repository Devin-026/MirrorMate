import Foundation
import CoreGraphics
import MirrorMateCore

struct CheckFailure: Error { let message: String }
private var assertionFailures: [String] = []
func XCTAssertTrue(_ value: Bool, _ message: String = "Expected true") { if !value { assertionFailures.append(message) } }
func XCTAssertFalse(_ value: Bool, _ message: String = "Expected false") { XCTAssertTrue(!value, message) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "Values differ") { XCTAssertTrue(a == b, message) }
func XCTAssertNotNil<T>(_ value: T?, _ message: String = "Expected non-nil") { XCTAssertTrue(value != nil, message) }
func XCTAssertThrowsError<T>(_ body: @autoclosure () throws -> T) { do { _ = try body(); assertionFailures.append("Expected an error") } catch {} }

final class SimulatedService: PairingService {
    var starts = 0
    var stops = 0
    var failNextStart = false
    var onStart: (() throws -> Void)?
    func stop() throws { stops += 1 }
    func start() throws {
        starts += 1
        if failNextStart { failNextStart = false; try onStart?(); throw MateError.command("Simulated startup failure") }
    }
}

final class RepairTests {
    var root: URL!
    var cache: URL!
    var backups: URL!
    var service: SimulatedService!
    var engine: RepairEngine { RepairEngine(paths: RepairPaths(cache: cache, backups: backups), service: service) }
    func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        cache = root.appendingPathComponent("cache"); backups = root.appendingPathComponent("backups")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("original-cache".utf8).write(to: cache.appendingPathComponent("replicatord.sql"))
        service = SimulatedService()
    }
    func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func testRebuildPreservesOriginalAndRestoresWithoutDiscardingCurrentCache() throws {
        let backup = try engine.rebuild()
        XCTAssertEqual(try String(contentsOf: backup.url.appendingPathComponent("pairing-cache/replicatord.sql"), encoding: .utf8), "original-cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
        try Data("new-cache".utf8).write(to: cache.appendingPathComponent("replicatord.sql"))
        try engine.restore(backup.url)
        XCTAssertEqual(try String(contentsOf: cache.appendingPathComponent("replicatord.sql"), encoding: .utf8), "original-cache")
        let saved = try FileManager.default.contentsOfDirectory(at: backup.url, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("cache-before-restore-") }
        XCTAssertNotNil(saved)
        XCTAssertEqual(try String(contentsOf: saved!.appendingPathComponent("replicatord.sql"), encoding: .utf8), "new-cache")
        XCTAssertTrue(engine.backups().isEmpty, "A consumed backup must not be offered for restore again")
    }
    func testFailedServiceStartupRollsBackOriginalAndKeepsFailedNewCache() throws {
        service.failNextStart = true
        service.onStart = {
            try FileManager.default.createDirectory(at: self.cache, withIntermediateDirectories: false)
            try Data("incomplete".utf8).write(to: self.cache.appendingPathComponent("replicatord.sql"))
        }
        XCTAssertThrowsError(try engine.rebuild())
        XCTAssertEqual(try String(contentsOf: cache.appendingPathComponent("replicatord.sql"), encoding: .utf8), "original-cache")
        let folder = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first!
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("incomplete-new-cache/replicatord.sql"), encoding: .utf8), "incomplete")
        XCTAssertEqual(service.starts, 2)
    }
    func testFailedRestoreRollsBackToCacheFromBeforeRestore() throws {
        let backup = try engine.rebuild()
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
        try Data("current".utf8).write(to: cache.appendingPathComponent("replicatord.sql"))
        service.failNextStart = true
        XCTAssertThrowsError(try engine.restore(backup.url))
        XCTAssertEqual(try String(contentsOf: cache.appendingPathComponent("replicatord.sql"), encoding: .utf8), "current")
        XCTAssertEqual(try String(contentsOf: backup.url.appendingPathComponent("pairing-cache/replicatord.sql"), encoding: .utf8), "original-cache")
    }
    func testRejectsSymlinkCacheBeforeStoppingService() throws {
        let linked = root.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: cache)
        let unsafe = RepairEngine(paths: RepairPaths(cache: linked, backups: backups), service: service)
        XCTAssertThrowsError(try unsafe.rebuild())
        XCTAssertEqual(service.stops, 0)
        XCTAssertEqual(try String(contentsOf: cache.appendingPathComponent("replicatord.sql"), encoding: .utf8), "original-cache")
    }
    func testRejectsForeignOrUnmarkedBackupWithoutStoppingService() throws {
        XCTAssertThrowsError(try engine.restore(root))
        XCTAssertEqual(service.stops, 0)
    }
    func testDiagnosticsDistinguishUnknownFromPermissionDenied() {
        XCTAssertEqual(Diagnostics.parsePairing("Error: Operation not permitted", status: 1), .inaccessible)
        XCTAssertEqual(Diagnostics.parsePairing("no such table: PairingRelationship", status: 1), .unsupported)
        XCTAssertEqual(Diagnostics.parsePairing("1\n", status: 0), .pending)
        XCTAssertEqual(Diagnostics.parsePairing("1\n2\n", status: 0), .paired)
    }
    func testVideoFrameDoesNotRemainConnectedAfterDisconnectOrAppExit() {
        let video = "VideoStream receivedFirstFrame\n"
        XCTAssertTrue(Diagnostics.parseSession(video, appRunning: true))
        XCTAssertFalse(Diagnostics.parseSession(video + "Tearing down the session due to: userQuit\n", appRunning: true))
        XCTAssertFalse(Diagnostics.parseSession(video, appRunning: false))
    }
    func testRepairRecommendationRequiresRepeatedFailureAndPendingPairing() {
        var report = DiagnosticReport(checks: [CheckItem("mac", "This Mac", "desktopcomputer", "Compatible", .pass)], pairing: .pending, hasRepeatedPairingFailure: false, recentFrame: false, osVersion: "test", architecture: "test", checkedAt: Date())
        XCTAssertFalse(report.canRepair)
        report.hasRepeatedPairingFailure = true
        XCTAssertTrue(report.canRepair)
        report.pairing = .paired
        XCTAssertFalse(report.canRepair)
    }
    func testPanelViewportFitsShortAndNarrowDisplays() {
        for size in [CGSize(width: 1440, height: 850), CGSize(width: 1024, height: 560), CGSize(width: 440, height: 390)] {
            let screen = CGRect(origin: .zero, size: size)
            let anchor = CGRect(x: size.width - 25, y: size.height, width: 20, height: 24)
            let viewport = PopoverGeometry.viewport(visibleFrame: screen, anchor: anchor)
            XCTAssertTrue(viewport.width <= size.width - 32)
            XCTAssertTrue(viewport.height <= size.height - 32)
            XCTAssertTrue(viewport.height > 0)
        }
    }
    func testPanelClampsToItsOwnSecondaryScreenWithNegativeOrigin() {
        let screen = CGRect(x: -1600, y: 140, width: 1600, height: 900)
        let frame = CGRect(x: -200, y: 950, width: 484, height: 660)
        let fitted = PopoverGeometry.clamp(frame, to: screen)
        XCTAssertTrue(screen.contains(fitted))
        XCTAssertTrue(fitted.maxX < 0, "The panel must remain on the secondary display")
        XCTAssertEqual(fitted.size, frame.size)
    }
    func testPanelClampsLeftEdgeAndOversizedWindow() {
        let screen = CGRect(x: 300, y: -900, width: 1200, height: 850)
        let oversized = PopoverGeometry.clamp(CGRect(x: -100, y: -1000, width: 1600, height: 1200), to: screen)
        XCTAssertTrue(screen.contains(oversized))
        let leftEdge = PopoverGeometry.clamp(CGRect(x: 250, y: -800, width: 484, height: 660), to: screen)
        XCTAssertTrue(screen.contains(leftEdge))
    }
}

@main enum ChecksMain {
    static func main() {
        let checks: [(String, (RepairTests) throws -> Void)] = [
            ("testRebuildPreservesOriginalAndRestoresWithoutDiscardingCurrentCache", { try $0.testRebuildPreservesOriginalAndRestoresWithoutDiscardingCurrentCache() }),
            ("testFailedServiceStartupRollsBackOriginalAndKeepsFailedNewCache", { try $0.testFailedServiceStartupRollsBackOriginalAndKeepsFailedNewCache() }),
            ("testFailedRestoreRollsBackToCacheFromBeforeRestore", { try $0.testFailedRestoreRollsBackToCacheFromBeforeRestore() }),
            ("testRejectsSymlinkCacheBeforeStoppingService", { try $0.testRejectsSymlinkCacheBeforeStoppingService() }),
            ("testRejectsForeignOrUnmarkedBackupWithoutStoppingService", { try $0.testRejectsForeignOrUnmarkedBackupWithoutStoppingService() }),
            ("testDiagnosticsDistinguishUnknownFromPermissionDenied", { $0.testDiagnosticsDistinguishUnknownFromPermissionDenied() }),
            ("testVideoFrameDoesNotRemainConnectedAfterDisconnectOrAppExit", { $0.testVideoFrameDoesNotRemainConnectedAfterDisconnectOrAppExit() }),
            ("testRepairRecommendationRequiresRepeatedFailureAndPendingPairing", { $0.testRepairRecommendationRequiresRepeatedFailureAndPendingPairing() }),
            ("testPanelViewportFitsShortAndNarrowDisplays", { $0.testPanelViewportFitsShortAndNarrowDisplays() }),
            ("testPanelClampsToItsOwnSecondaryScreenWithNegativeOrigin", { $0.testPanelClampsToItsOwnSecondaryScreenWithNegativeOrigin() }),
            ("testPanelClampsLeftEdgeAndOversizedWindow", { $0.testPanelClampsLeftEdgeAndOversizedWindow() })
        ]
        var failed = 0
        for (name, check) in checks {
            let fixture = RepairTests()
            assertionFailures = []
            do {
                try fixture.setUpWithError()
                try check(fixture)
            } catch { assertionFailures.append(String(describing: error)) }
            do { try fixture.tearDownWithError() } catch { assertionFailures.append("Cleanup failed") }
            if assertionFailures.isEmpty { print("PASS " + name) }
            else { failed += 1; print("FAIL " + name + ": " + assertionFailures.joined(separator: "; ")) }
        }
        print("\(checks.count - failed)/\(checks.count) checks passed. Temporary folders and simulated services only.")
        if failed > 0 { exit(1) }
    }
}
