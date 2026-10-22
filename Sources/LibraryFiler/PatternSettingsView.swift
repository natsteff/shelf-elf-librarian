import SwiftUI
import AppKit
import FilerCore

struct PatternSettingsView: View {
    @Binding var profile: Profile
    @EnvironmentObject var m: Model
    @Environment(\.dismiss) var dismiss
    @State private var sample = ""
    @State private var results: [String] = []
    @State private var validation = ""
    @State private var original: Profile?
    private var rules: Binding<[WorkspacePattern]> { Binding(get: { profile.workspacePatterns ?? [] }, set: { profile.workspacePatterns = $0 }) }
    private var types: Binding<[FilingType]> { Binding(get: { profile.classifications ?? [] }, set: { profile.classifications = $0 }) }
    private func move(_ id: UUID, _ offset: Int) {
        var list = rules.wrappedValue
        guard let index = list.firstIndex(where: { $0.id == id }), list.indices.contains(index + offset) else { return }
        list.swapAt(index, index + offset); rules.wrappedValue = list
    }
    private func addDefaults() {
        if (profile.classifications ?? []).isEmpty {
            // Preserve the old folder layout unless the user explicitly configures a mapping.
            profile.classifications = PatternEngine.defaultTypes(for: profile.kind).map { entry in var copy = entry; copy.folderMask = nil; return copy }
        }
        let missing = PatternEngine.defaults(for: profile).filter { rule in !(profile.workspacePatterns ?? []).contains { $0.pattern == rule.pattern && !$0.compatibility } }
        profile.workspacePatterns = missing + (profile.workspacePatterns ?? [])
    }
    private func test(_ urls: [URL]) {
        do {
            var draft = profile; draft.exceptions = m.sharedExceptions
            var preparation = draft.rules; preparation.smallWords = m.universalPreferences.titleWords; draft.rules = preparation
            try PatternEngine.validate(draft)
            results = urls.prefix(25).map { url in
                let result = PatternEngine.interpret(url, profile: draft)
                let values = FieldCatalog.values(result.0).filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: " · ")
                let filename = (try? proposedFilename(Item(url: url, size: 0, fields: result.0, evidence: "", reviewed: false), profile: draft)) ?? "[Missing filename components]"
                let folder = (try? Names.render(PatternEngine.folderMask(for: result.0, profile: draft), fields: result.0, profile: draft, source: url, folder: true)) ?? "[Missing folder components]"
                let warning = (try? PatternEngine.validateClassification(result.0, profile: draft)) == nil ? "Review classification before filing.\n" : ""
                return url.lastPathComponent + "\n" + result.1 + "\n" + values + "\n" + warning + "Destination: " + (draft.root.isEmpty ? "[Library root]" : draft.root) + (folder.isEmpty ? "" : "/" + folder) + "/" + filename
            }
            validation = ""
        } catch { validation = error.localizedDescription }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspace Filename Patterns & Filing Types").font(.title2.bold())
            Text("Changes are part of the profile draft. Save Profile Settings to apply them.").font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Input patterns · first enabled match wins").font(.headline)
                    Text("Match the entire filename without its extension. Braces capture a component; all other text is literal. Example: Commercial - {Title} ({Year}). [{Type}] reads a value inside brackets. {EpisodeID} understands S01E02. Specific patterns should precede broad patterns such as {Title}.").font(.caption)
                    ForEach(rules) { $rule in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Toggle("Enabled", isOn: $rule.enabled)
                                Spacer()
                                Button("↑") { move(rule.id, -1) }.accessibilityLabel("Move pattern earlier")
                                Button("↓") { move(rule.id, 1) }.accessibilityLabel("Move pattern later")
                                Button("Remove") { rules.wrappedValue.removeAll { $0.id == rule.id } }
                            }
                            if rule.compatibility {
                                Text("Compatibility: existing " + profile.kind.label + " interpretation").font(.callout.bold())
                                Text("Preserves the prior permissive parser, including the legacy extraction mask and episode precedence. Move your new patterns above this row, or disable/remove it to use patterns exclusively. It does not run Magic.").font(.caption).foregroundStyle(.secondary)
                                Button("Convert to editable pattern") { rule.compatibility = false; rule.pattern = profile.extractionMask.isEmpty ? "{Title}" : profile.extractionMask }
                            } else {
                                TextField("Input pattern", text: $rule.pattern).textFieldStyle(.roundedBorder)
                                if let source = rule.source {
                                    Picker("Input source", selection: Binding(get: { rule.source ?? .filename }, set: { rule.source = $0 })) {
                                        Text("Filename").tag(PatternSource.filename); Text("Parent folders").tag(PatternSource.parentFolders)
                                    }
                                    if source == .parentFolders { Text("Matches the last folder levels before the file, using / between levels. Existing chapter number/title can still come from the filename.").font(.caption) }
                                } else {
                                    Picker("Input source", selection: Binding(get: { PatternSource.filename }, set: { rule.source = $0 })) {
                                        Text("Filename").tag(PatternSource.filename); Text("Parent folders").tag(PatternSource.parentFolders)
                                    }
                                }
                                Picker(PatternEngine.classificationKey(profile), selection: $rule.assignedType) {
                                    Text("Unspecified").tag("")
                                    if rule.pattern.contains("{" + PatternEngine.classificationKey(profile) + "}") { Text("Read from filename").tag("@capture") }
                                    ForEach(profile.classifications ?? []) { entry in Text(entry.name).tag(entry.name) }
                                    Text("Add Type…").tag("@add")
                                }.onChange(of: rule.assignedType) { value in
                                    if value == "@add" { rule.assignedType = ""; types.wrappedValue.append(FilingType("New " + PatternEngine.classificationKey(profile))) }
                                }
                            }
                        }.padding(12).background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                    }
                    HStack {
                        Button("Add Pattern") { rules.wrappedValue.append(WorkspacePattern("{Title}")) }
                        Button("Add Suggested Patterns Before Existing Rules") { addDefaults() }
                    }
                    Text("Types & filing layouts").font(.headline)
                    Picker("Classification component", selection: Binding(get: { PatternEngine.classificationKey(profile) }, set: { profile.classificationComponent = $0 })) {
                        ForEach(["Type", "System", "Genre"], id: \.self) { Text($0).tag($0) }
                    }
                    Text("Names and aliases match without case sensitivity. Unknown captured values require review before filing. Shared folder masks are allowed. A mapping overrides the profile layout; otherwise the profile folder/filename masks are used. All folders remain below the selected library root.").font(.caption)
                    ForEach(types) { $entry in
                        FilingTypeEditor(entry: $entry, root: profile.root) { types.wrappedValue.removeAll { $0.id == entry.id } }
                    }
                    Button("Add Type…") { types.wrappedValue.append(FilingType("New " + PatternEngine.classificationKey(profile))) }
                    Text("Test patterns without changing files").font(.headline)
                    HStack {
                        TextField("Example filename, including extension", text: $sample).textFieldStyle(.roundedBorder)
                        Button("Test Example") { test([URL(fileURLWithPath: sample)]) }.disabled(sample.isEmpty)
                        Button("Test Selected Files") { test(m.visibleSelected.map(\.url)) }.disabled(m.visibleSelected.isEmpty)
                    }
                    Text("Tests at most 25 selected files. Shows matched rule, components and destination; no files are renamed or copied.").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(results.enumerated()), id: \.offset) { _, value in Text(value).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary) }
                    if !validation.isEmpty { Text(validation).foregroundStyle(.red) }
                    Text("Available captures: " + FieldCatalog.keys.keys.sorted().joined(separator: ", ") + ", EpisodeID. Output masks also support TitleYear, BookFolder, Bucket (music), Live and numeric :02 formatting. Use {Series?} for an optional folder level. BookFolder prefixes BookTitle with SeriesNumber when present.").font(.caption).foregroundStyle(.secondary)
                }.padding(4)
            }
            HStack { Button("Cancel") { if let original { profile = original }; dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button("Done") { do { try PatternEngine.validate(profile); dismiss() } catch { validation = error.localizedDescription } }.keyboardShortcut(.defaultAction) }
        }.padding(20).frame(width: 940, height: 760).onAppear { if original == nil { original = profile } }
    }
}
private struct FilingTypeEditor: View {
    @Binding var entry: FilingType
    let root: String
    let remove: () -> Void
    @State private var error = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { TextField("Type name", text: $entry.name); Button("Remove", action: remove) }
            TextField("Aliases (comma separated)", text: $entry.aliases)
            Toggle("Use a custom folder mask", isOn: Binding(get: { entry.folderMask != nil }, set: { entry.folderMask = $0 ? "" : nil }))
            if entry.folderMask != nil {
                HStack {
                    TextField("Folder mask (blank = library root)", text: Binding(get: { entry.folderMask ?? "" }, set: { entry.folderMask = $0 }))
                    Button("Choose Folder…") {
                        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                        if !root.isEmpty { panel.directoryURL = URL(fileURLWithPath: root) }
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        guard !root.isEmpty, url.path == root || url.path.hasPrefix(root + "/") else { error = "Choose a folder inside this profile’s destination root, or enter a relative folder mask."; return }
                        entry.folderMask = url.path == root ? "" : String(url.path.dropFirst(root.count + 1)); error = ""
                    }.disabled(root.isEmpty)
                }
            }
            Toggle("Use a custom filename mask", isOn: Binding(get: { entry.filenameMask != nil }, set: { entry.filenameMask = $0 ? "{Title}" : nil }))
            if entry.filenameMask != nil { TextField("Filename mask", text: Binding(get: { entry.filenameMask ?? "" }, set: { entry.filenameMask = $0 })) }
            if !error.isEmpty { Text(error).foregroundStyle(.red).font(.caption) }
        }.textFieldStyle(.roundedBorder).padding(12).background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}
