import SwiftUI
import FilerCore

struct EmbeddedMetadataButton: View {
    @EnvironmentObject var m: Model
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
            }.buttonStyle(.borderless).foregroundStyle(differs ? Color.orange : Color.secondary)
                .help(summary).accessibilityLabel(summary)
                .popover(isPresented: $showing, arrowEdge: .bottom) {
                    EmbeddedMetadataDetails(original: item, review: { showing = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { m.reviewTagProposal(item.id) } }).environmentObject(m)
                }
        }
    }
}
private struct EmbeddedMetadataDetails: View {
    @EnvironmentObject var m: Model
    let original: Item
    let review: () -> Void
    private var item: Item { m.items.first { $0.id == original.id } ?? original }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.metadata.video ? "Embedded Video Metadata" : "MP3 Tags & Filename Components").font(.headline)
            Text(item.url.lastPathComponent).font(.subheadline).textSelection(.enabled)
            Text(item.metadata.video ? "Video metadata fills only missing components used by your masks. Existing values and manual edits take priority."
                 : "Use a tag to update this file’s proposed components. The popup stays open so you can choose several values. No file or embedded tag changes until an explicit operation.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(item.metadata.notes, id: \.self) { Text($0).font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
                    if item.metadata.tags.isEmpty { Text("No readable embedded tags found.").foregroundStyle(.secondary) }
                    ForEach(item.metadata.sections(fields: item.fields)) { section in
                        Text(section.title).font(.headline)
                        ForEach(section.tags) { tag in tagRow(tag) }
                    }
                }
            }.frame(maxHeight: 380)
            if !item.metadata.video && item.url.pathExtension.lowercased() == "mp3" {
                Text("Proposed filename: " + ((try? proposedFilename(item, profile: m.active)) ?? "Complete required filename components to build the proposal."))
                    .font(.callout).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if m.tagEditsBefore[item.id] != nil { Button("Discard Tag Choices") { m.cancelTagEdits(item.id) } }
                    Spacer()
                    Button("Review Proposed Filename", action: review)
                }
                Text("Review closes this popup and focuses the filename. Enter renames; Esc restores components and the proposal from before your tag choices.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Text("Refresh after external tag edits. Writing and purging tags are separate Tools actions.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(width: 580)
    }
    private func tagRow(_ tag: EmbeddedTag) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Text(tag.component == "Year" ? "Release Year" : tag.component == "TrackNumber" ? "Track Number" : tag.label).fontWeight(.semibold)
                Spacer(); Text(tag.source + " · " + tag.key).font(.caption).foregroundStyle(.secondary)
            }
            let comparison = item.metadata.comparison(tag, fields: item.fields)
            if tag.component != nil && !tag.binary {
                Text(comparison).font(.caption).foregroundStyle(comparison == "Differs from component" ? Color.orange : Color.secondary)
                if let key = tag.component, !FieldCatalog.get(key, item.fields).isEmpty {
                    Text("Current " + key + " component: " + FieldCatalog.get(key, item.fields)).font(.caption).textSelection(.enabled)
                }
            }
            if tag.value.count > 300 { DisclosureGroup("Show value (\(tag.value.count.formatted()) characters)") { value(tag.value) } }
            else { value(tag.value) }
            if !item.metadata.video, item.url.pathExtension.lowercased() == "mp3", let key = tag.component, (try? EmbeddedMetadata.fieldValue(tag)) != nil {
                Button("Use Tag for " + (key == "TrackNumber" ? "Track Number" : key)) { m.useMP3Tag(tag, for: item.id) }.disabled(m.busy)
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
    }
    @ViewBuilder private func value(_ text: String) -> some View {
        Text(String(text.prefix(65_536))).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        if text.count > 65_536 { Text("Display limited to the first 65,536 characters.").font(.caption).foregroundStyle(.secondary) }
    }
}
