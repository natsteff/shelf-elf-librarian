import SwiftUI
import FilerCore

struct EmbeddedMetadataButton: View {
    let item: Item
    var showLabel = false
    @State private var showing = false
    private var summary: String { item.metadata.summary(fields: item.fields) }
    private var differs: Bool { item.metadata.tags.contains { item.metadata.comparison($0, fields: item.fields) == "Differs from component" } }
    var body: some View {
        if item.metadata.available {
            Button { showing = true } label: {
                if showLabel { Label("View Embedded Metadata…", systemImage: "tag") }
                else { Image(systemName: differs ? "tag.fill" : "tag").font(.system(size: 13)) }
            }
            .buttonStyle(.borderless).foregroundStyle(differs ? Color.orange : Color.secondary)
            .help(summary).accessibilityLabel(summary)
            .popover(isPresented: $showing, arrowEdge: .bottom) { EmbeddedMetadataDetails(item: item) }
        }
    }
}
private struct EmbeddedMetadataDetails: View {
    let item: Item
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Embedded Metadata — Read Only").font(.headline)
            Text(item.url.lastPathComponent).font(.subheadline).textSelection(.enabled)
            Text(item.metadata.video
                 ? "Video metadata fills only missing components used by your masks. Existing values and manual edits take priority."
                 : "Tags are reference information. They do not change filename proposals or components. Edit the proposed filename or Filename Components yourself if needed.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(item.metadata.notes, id: \.self) { note in Text(note).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if item.metadata.tags.isEmpty { Text("No readable embedded tags found.").foregroundStyle(.secondary) }
                    ForEach(item.metadata.tags) { tag in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top) {
                                Text(tag.label).fontWeight(.semibold)
                                Spacer()
                                Text(tag.source + " · " + tag.key).font(.caption).foregroundStyle(.secondary)
                            }
                            let comparison = item.metadata.comparison(tag, fields: item.fields)
                            if tag.component != nil && !tag.binary {
                                Text(comparison).font(.caption).foregroundStyle(comparison == "Differs from component" ? Color.orange : Color.secondary)
                                if let key = tag.component, !FieldCatalog.get(key, item.fields).isEmpty {
                                    Text("Current " + key + " component: " + FieldCatalog.get(key, item.fields)).font(.caption).textSelection(.enabled)
                                }
                            }
                            if tag.value.count > 300 {
                                DisclosureGroup("Show value (\(tag.value.count.formatted()) characters)") { value(tag.value) }
                            } else { value(tag.value) }
                        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
                    }
                }
            }.frame(maxHeight: 380)
            Text("Metadata was read during workspace discovery. Refresh to read external tag changes. No tags are written or removed.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(16).frame(width: 560)
    }
    @ViewBuilder private func value(_ text: String) -> some View {
        Text(String(text.prefix(65_536))).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        if text.count > 65_536 { Text("Display limited to the first 65,536 characters. The original tag is unchanged.").font(.caption).foregroundStyle(.secondary) }
    }
}
