import SwiftUI
import AppKit
import FilerCore

struct MediaCategorySettings: View {
    @Binding var profile: Profile
    @Binding var validation: String
    @State private var removal: UUID?
    @State private var editor: Editor?
    private enum Editor: Identifiable {
        case folder(UUID), advanced(UUID), add
        var id: String {
            switch self {
            case .folder(let id): return "folder-" + id.uuidString
            case .advanced(let id): return "advanced-" + id.uuidString
            case .add: return "add"
            }
        }
    }
    private var categories: Binding<[MediaCategory]> { Binding(get: { profile.mediaCategories ?? [] }, set: { profile.mediaCategories = $0 }) }
    private var defaultChoice: Binding<String> {
        Binding(get: { profile.unmatchedMediaUseLibraryRoot == true ? "@root" : (profile.defaultMediaCategoryID?.uuidString ?? "") }, set: { value in profile.unmatchedMediaUseLibraryRoot = value == "@root"; profile.defaultMediaCategoryID = UUID(uuidString: value) })
    }
    var body: some View {
        Toggle("Sort videos into Media Category folders", isOn: Binding(get: { profile.mediaRoutingEnabled ?? false }, set: { profile.mediaRoutingEnabled = $0 }))
        SettingsHint(text: "Choose the library folder for each category. Existing folders are reused; missing folders are created only when a filing operation is applied.")
        HStack {
            Text("Media Category").frame(width: 125, alignment: .leading)
            Text("Library folder").frame(maxWidth: .infinity, alignment: .leading)
            Spacer().frame(width: 210)
        }.font(.caption).foregroundStyle(.secondary)
        ForEach(profile.mediaCategories ?? []) { category in
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name.isEmpty ? "Unnamed Category" : category.name).lineLimit(2)
                    if !category.enabled { Text("Off").font(.caption).foregroundStyle(.secondary) }
                }.frame(width: 125, alignment: .leading)
                Text(category.rootFolder.map { $0.isEmpty ? "Library root" : $0 } ?? "Not chosen")
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(category.rootFolder == nil ? Color.secondary : Color.primary)
                    .instantHelp(category.rootFolder.map { $0.isEmpty ? profile.root : URL(fileURLWithPath: profile.root).appendingPathComponent($0).path } ?? "Choose a destination folder for this category")
                Button(category.rootFolder == nil ? "Choose…" : "Change…") { editor = .folder(category.id) }.fixedSize()
                Button("Advanced…") { editor = .advanced(category.id) }.fixedSize()
                Button("Remove…") { removal = category.id }.fixedSize()
            }.controlSize(.small).padding(.vertical, 3)
        }
        HStack {
            Button("Add Category…") { editor = .add }
            Spacer()
            Menu("Advanced Setup") {
                Button("Add Missing Starter Categories") { addMissingStarters() }
                Button("Add {MediaCategory} Input Patterns") { addCapturePatterns() }
            }.fixedSize()
        }
        Picker("Unmatched videos", selection: defaultChoice) {
            Text("Needs review").tag("")
            if let id = profile.defaultMediaCategoryID, !(profile.mediaCategories ?? []).contains(where: { $0.id == id && $0.enabled }) { Text("Unavailable default — choose another").tag(id.uuidString) }
            ForEach((profile.mediaCategories ?? []).filter(\.enabled)) { category in Text("Use “" + category.name + "”").tag(category.id.uuidString) }
            Text("Use Library Root").tag("@root")
        }
        SettingsHint(text: "Starter categories already include recognition and naming defaults. Use Advanced only to customize them. Removing a category never deletes library folders or files.")
            .onAppear { if profile.mediaCategories == nil { profile.mediaCategories = MediaRouting.starters } }
            .sheet(item: $editor) { selection in
                switch selection {
                case .folder(let id):
                    if let i = profile.mediaCategories?.firstIndex(where: { $0.id == id }) { CategoryFolderEditor(category: categories[i], libraryRoot: profile.root) }
                case .advanced(let id):
                    if let i = profile.mediaCategories?.firstIndex(where: { $0.id == id }) { advancedEditor(categories[i]) }
                case .add:
                    AddMediaCategoryView(existing: profile.mediaCategories ?? []) { category in categories.wrappedValue.append(category) }
                }
            }
            .alert("Remove this Media Category?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
                Button("Remove Category", role: .destructive) {
                    if let id = removal {
                        categories.wrappedValue.removeAll { $0.id == id }
                        if profile.defaultMediaCategoryID == id { profile.defaultMediaCategoryID = nil }
                    }
                    removal = nil
                }
                Button("Cancel", role: .cancel) { removal = nil }
            } message: { Text("Only its settings are removed. Library folders and files are untouched.") }
    }
    private func advancedEditor(_ binding: Binding<MediaCategory>) -> some View {
        @Binding var category: MediaCategory
        _category = binding
        return VStack(alignment: .leading, spacing: 12) {
            Text(category.name + " — Advanced").font(.title2.bold())
            Text("Recognition and layout details. Save the profile to keep changes.").font(.caption).foregroundStyle(.secondary)
            Form {
                Toggle("Category enabled", isOn: $category.enabled)
                TextField("Category name", text: $category.name)
                TextField("Aliases (comma separated)", text: $category.aliases)
                Picker("Layout Type", selection: $category.associatedType) {
                    Text("Use the file’s Type").tag("")
                    if !category.associatedType.isEmpty && !(profile.classifications ?? []).contains(where: { $0.name == category.associatedType }) { Text(category.associatedType + (PatternEngine.lookup(category.associatedType, profile: profile) == nil ? " (unconfigured)" : " (alias)")).tag(category.associatedType) }
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
                            if !rule.type.isEmpty && !(profile.classifications ?? []).contains(where: { $0.name == rule.type }) { Text(rule.type + (PatternEngine.lookup(rule.type, profile: profile) == nil ? " (unconfigured)" : " (alias)")).tag(rule.type) }
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
                }
            }.formStyle(.grouped).textFieldStyle(.roundedBorder)
            Text("Explicit selection/capture wins. Type + keyword rules precede keyword-only, then Type-only rules; order breaks ties. Both conditions in a rule must match.").font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button("Done") { editor = nil }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 650, height: 650)
    }
    private func addMissingStarters() {
        let occupied = Set((profile.mediaCategories ?? []).flatMap { [$0.name] + UniversalPreferences.entries($0.aliases) }.map { $0.lowercased() })
        categories.wrappedValue += MediaRouting.starters.filter { entry in
            Set(([entry.name] + UniversalPreferences.entries(entry.aliases)).map { $0.lowercased() }).isDisjoint(with: occupied)
        }
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

private struct CategoryFolderEditor: View {
    @Binding var category: MediaCategory
    let libraryRoot: String
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var useRoot = false
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Folder for “" + category.name + "”").font(.title2.bold())
            Text("Library: " + (libraryRoot.isEmpty ? "Choose a destination root in Profile Settings first" : libraryRoot)).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
            TextField("Folder name", text: $name).textFieldStyle(.roundedBorder).disabled(useRoot)
            HStack {
                Button("Browse Existing Folders…") { browse() }.disabled(libraryRoot.isEmpty)
                Toggle("Use library root itself", isOn: $useRoot)
            }
            Text("Enter the name of a folder directly inside your library, or browse to an existing one. New folders are created only when you apply a filing operation.").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Button("Clear Mapping") { category.rootFolder = nil; dismiss() }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Use Folder") {
                    do {
                        let folder = useRoot ? "" : name.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !useRoot { try component(folder) }
                        category.rootFolder = folder; dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(!useRoot && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 560)
            .onAppear { name = category.rootFolder ?? ""; useRoot = category.rootFolder == "" }
    }
    private func browse() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = false
        panel.title = "Select destination folder for " + category.name
        panel.message = "Select the library destination for “" + category.name + "”. Choose the library root or one of its direct child folders."
        panel.prompt = "Use for " + category.name
        panel.directoryURL = URL(fileURLWithPath: libraryRoot)
        WindowPresentation.choose(panel) { response in
            guard response == .OK, let url = panel.url else { return }
            let root = URL(fileURLWithPath: libraryRoot).standardizedFileURL
            if url.standardizedFileURL == root { useRoot = true; error = "" }
            else if url.deletingLastPathComponent().standardizedFileURL == root { name = url.lastPathComponent; useRoot = false; error = "" }
            else { error = "Choose the library root or one of its direct child folders." }
        }
    }
}

