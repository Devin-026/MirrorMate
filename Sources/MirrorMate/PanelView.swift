import SwiftUI
import AppKit
import MirrorMateCore

enum Palette {
    static let background = Color(red: 0.925, green: 0.925, blue: 0.918)
    static let card = Color(red: 0.868, green: 0.868, blue: 0.856)
    static let ink = Color(red: 0.25, green: 0.26, blue: 0.25)
    static let secondary = Color(red: 0.52, green: 0.53, blue: 0.51)
    static let orange = Color(red: 1, green: 0.51, blue: 0.12)
    static let green = Color(red: 0.28, green: 0.56, blue: 0.39)
}

struct PanelView: View {
    @ObservedObject var model: MateModel
    var viewport: CGSize? = nil
    var body: some View {
        VStack(spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            if viewport != nil {
                ScrollView(.vertical) {
                    content
                }
                .scrollIndicators(.automatic)
                .scrollBounceBehavior(.basedOnSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
            }
            footer.fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: viewport?.width ?? 484, height: viewport?.height)
        .background(Palette.background)
        .foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .alert(model.text("Rebuild the pairing cache?"), isPresented: $model.showRepairConfirmation) {
            Button(model.text("Cancel"), role: .cancel) {}
            Button(model.text("Back up & repair"), action: model.repair)
        } message: {
            Text(model.text("MirrorMate will close iPhone Mirroring, save the original cache, and restart the pairing service. iPhone notifications and widgets may need to sync again. You may need to authorize mirroring again. Your Apple Account and network settings will not change."))
        }
        .sheet(isPresented: $model.showBackups) { BackupsView(model: model) }
        .sheet(isPresented: $model.showAbout) { AboutView(model: model) }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
                connectionCard
                VStack(spacing: 0) {
                    sectionLabel(model.text("CONNECTION CHECK")) {
                        Button(action: model.scan) { Label(model.text(model.isBusy ? "Checking" : "Run check"), systemImage: "arrow.clockwise").font(.system(size: 11, weight: .medium)) }
                            .buttonStyle(.plain).disabled(model.isBusy || model.preview).help(model.text("Read-only checks. No settings are changed."))
                    }.padding(.bottom, 8)
                    ForEach(model.checks) { check in checkRow(check) }
                }
                Rectangle().fill(Palette.ink.opacity(0.13)).frame(height: 1)
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel(model.text("REPAIR & RECOVERY")) { Text(model.text("A backup comes first.")).font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars").font(.system(size: 23, weight: .light)).foregroundStyle(model.report?.canRepair == true ? Palette.orange : Palette.secondary).frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.text("Rebuild pairing cache")).font(.system(size: 13, weight: .medium))
                            Text(model.text("For a pairing that never completes")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 0)
                        Button(model.text("Repair…")) { model.showRepairConfirmation = true }.buttonStyle(OrangeButtonStyle()).disabled(model.isBusy || model.report?.canRepair != true)
                            .help(model.text("Available after checks find repeated pairing failures."))
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 21, weight: .light)).foregroundStyle(Palette.secondary).frame(width: 32)
                        Text(model.text("Restore a backup")).font(.system(size: 13))
                        Spacer()
                        Button(model.text("View backups"), action: { model.refreshBackups(); model.showBackups = true }).font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(Palette.secondary).disabled(model.isBusy || model.preview)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.secondary)
                    }.padding(.top, 6)
                }
                if let failure = model.failure {
                    message(model.text(failure), symbol: "exclamationmark.circle", color: .red)
                } else if let notice = model.notice { message(model.text(notice), symbol: "checkmark.circle", color: Palette.green) }
                if model.report?.pairing == .inaccessible {
                    Button(model.text("Allow folder access…"), action: model.allowFolder).buttonStyle(OrangeButtonStyle()).disabled(model.isBusy)
                }
        }.padding(.horizontal, 22).padding(.bottom, 20)
    }
    private var header: some View {
        ZStack {
            Text(model.text("MirrorMate")).font(.system(size: 13, weight: .medium))
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "iphone").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.orange)
                    Image(systemName: "link").font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                HStack(spacing: 14) {
                    Button { model.keepOpen.toggle() } label: {
                        Image(systemName: model.keepOpen ? "pin.fill" : "pin").font(.system(size: 14)).foregroundStyle(model.keepOpen ? Palette.orange : Palette.secondary)
                    }.buttonStyle(.plain)
                        .help(model.text(model.keepOpen ? "Pinned: clicking elsewhere keeps this panel open" : "Unpinned: clicking elsewhere closes this panel"))
                        .accessibilityLabel(model.text("Keep open"))
                        .accessibilityValue(model.text(model.keepOpen ? "On" : "Off"))
                    Button(action: { model.showAbout = true }) { Image(systemName: "gearshape.fill").font(.system(size: 16)) }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help(model.text("Settings"))
                    Button { model.closePanel?() } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)) }.buttonStyle(.plain).foregroundStyle(Palette.secondary).help(model.text("Close panel")).keyboardShortcut("w")
                }
            }
        }.padding(.horizontal, 24).padding(.top, 19).padding(.bottom, 22)
    }
    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13).fill(Palette.orange).frame(width: 44, height: 44)
                    Image(systemName: "iphone").font(.system(size: 25, weight: .light)).foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.text("iPhone Mirroring")).font(.system(size: 15, weight: .semibold))
                    Text(model.title).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
                if model.isBusy { ProgressView().controlSize(.small) }
                else { Image(systemName: model.report?.recentFrame == true ? "checkmark.circle.fill" : "wave.3.right").font(.system(size: 21, weight: .light)).foregroundStyle(model.report?.recentFrame == true ? Palette.green : Palette.secondary) }
            }
            Text(model.detail).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack {
                Circle().fill(model.report?.canRepair == true ? Palette.orange : (model.report?.pairing == .paired ? Palette.green : Palette.secondary.opacity(0.5))).frame(width: 5, height: 5)
                Text(model.report?.canRepair == true ? model.text("Repair available") : model.checkedLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
                Spacer()
                Button(action: model.openMirroring) { HStack(spacing: 5) { Text(model.text("Open mirroring")); Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)) }.font(.system(size: 10, weight: .medium)) }.buttonStyle(.plain).disabled(model.isBusy || model.preview)
            }
        }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
    }
    private func checkRow(_ item: CheckItem) -> some View {
        HStack(spacing: 11) {
            if item.id == "bluetooth" { Text(model.text("ᛒ")).font(.system(size: 24, weight: .light)).foregroundStyle(Palette.secondary).frame(width: 28) }
            else { Image(systemName: item.symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(Palette.secondary).frame(width: 28) }
            Text(model.text(item.title)).font(.system(size: 13))
            Spacer()
            Text(model.text(model.isBusy ? "Checking…" : item.value)).font(.system(size: 12, weight: item.state == .attention ? .medium : .regular)).foregroundStyle(item.state == .attention ? Palette.orange : Palette.secondary)
            Circle().fill(dotColor(item.state)).frame(width: 6, height: 6).padding(.leading, 6)
        }.padding(.horizontal, 5).frame(height: 38)
        .accessibilityElement(children: .combine)
    }
    private func dotColor(_ state: CheckState) -> Color { switch state { case .pass: return Palette.green; case .attention: return Palette.orange; case .fail: return .red; case .unknown: return Palette.secondary.opacity(0.35) } }
    private func sectionLabel<T: View>(_ title: String, @ViewBuilder trailing: () -> T) -> some View {
        HStack { Text(title).font(.system(size: 10, weight: .bold)).tracking(1.7); Spacer(); trailing() }
    }
    private func message(_ text: String, symbol: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 7) { Image(systemName: symbol).foregroundStyle(color); Text(text).foregroundStyle(Palette.secondary).lineSpacing(3) }.font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
    }
    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.ink.opacity(0.13)).frame(height: 1).padding(.horizontal, 22)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 11))
                Text(model.text(model.preview ? "Interface preview · sample results" : "On your Mac. No uploads.")).font(.system(size: 10))
                Spacer(minLength: 4)
                Button(action: model.copyReport) { Image(systemName: "doc.on.doc").font(.system(size: 12)) }.buttonStyle(.plain).disabled(model.report == nil || model.isBusy || model.preview).help(model.text("Copy a report without personal details"))
                Button { NSWorkspace.shared.open(ProjectLinks.repository) } label: { Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 12)) }.buttonStyle(.plain).padding(.horizontal, 6).help(model.text("Source code on GitHub"))
                Button { NSApp.terminate(nil) } label: { Text(model.text("Quit  ⌘Q")).font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5).background(Palette.ink.opacity(0.045), in: Capsule()) }.keyboardShortcut("q").buttonStyle(.plain).disabled(model.isBusy)
            }.foregroundStyle(Palette.secondary).padding(.horizontal, 24).padding(.vertical, 14)
        }
    }
}

