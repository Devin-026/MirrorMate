import AppKit
import SwiftUI
import MirrorMateCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let layoutProbe = CommandLine.arguments.contains("--check-popover")
    let model = MateModel(preview: CommandLine.arguments.contains("--check-popover"))
    var panelController: NSHostingController<PanelView>!
    func applicationDidFinishLaunching(_ notification: Notification) {
        if !layoutProbe, let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "org.mirrormate.app").first(where: { $0.processIdentifier != getpid() }) {
            existing.activate(); NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "MirrorMate")
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        panelController = NSHostingController(rootView: PanelView(model: model, viewport: CGSize(width: 484, height: 660)))
        // The viewport, rather than SwiftUI's changing content, owns the window size.
        panelController.sizingOptions = []
        popover.contentViewController = panelController
        if !layoutProbe { model.scan() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.show()
            if self?.layoutProbe == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.checkPresentedLayout() }
            }
        }
    }
    @objc func toggle() { if popover.isShown { popover.performClose(nil) } else { show() } }
    func show() {
        guard let button = statusItem.button, let anchorWindow = button.window else { return }
        let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) ?? anchorWindow.screen ?? NSScreen.main else { return }
        let size = PopoverGeometry.viewport(visibleFrame: screen.visibleFrame, anchor: anchor)
        panelController.rootView = PanelView(model: model, viewport: size)
        panelController.preferredContentSize = size
        panelController.view.setFrameSize(size)
        popover.contentSize = size
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        panelController.view.layoutSubtreeIfNeeded()
        if let window = panelController.view.window {
            let fitted = PopoverGeometry.clamp(window.frame, to: screen.visibleFrame)
            if fitted != window.frame { window.setFrame(fitted, display: true) }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    func checkPresentedLayout() {
        guard let window = panelController.view.window, let screen = window.screen else { fputs("FAIL popover did not appear\n", stderr); exit(1) }
        let size = panelController.view.bounds.size
        let expected = popover.contentSize
        let fits = screen.visibleFrame.contains(window.frame)
        let contentFits = abs(size.width - expected.width) < 1 && abs(size.height - expected.height) < 1
        print("\(fits && contentFits ? "PASS" : "FAIL") native menu bar popover: window \(window.frame), content \(size), viewport \(expected)")
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--check-popover"), index + 1 < args.count, !args[index + 1].hasPrefix("--"),
           let bitmap = panelController.view.bitmapImageRepForCachingDisplay(in: panelController.view.bounds) {
            panelController.view.cacheDisplay(in: panelController.view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: URL(fileURLWithPath: args[index + 1])) }
        }
        popover.performClose(nil)
        if !fits || !contentFits { exit(1) }
        NSApp.terminate(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model.isBusy ? .terminateCancel : .terminateNow }
}

@main enum MirrorMateMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--check-layout") {
            LayoutChecks.run()
            return
        }
        if let index = arguments.firstIndex(of: "--diagnose") {
            _ = index
            print(Diagnostics().run().shareableText)
            return
        }
        if let index = arguments.firstIndex(of: "--render-preview"), arguments.count > index + 1 {
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.prohibited)
            let renderer = ImageRenderer(content: PanelView(model: MateModel(preview: true)))
            renderer.scale = 2
            if let image = renderer.cgImage, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
                do { try png.write(to: URL(fileURLWithPath: arguments[index + 1])); print("Preview written.") }
                catch { fputs("Could not write preview.\n", stderr); exit(1) }
            } else { fputs("Could not render preview.\n", stderr); exit(1) }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