private struct AddMediaCategoryView: View {
    let existing: [MediaCategory]
    let add: (MediaCategory) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var layout = "Movies"
    @State private var keyword = ""
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Media Category").font(.title2.bold())
            TextField("Category name", text: $name).textFieldStyle(.roundedBorder)
            Picker("Naming layout", selection: $layout) { ForEach(MediaRouting.starters) { Text($0.name).tag($0.name) } }
            TextField("Match filenames containing (optional)", text: $keyword).textFieldStyle(.roundedBorder)
            Text("Without a keyword, select this category for files yourself or use it as the unmatched-video default. You can customize recognition later in Advanced.").font(.caption).foregroundStyle(.secondary)
            if !error.isEmpty { Text(error).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add Category") {
                    do {
                        let title = name.trimmingCharacters(in: .whitespacesAndNewlines); try component(title)
                        guard !title.hasPrefix("@"), !existing.contains(where: { ([$0.name] + UniversalPreferences.entries($0.aliases)).contains(where: { $0.caseInsensitiveCompare(title) == .orderedSame }) }) else { throw fail("Choose a unique category name.") }
                        guard let template = MediaRouting.starters.first(where: { $0.name == layout }) else { return }
                        var category = MediaCategory(title, type: template.associatedType, folderMask: template.folderMask, filenameMask: template.filenameMask)
                        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !word.isEmpty { category.rules = [MediaCategoryRule(keyword: word)] }
                        add(category); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(20).frame(width: 540)
    }
}
