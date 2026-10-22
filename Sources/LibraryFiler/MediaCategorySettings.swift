import SwiftUI
import AppKit
import FilerCore

struct MediaCategorySettings: View {
    @Binding var profile: Profile
    @Binding var validation: String
    @State private var removal: UUID?
    private var categories: Binding<[MediaCategory]> { Binding(get: { profile.mediaCategories ?? [] }, set: { profile.mediaCategories = $0 }) }
    private var defaultChoice: Binding<String> {
        Binding(get: { profile.defaultMediaCategoryID?.uuidString ?? "" }, set: { profile.defaultMediaCategoryID = UUID(uuidString: $0) })
    }
    var body: some View {
        Toggle("Route videos using Media Categories", isOn: Binding(get: { profile.mediaRoutingEnabled ?? false }, set: { profile.mediaRoutingEnabled = $0 }))
        SettingsHint(text: "Type describes the video’s structure. Media Category maps it to your actual library folder, such as Films, Kid Movies or Television. Folder names are never inferred from existing directories. When off, the original Type/profile masks remain in use.")
        if profile.mediaRoutingEnabled == true {
            Picker("When no rule matches", selection: defaultChoice) {
                Text("Needs review — no default").tag("")
                if let id = profile.defaultMediaCategoryID, !(profile.mediaCategories ?? []).contains(where: { $0.id == id && $0.enabled }) { Text("Unavailable default — choose another or Needs review").tag(id.uuidString) }
                ForEach((profile.mediaCategories ?? []).filter(\.enabled)) { category in Text("Use “" + category.name + "”").tag(category.id.uuidString) }
            }
            SettingsHint(text: "An explicit selection or captured {MediaCategory} wins. Type + keyword rules run first, then keyword-only, then Type-only. Category and rule order break ties. Unmapped categories always require review, including the default.")
        }
        ForEach(categories) { $category in
            DisclosureGroup {
                Toggle("Category enabled", isOn: $category.enabled)
                TextField("Category name", text: $category.name)
                TextField("Aliases (comma separated)", text: $category.aliases)
                destination($category)
                Picker("Layout Type", selection: $category.associatedType) {
                    Text("Use the file’s Type").tag("")
                    if !category.associatedType.isEmpty && !(profile.classifications ?? []).contains(where: { $0.name == category.associatedType }) { Text(category.associatedType + " (unconfigured)").tag(category.associatedType) }
                    ForEach(profile.classifications ?? []) { type in Text(type.name).tag(type.name) }
                }
                SettingsHint(text: "This Type selects the layout for files routed here. It does not identify the category by itself; add matching rules below.")
                Toggle("Custom subfolder layout", isOn: Binding(get: { category.folderMask != nil }, set: { category.folderMask = $0 ? "" : nil }))
                if category.folderMask != nil {
                    TextField("Subfolder mask (blank = none)", text: Binding(get: { category.folderMask ?? "" }, set: { category.folderMask = $0 }))
                } else { Text("Inherits the full Type/profile folder mask. Remove any old category prefix there to avoid nesting it again.").font(.caption).foregroundStyle(.secondary) }
                Toggle("Custom filename layout", isOn: Binding(get: { category.filenameMask != nil }, set: { category.filenameMask = $0 ? profile.filenameMask : nil }))
                if category.filenameMask != nil { TextField("Filename mask (without extension)", text: Binding(get: { category.filenameMask ?? "" }, set: { category.filenameMask = $0 })) }
                Text("Matching rules (any rule may match)").font(.caption.bold())
                ForEach($category.rules) { $rule in
                    VStack(alignment: .leading, spacing: 5) {
                        Picker("Type condition", selection: $rule.type) {
                            Text("Any Type").tag("")
                            if !rule.type.isEmpty && !(profile.classifications ?? []).contains(where: { $0.name == rule.type }) { Text(rule.type + " (unconfigured)").tag(rule.type) }
                            ForEach(profile.classifications ?? []) { type in Text(type.name).tag(type.name) }
                        }
                        TextField("Filename keyword or phrase (optional)", text: $rule.keyword)
                        Text("Both conditions must match when supplied. A rule with neither condition is ignored.").font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("↑") { moveRule(category.id, rule.id, -1) }
                            Button("↓") { moveRule(category.id, rule.id, 1) }
                            Button("Remove Rule") { category.rules.removeAll { $0.id == rule.id } }
                        }.controlSize(.small)
                    }.padding(.vertical, 4)
                }
                Button("Add Matching Rule") { category.rules.append(MediaCategoryRule()) }
                HStack {
                    Button("Move Category Up") { moveCategory(category.id, -1) }
                    Button("Move Category Down") { moveCategory(category.id, 1) }
                    Spacer()
                    Button("Remove Category…", role: .destructive) { removal = category.id }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(category.name.isEmpty ? "Unnamed Category" : category.name).fontWeight(.medium)
                    Text((category.enabled ? "" : "Disabled • ") + (category.rootFolder.map { $0.isEmpty ? "Library root" : $0 } ?? "Destination not mapped")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        HStack {
            Button("Add Media Category") { categories.wrappedValue.append(MediaCategory(uniqueName(), folderMask: "")) }
            Button("Add Missing Starter Categories") {
                let existing = profile.mediaCategories ?? []
                categories.wrappedValue += MediaRouting.starters.filter { entry in !existing.contains { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame } }
            }
        }
        Button("Add explicit {MediaCategory} input patterns") { addCapturePatterns() }
        SettingsHint(text: "Example input: {Title} ({Year}) [{MediaCategory}]. It reads the marker from the filename; your output mask can omit it. Renaming or removing a category never renames or deletes library folders/files. Multiple categories may share one folder. No folders are created until Apply.")
        .onAppear { if profile.mediaCategories == nil { profile.mediaCategories = MediaRouting.starters } }
        .alert("Remove this Media Category?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("Remove Category", role: .destructive) {
                if let id = removal {
                    categories.wrappedValue.removeAll { $0.id == id }
                    if profile.defaultMediaCategoryID == id { profile.defaultMediaCategoryID = nil }
                }
                removal = nil
            }
            Button("Cancel", role: .cancel) { removal = nil }
        } message: { Text("Only this profile’s configuration is removed. Library folders and files are untouched. Explicit references to this category will need review.") }
    }
    @ViewBuilder private func destination(_ category: Binding<MediaCategory>) -> some View {
        TextField("Root-level folder name", text: Binding(get: { category.wrappedValue.rootFolder ?? "" }, set: { category.wrappedValue.rootFolder = $0.isEmpty ? nil : $0 }))
        HStack {
            Button("Choose Existing Folder…") {
                guard !profile.root.isEmpty else { validation = "Choose the library Destination Root before mapping Media Categories."; return }
                let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                panel.directoryURL = URL(fileURLWithPath: profile.root)
                WindowPresentation.choose(panel) { response in
                    guard response == .OK, let url = panel.url else { return }
                    let root = URL(fileURLWithPath: profile.root).standardizedFileURL
                    if url.standardizedFileURL == root { category.wrappedValue.rootFolder = "" }
                    else if url.deletingLastPathComponent().standardizedFileURL == root { category.wrappedValue.rootFolder = url.lastPathComponent }
                    else { validation = "Choose the library root itself or one of its direct child folders. Category mappings must stay inside the library root." }
                }
            }.disabled(profile.root.isEmpty)
            Button("Use Library Root") { category.wrappedValue.rootFolder = "" }
            Button("Clear Mapping") { category.wrappedValue.rootFolder = nil }
        }.controlSize(.small)
        SettingsHint(text: "Choose an existing direct child folder or enter the root-level folder name to create on Apply. Use Library Root is an explicit mapping; blank/unmapped is not a fallback. Subfolder masks are applied beneath this folder.")
    }
    private func uniqueName() -> String {
        var i = 1
        while (profile.mediaCategories ?? []).contains(where: { $0.name.caseInsensitiveCompare("New Category \(i)") == .orderedSame }) { i += 1 }
        return "New Category \(i)"
    }
    private func moveCategory(_ id: UUID, _ offset: Int) {
        guard var list = profile.mediaCategories, let i = list.firstIndex(where: { $0.id == id }), list.indices.contains(i + offset) else { return }
        list.swapAt(i, i + offset); profile.mediaCategories = list
    }
    private func moveRule(_ category: UUID, _ rule: UUID, _ offset: Int) {
        guard var list = profile.mediaCategories, let c = list.firstIndex(where: { $0.id == category }), let i = list[c].rules.firstIndex(where: { $0.id == rule }), list[c].rules.indices.contains(i + offset) else { return }
        list[c].rules.swapAt(i, i + offset); profile.mediaCategories = list
    }
    private func addCapturePatterns() {
        var rules = profile.workspacePatterns ?? []
        let candidates = [WorkspacePattern("{Title} ({Year}) [{MediaCategory}]"), WorkspacePattern("{Title} [{MediaCategory}]")]
        let index = rules.firstIndex { $0.compatibility || $0.pattern == "{ParenthesizedYearAnywhere}" || $0.pattern == "{Title} [{Type}]" || $0.pattern == "{Title}" } ?? rules.count
        rules.insert(contentsOf: candidates.filter { candidate in !rules.contains { $0.pattern == candidate.pattern } }, at: index)
        profile.workspacePatterns = rules
    }
}
