import Foundation

public enum PatternSource: String, Codable { case filename, parentFolders }
public struct WorkspacePattern: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var enabled = true
    public var source: PatternSource?
    public var pattern: String
    /// Empty = unspecified, @capture = captured component, otherwise a configured classification name.
    public var assignedType: String
    /// Explicit compatibility row retains the older permissive parser for migrated profiles.
    public var compatibility: Bool
    public init(_ pattern: String, type: String = "", compatibility: Bool = false) {
        self.pattern = pattern; self.assignedType = type; self.compatibility = compatibility
    }
}
public struct FilingType: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var name: String
    public var aliases: String
    /// nil inherits the profile mask; an empty folder mask means the library root.
    public var folderMask: String?
    public var filenameMask: String?
    public init(_ name: String, aliases: String = "", folderMask: String? = nil, filenameMask: String? = nil) {
        self.name = name; self.aliases = aliases; self.folderMask = folderMask; self.filenameMask = filenameMask
    }
}
public enum FieldCatalog {
    public static func normalizedResolution(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d+[pPiI]$"#, options: .regularExpression) != nil ? trimmed.lowercased() : trimmed
    }
    public static let keys: [String: WritableKeyPath<Fields, String>] = [
        "MediaCategory": \.mediaCategory, "Resolution": \.resolution, "Title": \.title, "Year": \.year, "Artist": \.artist, "Album": \.album,
        "Author": \.author, "BookTitle": \.bookTitle, "ChapterNumber": \.chapterNumber, "ChapterTitle": \.chapterTitle,
        "Series": \.series, "Season": \.season, "Episode": \.episode, "EpisodeTitle": \.episodeTitle,
        "Date": \.date, "Revision": \.revision, "Narrator": \.narrator, "Publisher": \.publisher,
        "Illustrator": \.illustrator, "IssueNumber": \.issueNumber, "Volume": \.volume, "SeriesNumber": \.seriesNumber,
        "TrackNumber": \.trackNumber, "RecordingType": \.recordingType, "Type": \.type, "System": \.system,
        "Genre": \.genre, "Game": \.game, "Product": \.product, "Version": \.version, "Platform": \.platform,
        "Architecture": \.architecture, "DateTaken": \.dateTaken, "Event": \.event, "Region": \.region, "Edition": \.edition
    ]
    public static func values(_ f: Fields) -> [String: String] { keys.mapValues { f[keyPath: $0] }.merging(f.custom ?? [:]) { known, _ in known } }
    public static func get(_ key: String, _ f: Fields) -> String { keys[key].map { f[keyPath: $0] } ?? f.custom?[key] ?? "" }
    public static func set(_ key: String, _ value: String, _ f: inout Fields) { if let path = keys[key] { f[keyPath: path] = key == "Resolution" ? normalizedResolution(value) : value } else { var custom = f.custom ?? [:]; custom[key] = value; f.custom = custom } }
}
public enum PatternEngine {
    public static func classificationKey(_ p: Profile) -> String { p.classificationComponent ?? (p.kind == .roms ? "System" : p.kind == .music ? "Genre" : "Type") }
    public static func lookup(_ value: String, profile: Profile) -> FilingType? {
        (profile.classifications ?? []).first { entry in
            ([entry.name] + UniversalPreferences.entries(entry.aliases)).contains { $0.caseInsensitiveCompare(value) == .orderedSame }
        }
    }
    public static func validateClassification(_ f: Fields, profile: Profile) throws {
        let value = FieldCatalog.get(classificationKey(profile), f)
        if !value.isEmpty && lookup(value, profile: profile) == nil {
            throw fail("Unrecognized \(classificationKey(profile)): \(value). Select or add a configured value before filing.")
        }
    }
    public static func folderMask(for f: Fields, profile p: Profile) -> String {
        lookup(FieldCatalog.get(classificationKey(p), f), profile: p)?.folderMask ?? p.folderMask
    }
    public static func filenameMask(for f: Fields, profile p: Profile) -> String {
        lookup(FieldCatalog.get(classificationKey(p), f), profile: p)?.filenameMask ?? p.filenameMask
    }
    private struct Capture { let key: String; let group: Int }
    private static let cacheLock = NSLock()
    private static var regexCache: [String: (NSRegularExpression, [Capture])] = [:]
    private static func compiled(_ pattern: String) throws -> (NSRegularExpression, [Capture]) {
        cacheLock.lock(); let cached = regexCache[pattern]; cacheLock.unlock()
        if let cached { return cached }
        guard !pattern.isEmpty, pattern.utf8.count <= 2000 else { throw fail("Enter a filename pattern of at most 2,000 bytes.") }
        let tokens = try NSRegularExpression(pattern: #"\{([^{}]+)\}"#)
        let ns = pattern as NSString
        var expression = "^", end = 0, captures: [Capture] = [], seen = Set<String>(), group = 1
        for token in tokens.matches(in: pattern, range: NSRange(location: 0, length: ns.length)) {
            let literal = ns.substring(with: NSRange(location: end, length: token.range.location - end))
            guard !literal.contains("{") && !literal.contains("}") else { throw fail("Unbalanced braces in pattern.") }
            expression += NSRegularExpression.escapedPattern(for: literal)
            let key = ns.substring(with: token.range(at: 1))
            guard seen.insert(key).inserted else { throw fail("Use each captured component once: \(key)") }
            if key == "EpisodeID" {
                expression += #"([sS]\s*\d{1,3}\s*[eE]\s*\d{1,3})"#
            } else {
                guard FieldCatalog.keys[key] != nil || key.range(of: "^[A-Za-z][A-Za-z0-9]{0,39}$", options: .regularExpression) != nil else { throw fail("Invalid input component: \(key)") }
                if key == "Year" { expression += #"((?:(?:19|20)\d{2}|2100))"# }
                else if key == "Resolution" { expression += #"(\d{3,4}[pPiI])"# }
                else if ["Season", "Episode", "ChapterNumber", "TrackNumber", "SeriesNumber", "IssueNumber", "Volume"].contains(key) { expression += #"(\d+(?:\.\d+)?)"# }
                else { expression += "(.+?)" }
            }
            captures.append(Capture(key: key, group: group)); group += 1
            end = token.range.location + token.range.length
        }
        let tail = ns.substring(from: end)
        guard !tail.contains("{") && !tail.contains("}") else { throw fail("Unbalanced braces in pattern.") }
        expression += NSRegularExpression.escapedPattern(for: tail) + "$"
        let result = (try NSRegularExpression(pattern: expression, options: [.caseInsensitive]), captures)
        cacheLock.lock()
        if regexCache.count >= 500 { regexCache.removeAll(keepingCapacity: true) }
        regexCache[pattern] = result; cacheLock.unlock()
        return result
    }
    public static func validate(_ profile: Profile) throws {
        guard ["Type", "System", "Genre"].contains(classificationKey(profile)) else { throw fail("Choose Type, System or Genre as the classification component.") }
        guard (profile.workspacePatterns?.count ?? 0) <= 200, (profile.classifications?.count ?? 0) <= 200 else { throw fail("Use at most 200 patterns and 200 classifications per profile.") }
        guard Set((profile.workspacePatterns ?? []).map(\.id)).count == (profile.workspacePatterns ?? []).count,
              Set((profile.classifications ?? []).map(\.id)).count == (profile.classifications ?? []).count else { throw fail("Pattern and classification identifiers must be unique within a profile.") }
        var names = Set<String>()
        for entry in profile.classifications ?? [] {
            try component(entry.name)
            guard !["@add", "@mixed", "@capture"].contains(entry.name) else { throw fail("Choose a classification name without a reserved action value.") }
            for name in [entry.name] + UniversalPreferences.entries(entry.aliases) {
                guard names.insert(name.lowercased()).inserted else { throw fail("Classification name or alias is repeated: \(name)") }
            }
            if let mask = entry.folderMask { try validateMask(mask, folder: true) }
            if let mask = entry.filenameMask { try validateMask(mask, folder: false) }
        }
        for rule in profile.workspacePatterns ?? [] {
            if !rule.compatibility { _ = try compiled(rule.pattern) }
            if rule.assignedType == "@capture" {
                guard rule.pattern.contains("{" + classificationKey(profile) + "}") else { throw fail("Read from filename requires {\(classificationKey(profile))} in the pattern.") }
            } else if !rule.assignedType.isEmpty && lookup(rule.assignedType, profile: profile) == nil {
                throw fail("Pattern refers to an unknown classification: \(rule.assignedType)")
            }
        }
        try validateMask(profile.folderMask, folder: true)
        try validateMask(profile.filenameMask, folder: false)
    }
    public static func validateMask(_ mask: String, folder: Bool) throws {
        guard !mask.hasPrefix("/"), !mask.contains(":".description + "/"), !mask.contains("\\"), !mask.components(separatedBy: "/").contains("..") else { throw fail("Output masks must remain inside the library root.") }
        if !folder && (mask.isEmpty || mask.contains("/")) { throw fail("Filename mask must be a nonempty filename, without folders.") }
        let tokens = try NSRegularExpression(pattern: #"\{([^{}]+)\}"#)
        let extra = Set(["BookFolder", "TitleYear", "AlbumOrIndividual", "Bucket", "ChapterOrBook", "Live", "EpisodeID", "Season:02", "Episode:02", "ChapterNumber:02", "TrackNumber:02"])
        for token in tokens.matches(in: mask, range: NSRange(mask.startIndex..., in: mask)) {
            let key = (mask as NSString).substring(with: token.range(at: 1)).replacingOccurrences(of: "?", with: "")
            guard FieldCatalog.keys[key] != nil || extra.contains(key) || key.range(of: "^[A-Za-z][A-Za-z0-9]{0,39}$", options: .regularExpression) != nil else { throw fail("Unsupported output component: \(key)") }
        }
        let remainder = tokens.stringByReplacingMatches(in: mask, range: NSRange(mask.startIndex..., in: mask), withTemplate: "X")
        guard !remainder.contains("{") && !remainder.contains("}") else { throw fail("Unbalanced braces in output mask.") }
    }
    public static func interpret(_ url: URL, profile p: Profile, record: ((String) -> Void)? = nil) -> (Fields, String, Bool) {
        let original = url.deletingPathExtension().lastPathComponent
        for (index, rule) in (p.workspacePatterns ?? []).enumerated() where rule.enabled {
            if rule.compatibility {
                var legacy = p; legacy.workspacePatterns = nil
                let result = Names.legacyInterpret(url, legacy, record: record)
                return (result.0, "Pattern \(index + 1): compatibility interpretation. " + result.1, result.2)
            }
            let input: String
            if rule.source == .parentFolders {
                let levels = rule.pattern.components(separatedBy: "/").count
                input = url.deletingLastPathComponent().pathComponents.suffix(levels).joined(separator: "/")
            } else { input = original }
            let episodeCandidates = (try? NSRegularExpression(pattern: #"(?i)(?<![\p{L}\p{N}])s\d{1,3}\s*e\d{1,3}(?![\p{L}\p{N}])"#))?.matches(in: input, range: NSRange(input.startIndex..., in: input)).count ?? 0
            let inputYearCandidates = (try? NSRegularExpression(pattern: #"(?<!\d)(?:(?:19|20)\d{2}|2100)(?!\d)"#))?.matches(in: input, range: NSRange(input.startIndex..., in: input)).count ?? 0
            // Explicit editable recognition rules, evaluated in the same order as ordinary masks.
            if rule.pattern == "{EpisodeIDAnywhere}" || rule.pattern == "{ParenthesizedYearAnywhere}" {
                let episode = rule.pattern == "{EpisodeIDAnywhere}"
                let expression = episode ? #"(?i)(?<![\p{L}\p{N}])s(\d{1,3})\s*e(\d{1,3})(?![\p{L}\p{N}])"# : #"\(((?:(?:19|20)\d{2}|2100))\)"#
                let regex = try! NSRegularExpression(pattern: expression)
                let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))
                guard matches.count == 1, let match = matches.first, episode || inputYearCandidates == 1 else { continue }
                var f = Fields()
                let remainder = (input as NSString).replacingCharacters(in: match.range, with: " ")
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-–—")))
                if episode {
                    f.season = (input as NSString).substring(with: match.range(at: 1))
                    f.episode = (input as NSString).substring(with: match.range(at: 2))
                    let sections = remainder.components(separatedBy: " - ").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    if sections.count == 2 { f.series = Names.cleanField(sections[0], p); f.episodeTitle = Names.cleanField(sections[1], p) }
                    else { f.episodeTitle = Names.cleanField(remainder, p) }
                } else {
                    f.year = (input as NSString).substring(with: match.range(at: 1))
                    f.title = Names.cleanField(remainder.replacingOccurrences(of: #"\s+-\s*$|^\s*-\s+"#, with: "", options: .regularExpression), p)
                }
                if !rule.assignedType.isEmpty && rule.assignedType != "@capture" { FieldCatalog.set(classificationKey(p), rule.assignedType, &f) }
                record?("Workspace pattern \(index + 1)")
                return (f, "Pattern \(index + 1): \(rule.pattern). " + (episode ? "Explicit episode marker; review Series and Episode title. Missing or ambiguous series requires review." : "One explicit parenthesized year; review title."), false)
            }
            let delimiterExceptions = UniversalPreferences.entries(p.exceptions).filter { $0.contains("-") && !rule.pattern.localizedCaseInsensitiveContains($0) }.joined(separator: ", ")
            let protected = ProtectedSpellings(input, exceptions: delimiterExceptions)
            let matchingInput = protected.text
            guard let (regex, captures) = try? compiled(rule.pattern), let match = regex.firstMatch(in: matchingInput, range: NSRange(matchingInput.startIndex..., in: matchingInput)) else { continue }
            let yearCandidates = (try? NSRegularExpression(pattern: #"(?<!\d)(?:(?:19|20)\d{2}|2100)(?!\d)"#))?.matches(in: input, range: NSRange(input.startIndex..., in: input)).count ?? 0
            if captures.contains(where: { $0.key == "Year" }) && yearCandidates > 1 { continue }
            if captures.contains(where: { $0.key == "EpisodeID" }) && episodeCandidates > 1 { continue }
            var f = Fields()
            for capture in captures {
                let raw = protected.restore((matchingInput as NSString).substring(with: match.range(at: capture.group)))
                if capture.key == "EpisodeID", let ep = Names.episodeComponents("Show - " + raw + " - Title", profile: p) {
                    f.season = ep.season; f.episode = ep.episode
                } else {
                    let literalFields = ["MediaCategory", "Resolution", "Type", "System", "Genre", "Year", "Season", "Episode", "SeriesNumber", "Version", "Architecture", "Platform", "DateTaken", "Region", "Edition"]
                    let preferred = ProtectedSpellings(raw.trimmingCharacters(in: .whitespaces), exceptions: p.exceptions)
                    FieldCatalog.set(capture.key, literalFields.contains(capture.key) ? preferred.restore(preferred.text) : Names.cleanField(raw, p, record: record), &f)
                }
            }
            if rule.source == .parentFolders && p.kind == .audiobook {
                let chapters = try? NSRegularExpression(pattern: #"^(\d+) - (.+)$"#)
                if let match = chapters?.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)) {
                    f.chapterNumber = (original as NSString).substring(with: match.range(at: 1)); f.chapterTitle = Names.cleanField((original as NSString).substring(with: match.range(at: 2)), p)
                }
            }
            if p.kind == .software || p.kind == .photos { f.title = Names.cleanField(original, p, record: record) }
            if p.kind == .audiobook { if f.bookTitle.isEmpty { f.bookTitle = f.title }; f.title = f.bookTitle }
            if p.kind == .video && !f.season.isEmpty && !f.episode.isEmpty { f.title = "" }
            let key = classificationKey(p)
            if !rule.assignedType.isEmpty && rule.assignedType != "@capture" { FieldCatalog.set(key, rule.assignedType, &f) }
            else if rule.assignedType.isEmpty { FieldCatalog.set(key, "", &f) }
            let captured = FieldCatalog.get(key, f)
            var warning = yearCandidates > 1 && p.kind == .video ? " Multiple possible years; review Year rather than choosing automatically." : ""
            if let known = lookup(captured, profile: p) { FieldCatalog.set(key, known.name, &f) }
            else if !captured.isEmpty { warning = " Unrecognized \(key): \(captured); choose or add a value before filing." }
            f.artist = RuleEngine.artistName(f.artist, profile: p)
            Names.enrichYearAndRecording(&f, profile: p)
            record?("Workspace pattern \(index + 1)")
            return (f, "Pattern \(index + 1): \(rule.pattern)." + warning, false)
        }
        var f = Fields(); f.title = Names.cleanField(original, p, record: record)
        return (f, "No enabled workspace filename pattern matched. Original basename retained as Title; review components before filing.", false)
    }
    public static func defaults(for p: Profile) -> [WorkspacePattern] {
        switch p.kind {
        case .video: return [WorkspacePattern("{EpisodeID} - {Series} - {EpisodeTitle}", type: "TV Show"), WorkspacePattern("{Series} - {EpisodeTitle} - {EpisodeID}", type: "TV Show"), WorkspacePattern("{Series} - {EpisodeID} - {EpisodeTitle}", type: "TV Show"), WorkspacePattern("{Series} - {EpisodeID}", type: "TV Show"), WorkspacePattern("{EpisodeIDAnywhere}", type: "TV Show"), WorkspacePattern("Commercial - {Title} ({Year})", type: "Commercial"), WorkspacePattern("Commercial - {Title}", type: "Commercial"), WorkspacePattern("Documentary - {Title} ({Year})", type: "Documentary"), WorkspacePattern("Documentary - {Title}", type: "Documentary"), WorkspacePattern("{Title} [Commercial]", type: "Commercial"), WorkspacePattern("{Title} ({Year}) [{Resolution}]", type: "Movie"), WorkspacePattern("{Title} ({Year}) {Resolution}", type: "Movie"), WorkspacePattern("{Title} {Year} [{Resolution}]", type: "Movie"), WorkspacePattern("{Title} {Year} {Resolution}", type: "Movie"), WorkspacePattern("({Year}) - {Title}", type: "Movie"), WorkspacePattern("({Year}) {Title}", type: "Movie"), WorkspacePattern("{Year} - {Title}", type: "Movie"), WorkspacePattern("{ParenthesizedYearAnywhere}", type: "Movie"), WorkspacePattern("{Title} [{Type}]", type: "@capture"), WorkspacePattern("{Title} ({Year})", type: "Movie"), WorkspacePattern("{Title} {Year}", type: "Movie"), WorkspacePattern("{Title}", type: "Movie")]
        case .music: return [WorkspacePattern("{TrackNumber} - {Artist} - {Title}"), WorkspacePattern("{Artist} - {Title}"), WorkspacePattern("{Title}")]
        case .audiobook: return [WorkspacePattern("{Author} - {Series} - {SeriesNumber} - {BookTitle}"), WorkspacePattern("{Author} - {Series} - #{SeriesNumber} - {BookTitle}"), WorkspacePattern("{Author} - {BookTitle} - {ChapterNumber}"), WorkspacePattern("{ChapterNumber} - {ChapterTitle}"), WorkspacePattern("{Author} - {BookTitle}"), WorkspacePattern("{BookTitle}")]
        case .roms: return [WorkspacePattern("{Title} [{System}]", type: "@capture"), WorkspacePattern("{Title}")]
        case .software: return [WorkspacePattern("{Product} - {Version} [{Platform}]"), WorkspacePattern("{Product} - {Version}"), WorkspacePattern("{Product}")]
        case .photos: return [WorkspacePattern("{DateTaken} - {Event} - {Title}"), WorkspacePattern("{Title}")]
        case .documents, .other: return [WorkspacePattern("{Title}")]
        }
    }
    public static func defaultTypes(for kind: Kind) -> [FilingType] {
        if kind == .video {
            return [FilingType("Movie", aliases: "Movies", folderMask: "Movies/{Title} ({Year?})", filenameMask: "{Title} ({Year?}) [{Resolution?}]"), FilingType("TV Show", aliases: "TV, TV Shows", folderMask: "TV Shows/{Series}/Season {Season:02}", filenameMask: "{Series} - {EpisodeID} - {EpisodeTitle}"), FilingType("Documentary", aliases: "Documentaries", folderMask: "Documentaries/{TitleYear}"), FilingType("Commercial", aliases: "Commercials", folderMask: "Commercials"), FilingType("Home Video", aliases: "Home Videos", folderMask: "Home Videos"), FilingType("Music Video", aliases: "Music Videos", folderMask: "Music Videos/{Title}"), FilingType("TV Show (Children)", folderMask: "TV Shows (Children)/{Series}/Season {Season:02}"), FilingType("Movie (Children)", folderMask: "Movies (Children)/{TitleYear}")]
        }
        if kind == .roms { return [FilingType("NES", aliases: "Nintendo Entertainment System"), FilingType("SNES", aliases: "Super Nintendo, SFC"), FilingType("Game Boy", aliases: "GB"), FilingType("Game Boy Color", aliases: "GBC"), FilingType("Game Boy Advance", aliases: "GBA"), FilingType("Nintendo 64", aliases: "N64"), FilingType("Nintendo DS", aliases: "NDS"), FilingType("PlayStation", aliases: "PS1, PSX"), FilingType("PlayStation 2", aliases: "PS2"), FilingType("Genesis", aliases: "Mega Drive")] }
        return []
    }
}
