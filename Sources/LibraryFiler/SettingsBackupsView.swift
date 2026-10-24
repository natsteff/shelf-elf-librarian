import SwiftUI
import AppKit
import FilerCore

struct SettingsBackupsView: View {
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [SettingsBackup] = []
    @State private var selected: URL?
    @State private var pending: SettingsArchive?
    @State private var confirm = false
    @State private var validation = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Restore Settings Backup").font(.title2.bold())
            Text("The newest 10 automatic backups contain all profiles and General Settings from before saved changes. Tools → Export Settings remains the primary portable backup method.")
            if entries.isEmpty {
                Text("No automatic backups yet. A backup is created before the next saved configuration change.").foregroundStyle(.secondary)
            }
            List(entries, selection: $selected) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.date.formatted(date: .numeric, time: .standard)).font(.headline)
                    Text("Before: " + entry.reason)
                }.padding(.vertical, 4).tag(entry.url)
            }
            Text("Restore replaces all profiles and General Settings. Your current settings are backed up first. Library files, operation history and remembered corrections are unchanged.").font(.callout)
            if !validation.isEmpty { Text(validation).foregroundStyle(.red).textSelection(.enabled) }
            HStack {
                Button("Show Backups in Finder") {
                    NSWorkspace.shared.open(SettingsBackupStore(support: m.support).directory)
                }.disabled(entries.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Restore…") {
                    guard let selected else { return }
                    do { pending = try SettingsBackupStore(support: m.support).read(selected); confirm = true }
                    catch { validation = error.localizedDescription }
                }.disabled(selected == nil || m.busy)
            }
        }.padding(20).frame(width: 720, height: 540)
        .onAppear {
            do { entries = try SettingsBackupStore(support: m.support).entries(); selected = entries.first?.url }
            catch { validation = error.localizedDescription }
        }
        .alert("Replace current profiles and General Settings?", isPresented: $confirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore Settings", role: .destructive) {
                guard let pending else { return }
                do { try m.replaceSettings(pending, reason: "Restore automatic backup", statusText: "Settings restored"); dismiss() }
                catch { validation = error.localizedDescription }
            }
        } message: {
            Text("Restore the snapshot from " + (pending?.created.formatted(date: .numeric, time: .standard) ?? "the selected backup") + ". Your current configuration will be backed up before replacement.")
        }
    }
}
