import SwiftUI
import FilerCore

struct GroupedPlanRows: View {
    let plan: Plan
    var included: Binding<Set<UUID>>?
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(OperationPresentation.groups(plan)) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(group.title, systemImage: group.blocked ? "exclamationmark.triangle" : "folder")
                                .font(.headline).foregroundStyle(group.blocked ? Color.orange : Color.primary)
                            Spacer()
                            Text("\(group.rows.count) \(group.rows.count == 1 ? "file" : "files")").font(.caption).foregroundStyle(.secondary)
                        }.textSelection(.enabled)
                        ForEach(group.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    if let included {
                                        Toggle(row.status, isOn: Binding(get: { included.wrappedValue.contains(row.id) }, set: { selected in
                                            if selected { included.wrappedValue.insert(row.id) } else { included.wrappedValue.remove(row.id) }
                                        })).disabled(!row.actionable)
                                    } else {
                                        Text(row.actionable ? "Ready" : "Blocked: " + row.status).fontWeight(.medium).foregroundStyle(row.actionable ? Color.primary : Color.orange)
                                    }
                                    Spacer()
                                    if !row.group.isEmpty { Text("Group: " + row.group).font(.caption).foregroundStyle(.secondary) }
                                }
                                Text("Source: " + row.source)
                                if !row.destination.isEmpty { Text("Destination: " + row.destination).fontWeight(.medium) }
                                if let recipe = row.magicMP3 {
                                    if recipe.changes.isEmpty { Text("MP3 steps checked: no tag changes needed.").font(.caption).foregroundStyle(.secondary) }
                                    else { Text(recipe.changes.joined(separator: "\n")).font(.caption).foregroundStyle(.secondary) }
                                }
                                if included != nil && !row.newFolders.isEmpty { Text("New folders (created only on Apply):\n" + row.newFolders.joined(separator: "\n")).font(.caption).foregroundStyle(.blue) }
                                if !row.actionable || included != nil { Text(row.explanation).font(.caption).foregroundStyle(.secondary) }
                            }.textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }
            }
        }
    }
}
