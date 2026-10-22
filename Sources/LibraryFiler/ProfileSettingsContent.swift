import SwiftUI
import AppKit
import FilerCore

/// One settings flow for every content type; examples and specialized controls follow the profile.
struct ProfileSettingsContent: View {
    @EnvironmentObject var model: Model
    @Binding var profile: Profile
    @Binding var validation: String
    var patterns: () -> Void
    var guide: () -> Void
    var general: () -> Void
    var recommendations: () -> Void
    private var sample: String {
        switch profile.kind {
        case .video: return "Movie Title"
        case .music: return "Song Title"
        case .audiobook: return "Book Title"
        case .documents: return "Document Title"
        case .roms: return "Game Title"
        case .photos: return "Holiday Photo"
        case .software: return "Product Name"
        case .other: return "File Name"
        }
    }
    private var suggested: Profile { ProfileSetup.configured(profile.kind, name: profile.name, subtype: profile.bookSubtype) }
    private var periodChoice: Binding<String> {
        Binding(get: { profile.replaceDots && profile.rules.dotsToDashes ? "conflict" : profile.rules.dotsToDashes ? "dashes" : profile.replaceDots ? "spaces" : "keep" }, set: { choice in
            guard choice != "conflict" else { return }
            profile.replaceDots = choice == "spaces"
            var rules = profile.rules; rules.dotsToDashes = choice == "dashes"; profile.rules = rules
        })
    }
    private func typeMask(_ type: String, folder: Bool) -> Binding<String> {
        Binding(get: {
            let entry = profile.classifications?.first { $0.name == type }
            return (folder ? entry?.folderMask : entry?.filenameMask) ?? (folder ? profile.folderMask : profile.filenameMask)
        }, set: { value in
            var types = profile.classifications ?? []
            if !types.contains(where: { $0.name == type }) { types.append(FilingType(type)) }
            if let i = types.firstIndex(where: { $0.name == type }) {
                if folder { types[i].folderMask = value } else { types[i].filenameMask = value }
            }
            profile.classifications = types
        })
    }
    private var componentReference: String {
        switch profile.kind {
        case .video: return "Title, Year, Resolution, Series, Season, Episode, EpisodeID, EpisodeTitle, Type"
        case .music: return "Artist, Title, Album, Year, TrackNumber, Genre, RecordingType, Live, Bucket, AlbumOrIndividual"
        case .audiobook:
            switch profile.effectiveBookSubtype {
            case .audiobook: return "Author, Series, SeriesNumber, BookTitle, BookFolder, ChapterNumber, ChapterTitle, ChapterOrBook, Narrator, Publisher, Year"
            case .ebook: return "Author, Series, SeriesNumber, BookTitle, BookFolder, Publisher, Year"
            case .comic: return "Author, Series, SeriesNumber, BookTitle, BookFolder, Illustrator, Publisher, IssueNumber, Volume, Year"
            case .general: return "Author, Series, SeriesNumber, BookTitle, BookFolder, ChapterNumber, ChapterTitle, Narrator, Illustrator, Publisher, IssueNumber, Volume, Year"
            }
        case .documents: return "Title, Date, Revision, Game, Type"
        case .roms: return "Title, System, Region, Edition, Revision"
        case .photos: return "Title, DateTaken, Event"
        case .software: return "Product, Version, Platform, Architecture, Title"
        case .other: return "Title and your named captures, such as Collection or Category"
        }
    }
    var body: some View {
        Section("1. Profile & destination") {
            SettingsInput(title: "Profile name", text: $profile.name, example: profile.kind.label + " Library")
            VStack(alignment: .leading) {
                Text("Description / Notes").font(.caption.bold())
                TextEditor(text: Binding(get: { profile.notes ?? "" }, set: { profile.notes = $0 })).frame(minHeight: 65, maxHeight: 100)
            }
            Picker("Content type", selection: $profile.kind) { ForEach(Kind.allCases) { Text($0.label).tag($0) } }
            if profile.kind == .audiobook {
                Picker("Book subtype", selection: Binding(get: { profile.effectiveBookSubtype }, set: { profile.bookSubtype = $0 })) { ForEach(BookSubtype.allCases) { Text($0.label).tag($0) } }
            }
            Button("Load defaults for this content type") {
                var p = suggested
                p.id = profile.id; p.notes = profile.notes; p.root = profile.root; p.bookmark = profile.bookmark; p.rootIdentity = profile.rootIdentity
                profile = p
            }
            SettingsHint(text: "Changing content type or subtype preserves your settings. Load defaults replaces rules, extensions and masks; name, notes and destination are kept.")
            SettingsInput(title: "Extensions (comma separated)", text: $profile.extensions, example: suggested.extensions)
            SettingsHint(text: "Filters files without converting them. Matching ignores case; original extensions are preserved.")
            LabeledContent("Destination root") { Text(profile.root.isEmpty ? "Not configured" : profile.root).textSelection(.enabled) }
            HStack {
                Button("Choose Destination Root…") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                    WindowPresentation.choose(panel) { response in
                        guard response == .OK, let url = panel.url else { return }
                        do {
                            let d = try Directory(url.path)
                            profile.rootIdentity = DirectoryIdentity(device: d.device, inode: d.inode); profile.root = url.path
                            profile.bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                        } catch { validation = error.localizedDescription }
                    }
                }
                Button("Show Library in Finder") {
                    let url = URL(fileURLWithPath: profile.root)
                    let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if !showFolderInFinder(url) { validation = "Library folder unavailable. Choose Destination Root to reconnect." }
                }.disabled(profile.root.isEmpty)
            }
            SettingsHint(text: "Folder masks create subfolders beneath this root. Preview Filing shows the complete destination before you apply it.")
        }
        Section("2. Read filenames") {
            Button("Workspace Filename Patterns & Filing Types…", action: patterns)
            SettingsHint(text: "Input patterns run in order and extract components from original filenames. Filing types choose output layouts in section 4. Test patterns against workspace examples before saving.")
            if profile.workspacePatterns?.contains(where: { $0.compatibility }) == true {
                SettingsInput(title: "Legacy extraction mask", text: $profile.extractionMask, example: suggested.workspacePatterns?.first?.pattern ?? "{Title}")
                SettingsHint(text: "Used only by an enabled compatibility rule. Edit or disable that rule in Workspace Filename Patterns.")
            }
            Text("Available components: " + componentReference).font(.caption)
            if profile.kind == .photos || profile.kind == .music || profile.kind == .audiobook {
                SettingsHint(text: "Components come from filenames or explicitly configured parent-folder patterns. Embedded tags and EXIF data are not read.")
            }
        }
        Section("3. Clean components") {
            Button("Universal Spelling & Case Preference Exceptions…", action: general)
            SettingsHint(text: "Shared spelling and preferred-case exceptions apply to every profile. Explicit removable labels take precedence over exceptions.")
            Toggle("Underscores to spaces", isOn: $profile.replaceUnderscores)
            SettingsHint(text: sample.replacingOccurrences(of: " ", with: "_") + " → " + sample)
            Picker("Period handling", selection: periodChoice) {
                if periodChoice.wrappedValue == "conflict" { Text("Conflict — choose one option").tag("conflict") }
                Text("Keep periods").tag("keep")
                Text("Separator periods → spaces").tag("spaces")
                Text("All periods → ‘ - ’").tag("dashes")
            }
            if periodChoice.wrappedValue == "conflict" { Text("Both old period options are enabled. Choose one before saving.").foregroundStyle(.orange) }
            SettingsHint(text: periodChoice.wrappedValue == "dashes" ? "Every basename period changes: Name.v1.2 → Name - v1 - 2. The extension is preserved." : sample.replacingOccurrences(of: " ", with: ".") + " → " + sample + ". Separator mode preserves decimals and dotted initials; the extension is unchanged.")
            Toggle("Title case", isOn: $profile.titleCase)
            Toggle("Smart title case", isOn: Binding(get: { profile.rules.smartTitleCase }, set: { var r = profile.rules; r.smartTitleCase = $0; profile.rules = r })).disabled(!profile.titleCase)
            SettingsHint(text: "Smart title case keeps short connecting words lowercase in names such as ‘" + sample + " of the Year’. Requires Title case and uses the lowercase word list in General Settings. Preferred-case exceptions apply last.")
            Toggle("Normalize repeated spaces and trim whitespace", isOn: Binding(get: { profile.normalizeSpaces ?? true }, set: { profile.normalizeSpaces = $0 }))
            Toggle("Hyphens to spaces (filename components)", isOn: Binding(get: { profile.rules.hyphensToSpaces }, set: { var r = profile.rules; r.hyphensToSpaces = $0; profile.rules = r }))
            SettingsHint(text: sample.replacingOccurrences(of: " ", with: "-") + " → " + sample + ". Output masks may add their own separators. Protect meaningful spellings such as AC-DC in General Settings.")
            DisclosureGroup("Advanced cleanup & replacements") {
                SettingsInput(title: "Removable labels", text: $profile.removeTokens, example: profile.kind == .music ? "[Official Audio]" : "[Unwanted Label]")
                SettingsHint(text: "Deletes matching text at word boundaries, including brackets if entered. Leave blank to preserve technical information such as resolution and source.")
                if !model.universalPreferences.overlaps(removableLabels: profile.removeTokens).isEmpty {
                    SettingsHint(text: "Removal overrides preferred spellings for: " + model.universalPreferences.overlaps(removableLabels: profile.removeTokens).joined(separator: ", "))
                }
                Toggle("Smart title case for folder names", isOn: Binding(get: { profile.rules.folderTitleCase ?? true }, set: { var r = profile.rules; r.folderTitleCase = $0; profile.rules = r }))
                Toggle("Hyphens to spaces (destination folder names)", isOn: Binding(get: { profile.rules.folderHyphensToSpaces }, set: { var r = profile.rules; r.folderHyphensToSpaces = $0; profile.rules = r }))
                SettingsHint(text: "Applies to generated destination folders. Tools → Clean Folder Names is a separate, reviewed operation on existing folders.")
                ReplacementSettings(rules: Binding(get: { profile.rules }, set: { profile.rules = $0 }))
            }
        }
        Section("4. Build names & folders") {
            if profile.kind == .video {
                Text("Movie").font(.headline)
                SettingsInput(title: "Movie folder mask", text: typeMask("Movie", folder: true), example: "Movies/{Title} ({Year?})")
                SettingsInput(title: "Movie filename mask", text: typeMask("Movie", folder: false), example: "{Title} ({Year?}) [{Resolution?}]")
                Text("TV Show").font(.headline)
                SettingsInput(title: "TV folder mask", text: typeMask("TV Show", folder: true), example: "TV Shows/{Series}/Season {Season:02}")
                SettingsInput(title: "TV filename mask", text: typeMask("TV Show", folder: false), example: "{Series} - {EpisodeID} - {EpisodeTitle}")
                EpisodeFormattingSettings(rules: Binding(get: { profile.rules }, set: { profile.rules = $0 }))
                SettingsHint(text: "These are the same Movie and TV Show mappings shown in Filing Types. Other types can override the fallback masks below.")
                DisclosureGroup("Fallback masks for other video types") { fallbackMasks }
            } else { fallbackMasks }
            SettingsHint(text: "Literal text around {Components} is preserved. / separates folders; the original extension is added automatically. ({Year?}) and [{Resolution?}] disappear when blank. A standalone optional folder such as {Series?} omits that folder level.")
            SettingsInput(title: "Filename prefix (optional)", text: $profile.prefix, example: "Archive - ")
            SettingsInput(title: "Filename suffix (optional)", text: $profile.suffix, example: " - Reviewed")
            if profile.kind == .music {
                Toggle("Music first-letter bucket", isOn: $profile.bucket)
                SettingsInput(title: "Individual tracks folder", text: $profile.individualTracks, example: "Individual Tracks")
                TextField("Number bucket", text: Binding(get: { profile.rules.numericBucket }, set: { var r = profile.rules; r.numericBucket = $0; profile.rules = r }))
                TextField("Symbol bucket", text: Binding(get: { profile.rules.symbolBucket }, set: { var r = profile.rules; r.symbolBucket = $0; profile.rules = r }))
                Toggle("Ignore leading The for bucket only", isOn: Binding(get: { profile.rules.ignoreLeadingThe }, set: { var r = profile.rules; r.ignoreLeadingThe = $0; profile.rules = r }))
            }
            if profile.kind != .video && profile.supportsEpisodes { DisclosureGroup("Optional episode formatting") { EpisodeFormattingSettings(rules: Binding(get: { profile.rules }, set: { profile.rules = $0 })) } }
            DisclosureGroup("Components & mask reference") {
                Text(componentReference).font(.caption)
                Button("Interpretation & Output Masks Guide…", action: guide)
                Button("Edit input patterns and filing type overrides…", action: patterns)
            }
        }
        Section("5. Magic & learning") {
            Toggle("Enable Magic for this profile", isOn: Binding(get: { profile.rules.useMagic }, set: { var r = profile.rules; r.useMagic = $0; profile.rules = r }))
            SettingsHint(text: "Magic runs only when requested for selected files. It proposes components from filename evidence, parent folders and remembered corrections; output masks still determine the resulting names. No online lookup or embedded metadata reading.")
            Toggle("Remember confirmed corrections by default", isOn: Binding(get: { profile.rememberCorrectionsByDefault ?? true }, set: { profile.rememberCorrectionsByDefault = $0 }))
            SettingsHint(text: "Starts Remember checked after refresh. Only successful, approved operations supply examples. You can turn it off for selected files or forget examples below.")
            Button("Recommendations & Learning…", action: recommendations)
        }
    }
    private var fallbackMasks: some View {
        Group {
            SettingsInput(title: "Folder mask", text: $profile.folderMask, example: suggested.folderMask)
            SettingsInput(title: "Filename mask (without extension)", text: $profile.filenameMask, example: suggested.filenameMask)
            SettingsHint(text: "Type, System or Genre mappings may override these masks. Review those mappings in Workspace Filename Patterns & Filing Types.")
        }
    }
}

