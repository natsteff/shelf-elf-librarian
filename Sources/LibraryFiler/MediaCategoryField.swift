import SwiftUI
import FilerCore

struct MediaCategoryField: View {
    @EnvironmentObject var m: Model
    private var value: String {
        let values = Set(m.visibleSelected.map { $0.fields.mediaCategory })
        return values.count == 1 ? values.first! : "@mixed"
    }
    var body: some View {
        if m.active.kind == .video {
            VStack(alignment: .leading, spacing: 4) {
                Text("Media Category").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Picker("Media Category", selection: Binding(get: { value }, set: { chosen in
                    if chosen != "@mixed" { m.updateFields { $0.mediaCategory = chosen } }
                })) {
                    if value == "@mixed" { Text("Mixed — choose to replace").tag("@mixed") }
                    Text("Automatic — rules / default").tag("")
                    if !value.isEmpty && value != "@mixed" && !(m.active.mediaCategories ?? []).contains(where: { $0.enabled && $0.name == value }) { Text(value + " (captured or unavailable)").tag(value) }
                    ForEach((m.active.mediaCategories ?? []).filter(\.enabled)) { category in Text(category.name).tag(category.name) }
                }.labelsHidden().disabled(!MediaRouting.enabled(m.active))
                if let item = m.visibleSelected.first {
                    let resolved = MediaRouting.resolve(fields: item.fields, source: item.url, profile: m.active)
                    Text((m.visibleSelected.count > 1 ? "First file: " : "") + resolved.1).font(.caption).foregroundStyle(.secondary)
                    if MediaRouting.enabled(m.active), let category = resolved.0 {
                        Text(category.rootFolder.map { "Destination branch: " + ($0.isEmpty ? "Library root" : $0) } ?? "Destination not mapped — choose its folder in Profile Settings → Media Categories.").font(.caption).foregroundStyle(category.rootFolder == nil ? Color.orange : Color.secondary)
                        if !category.associatedType.isEmpty { Text("Category layout Type: " + category.associatedType).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if !MediaRouting.enabled(m.active) { Text("Optional: enable and map Media Categories in Profile Settings → Build names & folders.").font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}
