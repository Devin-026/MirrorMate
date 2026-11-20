import AppKit
import SwiftUI
import MirrorMateCore

@MainActor enum LayoutChecks {
    static func run() {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        var failures = 0
        let storedLanguage = UserDefaults.standard.string(forKey: "InterfaceLanguage")
        let storedPin = UserDefaults.standard.object(forKey: "KeepPanelOpen") as? Bool
        for language in [AppLanguage.english, .simplifiedChinese] {
          for size in [CGSize(width: 484, height: 660), CGSize(width: 484, height: 400), CGSize(width: 360, height: 310)] {
            let model = MateModel(preview: true, languageOverride: language)
            let host = NSHostingController(rootView: PanelView(model: model, viewport: size))
            host.sizingOptions = []
            host.preferredContentSize = size
            let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentViewController = host
            window.setContentSize(size)
            host.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            model.failure = String(repeating: "A longer diagnostic message should scroll instead of resizing the panel. ", count: 8)
            host.view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            let actual = host.view.bounds.size
            let matches = abs(actual.width - size.width) < 1 && abs(actual.height - size.height) < 1
            if !matches { failures += 1 }
            print("\(matches ? "PASS" : "FAIL") \(language.rawValue) hosted viewport \(Int(size.width))x\(Int(size.height)); after long message: \(Int(actual.width))x\(Int(actual.height))")
            model.language = language == .english ? .simplifiedChinese : .english
            let changed = model.title == (language == .english ? "配对卡住了" : "Pairing is stuck")
            if !changed { failures += 1 }
            model.keepOpen.toggle()
            window.orderOut(nil)
          }
        }
        if storedLanguage != UserDefaults.standard.string(forKey: "InterfaceLanguage") || storedPin != (UserDefaults.standard.object(forKey: "KeepPanelOpen") as? Bool) { failures += 1; print("FAIL preview modified user preferences") }
        else { print("PASS language switches live; preview checks did not change saved preferences") }
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            let anchor = CGRect(x: visible.maxX - 25, y: visible.maxY, width: 20, height: 24)
            let size = PopoverGeometry.viewport(visibleFrame: visible, anchor: anchor)
            let fitted = PopoverGeometry.clamp(CGRect(x: anchor.midX - size.width / 2, y: anchor.minY - size.height, width: size.width, height: size.height), to: visible)
            let fits = visible.contains(fitted)
            if !fits { failures += 1 }
            print("\(fits ? "PASS" : "FAIL") current display \(Int(visible.width))x\(Int(visible.height)); panel \(Int(size.width))x\(Int(size.height))")
        }
        print("No mirroring, pairing, or network settings were changed.")
        if failures > 0 { exit(1) }
    }
}