struct OrangeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold)).foregroundStyle(enabled ? Color.white : Palette.secondary)
            .padding(.horizontal, 13).padding(.vertical, 8)
            .background(enabled ? Palette.orange.opacity(configuration.isPressed ? 0.75 : 1) : Palette.ink.opacity(0.06), in: Capsule())
    }
}

struct BackupsView: View {
    @ObservedObject var model: MateModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: BackupRecord?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text(model.text("Your backups")).font(.system(size: 20, weight: .semibold)); Spacer(); Button(model.text("Done")) { dismiss() } }
            Text(model.text("Restore a pairing cache saved by MirrorMate. The current cache will also be kept.")).font(.system(size: 12)).foregroundStyle(.secondary)
            if model.backupRecords.isEmpty { ContentUnavailableView(model.text("No backups yet"), systemImage: "clock.arrow.circlepath", description: Text(model.text("MirrorMate makes one before every repair."))) }
            else {
                ScrollView {
                    ForEach(model.backupRecords) { backup in
                        HStack { VStack(alignment: .leading, spacing: 4) { Text(model.backupDate(backup.createdAt)).font(.system(size: 13, weight: .medium)); Text(model.text("Original pairing cache")).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Button(model.text("Restore…")) { selected = backup }.buttonStyle(OrangeButtonStyle()) }.padding(12).background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.frame(maxHeight: 230)
            }
            Button(model.text("Show backup folder"), action: model.showBackupFolder).buttonStyle(.link)
        }.padding(24).frame(width: 420).background(Palette.background)
        .alert(model.text("Restore this backup?"), isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Button(model.text("Cancel"), role: .cancel) { selected = nil }
            Button(model.text("Restore backup")) { if let selected { model.restore(selected) }; selected = nil }
        } message: { Text(model.text("iPhone Mirroring will close and pairing will restart. The current cache will be preserved too.")) }
    }
}