struct EpisodeFormattingSettings: View {
    @Binding var rules: PreparationRules
    var body: some View {
        Toggle("Format season/episode separators", isOn: $rules.formatEpisodes)
        SettingsHint(text: "Show S1E2 Pilot → Show - S01E02 - Pilot. Explicit TV output masks control the final separators; {EpisodeID} uses the capitalization below.")
        Picker("Season/episode capitalization", selection: Binding(get: { rules.episodeCase }, set: { rules.episodeCapitalization = $0 })) { ForEach(EpisodeCapitalization.allCases) { Text($0.label).tag($0) } }
        Toggle("Lowercase entire episode filename", isOn: $rules.lowercaseEpisodeTitle)
        SettingsHint(text: "Changes surrounding series/title text. Episode capitalization and preferred-case exceptions retain their own rules.")
    }
}

struct ReplacementSettings: View {
    @Binding var rules: PreparationRules
    var body: some View {
        ForEach($rules.replacements) { $rule in
            VStack {
                HStack { Toggle("Enabled", isOn: $rule.enabled); TextField("Find literal text", text: $rule.find); Text("→"); TextField("Replace (blank deletes)", text: $rule.replacement) }
                HStack {
                    Picker("Match", selection: Binding(get: { rule.position ?? .anywhere }, set: { rule.position = $0 })) { ForEach(ReplacementPosition.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    Picker("Apply to", selection: $rule.target) { ForEach(RuleTarget.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    Button("↑") { move(rule.id, -1) }; Button("↓") { move(rule.id, 1) }
                    Button("Remove") { rules.replacements.removeAll { $0.id == rule.id } }
                }
            }
        }
        Button("Add Replacement Rule") { rules.replacements.append(ReplacementRule()) }
        SettingsHint(text: "Literal matches, applied top to bottom after separator cleanup and before casing. Blank replacement deletes text. Rules never edit extensions.")
    }
    private func move(_ id: UUID, _ offset: Int) {
        guard let i = rules.replacements.firstIndex(where: { $0.id == id }), rules.replacements.indices.contains(i + offset) else { return }
        rules.replacements.swapAt(i, i + offset)
    }
}
