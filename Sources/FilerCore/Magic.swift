import Foundation

public struct Interpretation: Identifiable, Equatable {
    public var id = UUID()
    public var label: String
    public var fields: Fields
    public var evidence: String
    public var confidence: String
    public var overrideBasename: String?
    public init(label: String, fields: Fields, evidence: String, confidence: String, overrideBasename: String? = nil) { self.overrideBasename = overrideBasename; self.label = label; self.fields = fields; self.evidence = evidence; self.confidence = confidence }
}
public enum Magic {
    public static func suggestions(url: URL, profile p: Profile, related: [Item] = [], memories: [ConfirmedCorrection] = []) -> [Interpretation] {
        if p.workspacePatterns != nil && !MediaFilenameParser.supports(p) {
            let result = PatternEngine.interpret(url, profile: p)
            let primary = Interpretation(label: "Workspace pattern", fields: result.0, evidence: result.1, confidence: "Review filename evidence")
            var legacy = p; legacy.workspacePatterns = nil
            let additional = suggestions(url: url, profile: legacy, related: related, memories: [])
            var options = result.1.contains(": compatibility interpretation.") ? additional : [primary]
            if !options.contains(where: { $0.fields == primary.fields }) { options.append(primary) }
            if !result.1.contains(": compatibility interpretation.") {
                for var alternative in additional where !options.contains(where: { $0.fields == alternative.fields }) {
                    let key = PatternEngine.classificationKey(p)
                    if FieldCatalog.get(key, alternative.fields).isEmpty { FieldCatalog.set(key, FieldCatalog.get(key, result.0), &alternative.fields) }
                    alternative.evidence = "Additional manual Magic interpretation. " + alternative.evidence
                    options.append(alternative)
                }
            }
            let exact = memories.filter { $0.profileID == p.id && $0.remember && $0.settingsSignature == Learning.settingsSignature(p) && $0.original == url.lastPathComponent && $0.sourceParentPath == url.deletingLastPathComponent().path }
            for memory in exact { options.insert(Interpretation(label: "Remembered correction", fields: memory.fields, evidence: "Previously confirmed correction; review before applying.", confidence: "Remembered evidence", overrideBasename: URL(fileURLWithPath: memory.final).deletingPathExtension().lastPathComponent), at: 0) }
            return options
        }
        let original = url.deletingPathExtension().lastPathComponent
        let basic = Names.basicInterpret(url, p)
        var suggestions: [Interpretation] = []
        func add(_ label: String, _ input: Fields, _ why: String, _ strength: String) { var f = input; if p.kind == .video && f.type.isEmpty { f.type = basic.0.type }; f.artist = RuleEngine.artistName(f.artist, profile: p); if p.kind == .audiobook && !f.bookTitle.isEmpty { f.title = f.bookTitle }; Names.enrichYearAndRecording(&f, profile: p); if !suggestions.contains(where: { $0.fields == f }) { suggestions.append(Interpretation(label: label, fields: f, evidence: why, confidence: strength)) } }
        // Remembered examples are scoped to one profile and must be explicitly opted in.
        let remembered = memories.filter { $0.profileID == p.id && $0.remember && $0.settingsSignature == Learning.settingsSignature(p) && $0.sourceParentPath == url.deletingLastPathComponent().path && $0.original == url.lastPathComponent }
        for example in remembered {
            suggestions.append(Interpretation(label: "Remembered correction", fields: example.fields, evidence: "Previously approved exact filename correction in this profile. Confirm it applies to this item too.", confidence: "Strong evidence", overrideBasename: URL(fileURLWithPath: example.final).deletingPathExtension().lastPathComponent))
        }
        if MediaFilenameParser.supports(p) { add("Built-in filename interpretation", basic.0, basic.1, "Review filename evidence") }
        if p.kind == .video, let ep = Names.episodeComponents(original, profile: p) {
            var f = Fields(); f.series = Names.cleanField(ep.series, p); f.season = ep.season; f.episode = ep.episode; f.episodeTitle = Names.cleanField(ep.title, p)
            add("TV episode", f, "The original filename contains S/E numbers; the video profile is selected. Year was not guessed.", "Strong evidence")
        }
        let readable = original.replacingOccurrences(of: "_", with: " ")
        let parts = Names.filenameSections(original, profile: p).map { Names.cleanField($0, p) }
        switch p.kind {
        case .music:
            if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                var f = Fields(); f.artist = parts[0]; f.title = parts[1]
                let shared = related.filter { $0.url.path != url.path && $0.url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ").hasPrefix(readable.components(separatedBy: " - ")[0] + " - ") }.count
                add("Artist — Title", f, "Two original filename sections separated by ‘ - ’ and the music profile is selected." + (shared > 0 ? " \(shared) other selected filenames share the first section." : ""), "Strong evidence")
                var reversed = Fields(); reversed.artist = parts[1]; reversed.title = parts[0]
                add("Title — Artist (alternative)", reversed, "The separator alone cannot prove which section is the artist. Use this alternative only if the file is named title first.", "Limited evidence")
            }
        case .audiobook:
            if p.effectiveBookSubtype == .audiobook, parts.count >= 3, let number = parts.last, Int(number) != nil {
                var f = Fields(); f.author = parts[0]; f.bookTitle = parts.dropFirst().dropLast().joined(separator: " - "); f.chapterNumber = number; f.title = Names.cleanField(original, p)
                add("Author — Book — Chapter", f, "Original filename has author/book sections and a trailing number, with the audiobook profile selected. Chapter numbering is retained.", "Strong evidence")
            }
            if p.effectiveBookSubtype == .audiobook, parts.count == 2, Int(parts[0]) != nil {
                var f = basic.0; f.chapterNumber = parts[0]; f.chapterTitle = parts[1]
                let shared = related.filter { $0.url.deletingLastPathComponent() == url.deletingLastPathComponent() }
                let confirmed = shared.filter { !$0.fields.author.isEmpty && !$0.fields.bookTitle.isEmpty && $0.reviewed }
                let groups = Dictionary(grouping: confirmed, by: { $0.fields.author + "\u{0}" + $0.fields.bookTitle }).values.compactMap(\.first).sorted { $0.fields.bookTitle < $1.fields.bookTitle }
                if groups.count > 1 { add("Conflicting selected groups", f, "Reviewed selected siblings name different books/authors. Choose an explicit alternative; missing author/book fields are not guessed.", "Needs review") }
                for sibling in groups {
                    var grouped = f; grouped.author = sibling.fields.author; grouped.bookTitle = sibling.fields.bookTitle
                    add("Selected group: " + grouped.bookTitle, grouped, "A reviewed selected sibling in the same folder supplies Author and Book; the original filename supplies chapter number/title." + (groups.count > 1 ? " Other selected groups disagree." : ""), groups.count > 1 ? "Limited evidence" : "Strong evidence")
                }
                let parent = url.deletingLastPathComponent(), grandparent = parent.deletingLastPathComponent()
                if parent.path != "/", grandparent.path != "/" {
                    f.author = Names.cleanField(grandparent.lastPathComponent, p); f.bookTitle = Names.cleanField(parent.lastPathComponent, p)
                    add("Parent-folder book/author", f, "Possible author/book from the two parent folder names, plus the original chapter filename. Folder names can be incidental: review or choose another interpretation.", "Limited evidence")
                }
            }
        case .documents:
            var f = basic.0
            if let re = try? NSRegularExpression(pattern: #"(?<!\d)(\d{4}[-_.]\d{2}[-_.]\d{2})(?!\d)"#), let m = re.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)) { f.date = (original as NSString).substring(with: m.range(at: 1)) }
            if let re = try? NSRegularExpression(pattern: #"(?i)(?<![\p{L}\p{N}])((?:rev(?:ision)?[ _.-]*|v)\d+(?:\.\d+)*)(?![\p{L}\p{N}])"#), let m = re.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)) { f.revision = (original as NSString).substring(with: m.range(at: 1)) }
            if !f.date.isEmpty || !f.revision.isEmpty { add("Document filename fields", f, "Date-like/revision markers appear in the original filename. The title retains them unless you explicitly change the output mask or fields. No document content was inspected.", "Strong evidence") }
        case .video, .roms, .photos, .software, .other: break
        }
        if p.kind == .video, RuleEngine.episode(original) == nil,
            let regex = try? NSRegularExpression(pattern: #"(?:^|[ ._(\-])((?:19|20)\d{2})(?:[ ._)\-]|$)"#),
            let match = regex.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)) {
            var f = Fields(); f.year = (original as NSString).substring(with: match.range(at: 1))
            let title = (original as NSString).replacingCharacters(in: match.range(at: 1), with: " ")
            f.title = Names.cleanField(title, p).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "()")))
            add("Movie title/year", f, "A year-like token is retained from the original filename before cleanup. No online identification or invented values.", "Limited evidence")
        }
        add("Filename interpretation", basic.0, basic.1, basic.2 ? "Filename only" : "Needs review")
        var literal = Fields(); literal.title = Names.cleanField(original, p)
        add("Keep as one title", literal, "Treat the complete basename as one title; no author/artist/year inferred. Required filing fields may remain missing.", "Filename only")
        // Repeated explicitly remembered spelling corrections can refine the structured fields.
        for index in suggestions.indices {
            for memory in memories where memory.profileID == p.id && memory.remember && memory.settingsSignature == Learning.settingsSignature(p) {
                for key in [\Fields.artist, \Fields.author, \Fields.bookTitle] {
                    let from = memory.initialFields[keyPath: key], to = memory.fields[keyPath: key]
                    if !from.isEmpty, from != to, suggestions[index].fields[keyPath: key].caseInsensitiveCompare(from) == .orderedSame {
                        suggestions[index].fields[keyPath: key] = to
                        suggestions[index].evidence += "\nApplied an explicitly remembered field correction from this profile."
                    }
                }
            }
        }
        return suggestions
    }
    public static func prepare(_ items: [Item], profile: Profile, memories: [ConfirmedCorrection]) -> [Item] {
        try! prepare(items, profile: profile, memories: memories, cancel: Cancellation())
    }
    public static func prepare(_ items: [Item], profile: Profile, memories: [ConfirmedCorrection], cancel: Cancellation) throws -> [Item] {
        let results = try items.map { input in
            if cancel.cancelled { throw fail("Magic analysis cancelled; existing proposals unchanged.") }
            var item = input
            let options = suggestions(url: item.url, profile: profile, related: items, memories: memories).map { option in
                var enriched = option
                let extra = item.metadata.fillingVideoFields(option.fields, profile: profile, source: item.url)
                enriched.fields = extra.0
                if !extra.1.isEmpty { enriched.evidence += "\n" + extra.1.joined(separator: "\n") }
                return enriched
            }
            item.alternatives = options
            if let first = options.first {
                // Deliberate field edits and overrides are never replaced by an analysis pass.
                if item.overrideBasename == nil && (item.initialFields == nil || item.fields == item.initialFields) {
                    item.fields = first.fields; item.initialFields = first.fields
                    item.overrideBasename = first.overrideBasename
                    item.initialBasename = try? proposedBasename(item, profile: profile)
                }
                item.evidence = first.evidence
                if item.overrideBasename != nil || item.fields != first.fields { item.evidence += "\nYour manual name/field edits have been retained; analysis only adds alternatives." }
                item.confidence = first.confidence
                item.reviewed = false
            }
            if MediaRouting.enabled(profile) { item.evidence += "\n" + MediaRouting.resolve(fields: item.fields, source: item.url, profile: profile).1 }
            return item
        }
        if cancel.cancelled { throw fail("Magic analysis cancelled; existing proposals unchanged.") }
        return results
    }
}
