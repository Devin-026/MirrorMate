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
        .alert("Rebuild the pairing cache?", isPresented: $model.showRepairConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Back up & repair", action: model.repair)
        } message: {
            Text("MirrorMate will close iPhone Mirroring, save the original cache, and restart the pairing service. iPhone notifications and widgets may need to sync again. You may need to authorize mirroring again. Your Apple Account and network settings will not change.")
        }
        .sheet(isPresented: $model.showBackups) { BackupsView(model: model) }
        .sheet(isPresented: $model.showAbout) { AboutView() }
    }
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
                connectionCard
                VStack(spacing: 0) {
                    sectionLabel("CONNECTION CHECK") {
                        Button(action: model.scan) { Label(model.isBusy ? "Checking" : "Run check", systemImage: "arrow.clockwise").font(.system(size: 11, weight: .medium)) }
                            .buttonStyle(.plain).disabled(model.isBusy || model.preview).help("Read-only checks. No settings are changed.")
                    }.padding(.bottom, 8)
                    ForEach(model.checks) { check in checkRow(check) }
                }
                Rectangle().fill(Palette.ink.opacity(0.13)).frame(height: 1)
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("REPAIR & RECOVERY") { Text("A backup comes first.").font(.system(size: 10)).foregroundStyle(Palette.secondary) }
                    HStack(spacing: 12) {
                        Image(systemName: "wand.and.stars").font(.system(size: 23, weight: .light)).foregroundStyle(model.report?.canRepair == true ? Palette.orange : Palette.secondary).frame(width: 32)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Rebuild pairing cache").font(.system(size: 13, weight: .medium))
                            Text("For a pairing that never completes").font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                        Spacer(minLength: 0)
                        Button("Repair…") { model.showRepairConfirmation = true }.buttonStyle(OrangeButtonStyle()).disabled(model.isBusy || model.report?.canRepair != true)
                            .help("Available after checks find repeated pairing failures.")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 21, weight: .light)).foregroundStyle(Palette.secondary).frame(width: 32)
                        Text("Restore a backup").font(.system(size: 13))
                        Spacer()
                        Button("View backups", action: { model.refreshBackups(); model.showBackups = true }).font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(Palette.secondary).disabled(model.isBusy || model.preview)
                        Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.secondary)
                    }.padding(.top, 6)
                }
                if let failure = model.failure {
                    message(failure, symbol: "exclamationmark.circle", color: .red)
                } else if let notice = model.notice { message(notice, symbol: "checkmark.circle", color: Palette.green) }
                if model.report?.pairing == .inaccessible {
                    Button("Allow folder access…", action: model.allowFolder).buttonStyle(OrangeButtonStyle()).disabled(model.isBusy)
                }
        }.padding(.horizontal, 22).padding(.bottom, 20)
    }
    private var header: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "iphone").font(.system(size: 16, weight: .medium)).foregroundStyle(Palette.orange)
                Image(systemName: "link").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }.frame(width: 42, alignment: .leading)
            Spacer()
            Text("MirrorMate").font(.system(size: 13, weight: .medium))
            Spacer()
            Button(action: { model.showAbout = true }) { Image(systemName: "gearshape.fill").font(.system(size: 16)) }.buttonStyle(.plain).foregroundStyle(Palette.secondary).frame(width: 42, alignment: .trailing).help("About MirrorMate")
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
                    Text("iPhone Mirroring").font(.system(size: 15, weight: .semibold))
                    Text(model.title).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
                if model.isBusy { ProgressView().controlSize(.small) }
                else { Image(systemName: model.report?.recentFrame == true ? "checkmark.circle.fill" : "wave.3.right").font(.system(size: 21, weight: .light)).foregroundStyle(model.report?.recentFrame == true ? Palette.green : Palette.secondary) }
            }
            Text(model.detail).font(.system(size: 11.5)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            HStack {
                Circle().fill(model.report?.canRepair == true ? Palette.orange : (model.report?.pairing == .paired ? Palette.green : Palette.secondary.opacity(0.5))).frame(width: 5, height: 5)
                Text(model.report?.canRepair == true ? "Repair available" : model.checkedLabel).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.secondary)
                Spacer()
                Button(action: model.openMirroring) { HStack(spacing: 5) { Text("Open mirroring"); Image(systemName: "arrow.up.right").font(.system(size: 8, weight: .bold)) }.font(.system(size: 10, weight: .medium)) }.buttonStyle(.plain).disabled(model.isBusy || model.preview)
            }
        }.padding(16).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
    }
    private func checkRow(_ item: CheckItem) -> some View {
        HStack(spacing: 11) {
            if item.id == "bluetooth" { Text("ᛒ").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.secondary).frame(width: 28) }
            else { Image(systemName: item.symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(Palette.secondary).frame(width: 28) }
            Text(item.title).font(.system(size: 13))
            Spacer()
            Text(model.isBusy ? "Checking…" : item.value).font(.system(size: 12, weight: item.state == .attention ? .medium : .regular)).foregroundStyle(item.state == .attention ? Palette.orange : Palette.secondary)
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
                Text(model.preview ? "Interface preview · sample results" : "On your Mac. No uploads.").font(.system(size: 10))
                Spacer(minLength: 4)
                Button(action: model.copyReport) { Image(systemName: "doc.on.doc").font(.system(size: 12)) }.buttonStyle(.plain).disabled(model.report == nil || model.isBusy || model.preview).help("Copy a report without personal details")
                Button { NSWorkspace.shared.open(ProjectLinks.repository) } label: { Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 12)) }.buttonStyle(.plain).padding(.horizontal, 6).help("Source code on GitHub")
                Button { NSApp.terminate(nil) } label: { Text("Quit  ⌘Q").font(.system(size: 10, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 5).background(Palette.ink.opacity(0.045), in: Capsule()) }.keyboardShortcut("q").buttonStyle(.plain).disabled(model.isBusy)
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
            HStack { Text("Your backups").font(.system(size: 20, weight: .semibold)); Spacer(); Button("Done") { dismiss() } }
            Text("Restore a pairing cache saved by MirrorMate. The current cache will also be kept.").font(.system(size: 12)).foregroundStyle(.secondary)
            if model.backupRecords.isEmpty { ContentUnavailableView("No backups yet", systemImage: "clock.arrow.circlepath", description: Text("MirrorMate makes one before every repair.")) }
            else {
                ScrollView {
                    ForEach(model.backupRecords) { backup in
                        HStack { VStack(alignment: .leading, spacing: 4) { Text(backup.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 13, weight: .medium)); Text("Original pairing cache").font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Button("Restore…") { selected = backup }.buttonStyle(OrangeButtonStyle()) }.padding(12).background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
                    }
                }.frame(maxHeight: 230)
            }
            Button("Show backup folder", action: model.showBackupFolder).buttonStyle(.link)
        }.padding(24).frame(width: 420).background(Palette.background)
        .alert("Restore this backup?", isPresented: Binding(get: { selected != nil }, set: { if !$0 { selected = nil } })) {
            Button("Cancel", role: .cancel) { selected = nil }
            Button("Restore backup") { if let selected { model.restore(selected) }; selected = nil }
        } message: { Text("iPhone Mirroring will close and pairing will restart. The current cache will be preserved too.") }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Text("MirrorMate").font(.system(size: 24, weight: .semibold)); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1").font(.system(size: 12)).foregroundStyle(.secondary) }
            Text("A little help connecting.").font(.system(size: 15)).foregroundStyle(Palette.orange)
            Text("A small, independent menu bar companion for iPhone Mirroring. Check your connection, rebuild a stuck pairing cache, and keep a way back.").font(.system(size: 12)).lineSpacing(4)
            Text("Checks and repairs run locally. MirrorMate does not upload diagnostics, read your passwords, or sign you out. Repair support is limited to the recognized pairing-cache format; not every connection issue can be repaired.").font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
            HStack { Link("View source", destination: ProjectLinks.repository); Spacer(); Button("Done") { dismiss() } }.font(.system(size: 12))
        }.padding(28).frame(width: 410).background(Palette.background)
    }
}
