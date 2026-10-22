import SwiftUI
import FilerCore

struct MP3TagReviewView: View {
    @EnvironmentObject var m: Model
    @State private var selected = Set<UUID>()
    @State private var confirm = false
    private var changes: Int { selected.count }
    private var fileCount: Int { m.mp3TagPlan?.files.filter { file in file.changes.contains { selected.contains($0.id) } }.count ?? 0 }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let plan = m.mp3TagPlan {
                Text(plan.action == .update ? "Update MP3 Tags from Filename Components" : "Purge Other MP3 Tags").font(.title2.bold())
                Text("Music profile: " + plan.profileName).font(.headline)
                Text(plan.action == .update ? "Current Filename Components supply the new tag values. Blank components never erase tags. Filenames, unrelated tags and artwork stay unchanged. No Magic analysis is run."
                     : "Only unchecked keep-list tags are offered for removal. Filenames and audio remain unchanged.")
                if plan.action == .purge { Text("Keep: " + MP3KeepTag.allCases.filter { plan.keep.contains($0) }.map(\.label).joined(separator: ", ")).font(.callout).foregroundStyle(.secondary) }
                Text("No Undo or retained file backup is available for these tag changes.").font(.callout.bold()).foregroundStyle(.orange)
                HStack { Button("Select All") { selected = Set(plan.files.filter { $0.blocked == nil }.flatMap(\.changes).map(\.id)) }; Button("Select None") { selected = [] }; Spacer(); Text("\(changes) changes in \(fileCount) files") }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(plan.files) { file in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Toggle(file.url.lastPathComponent, isOn: Binding(get: { !file.changes.isEmpty && file.changes.allSatisfy { selected.contains($0.id) } }, set: { include in
                                        let ids = Set(file.changes.map(\.id)); if include { selected.formUnion(ids) } else { selected.subtract(ids) }
                                    })).font(.headline).disabled(file.blocked != nil || file.changes.isEmpty)
                                    Spacer()
                                }
                                Text(file.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if let blocked = file.blocked { Text("Blocked: " + blocked).foregroundStyle(.orange) }
                                else if file.changes.isEmpty { Text(plan.action == .purge ? "Nothing to remove with this keep list." : "No tag discrepancies or missing component tags.").foregroundStyle(.secondary) }
                                ForEach(file.changes) { change in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Toggle(change.label, isOn: Binding(get: { selected.contains(change.id) }, set: { value in if value { selected.insert(change.id) } else { selected.remove(change.id) } }))
                                        Text("Current: " + String(change.before.prefix(4096))).font(.callout).textSelection(.enabled)
                                        Text("After: " + String(change.after.prefix(4096))).font(.callout.bold()).textSelection(.enabled)
                                        if change.before.count > 4096 || change.after.count > 4096 { Text("Display shortened; the selected tag’s complete value is affected.").font(.caption).foregroundStyle(.secondary) }
                                    }.padding(.leading, 20)
                                }
                            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        }
                        if !plan.skipped.isEmpty { DisclosureGroup("\(plan.skipped.count) selected non-MP3 files skipped") { ForEach(plan.skipped, id: \.self) { Text($0) } } }
                    }
                }
                HStack {
                    Button("Cancel") { m.showMP3Tags = false; m.mp3TagPlan = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button(plan.action == .update ? "Update Selected Tags…" : "Purge Selected Tags…") { confirm = true }.disabled(selected.isEmpty)
                }
            }
        }.padding(20).frame(width: 820, height: 650)
            .onAppear { selected = Set(m.mp3TagPlan?.files.filter { $0.blocked == nil }.flatMap(\.changes).map(\.id) ?? []) }
            .alert(m.mp3TagPlan?.action == .update ? "Update MP3 tags?" : "Remove selected MP3 tags?", isPresented: $confirm) {
                Button("Cancel", role: .cancel) {}
                Button(m.mp3TagPlan?.action == .update ? "Update Tags" : "Remove Tags", role: .destructive) { m.applyMP3Tags(selected) }
            } message: { Text("Apply \(changes) tag changes to \(fileCount) MP3 files? Audio is preserved. There is no Undo or retained backup.") }
    }
}
