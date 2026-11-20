import AppKit
import SwiftUI
import MirrorMateCore

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    let model = MateModel()
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "org.mirrormate.app").first(where: { $0.processIdentifier != getpid() }) {
            existing.activate(); NSApp.terminate(nil); return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "iphone", accessibilityDescription: "MirrorMate")
        statusItem.button?.target = self; statusItem.button?.action = #selector(toggle)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
        model.scan()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.show() }
    }
    @objc func toggle() { if popover.isShown { popover.performClose(nil) } else { show() } }
    func show() { if let button = statusItem.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); NSApp.activate(ignoringOtherApps: true) } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { model.isBusy ? .terminateCancel : .terminateNow }
}

@main enum MirrorMateMain {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
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