struct AboutView: View {
    @ObservedObject var model: MateModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text(model.text("MirrorMate")).font(.system(size: 24, weight: .semibold)); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.2").font(.system(size: 12)).foregroundStyle(.secondary) }
            Text(model.text("A little help connecting.")).font(.system(size: 15)).foregroundStyle(Palette.orange)
            Divider()
            Picker(model.text("Language"), selection: $model.language) {
                Text(model.text("Follow system")).tag(AppLanguage.system)
                Text("简体中文").tag(AppLanguage.simplifiedChinese)
                Text("English").tag(AppLanguage.english)
            }.pickerStyle(.menu).font(.system(size: 12))
            Toggle(model.text("Keep panel open when clicking elsewhere"), isOn: $model.keepOpen).font(.system(size: 12))
            Divider()
            Text(model.text("A small, independent menu bar companion for iPhone Mirroring. Check your connection, rebuild a stuck pairing cache, and keep a way back.")).font(.system(size: 12)).lineSpacing(4)
            Text(model.text("Checks and repairs run locally. MirrorMate does not upload diagnostics, read your passwords, or sign you out. Repair support is limited to the recognized pairing-cache format; not every connection issue can be repaired.")).font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            HStack { Link(model.text("View source"), destination: ProjectLinks.repository); Spacer(); Button(model.text("Done")) { dismiss() } }.font(.system(size: 12))
        }.padding(28).frame(width: 410).background(Palette.background)
    }
}
