import Foundation

public struct EmbeddedTag: Identifiable, Equatable {
    public var id = UUID()
    public var key: String
    public var label: String
    public var value: String
    public var component: String?
    public var source: String
    public var binary: Bool
    public init(key: String, label: String, value: String, component: String? = nil, source: String, binary: Bool = false) {
        self.key = key; self.label = label; self.value = value; self.component = component; self.source = source; self.binary = binary
    }
}
public struct EmbeddedMetadata: Equatable {
    public var tags: [EmbeddedTag] = []
    public var notes: [String] = []
    public var video = false
    public init(tags: [EmbeddedTag] = [], notes: [String] = [], video: Bool = false) { self.tags = tags; self.notes = notes; self.video = video }
    public var available: Bool { !tags.isEmpty || !notes.isEmpty }
    public func comparison(_ tag: EmbeddedTag, fields: Fields) -> String {
        guard !tag.binary, let key = tag.component else { return "Additional tag information" }
        let current = FieldCatalog.get(key, fields)
        guard !current.isEmpty else { return "Additional tag information" }
        if key == "Genre", tag.source == "ID3v1" { return ID3Genres.normalized(current).caseInsensitiveCompare(ID3Genres.normalized(tag.value)) == .orderedSame ? "Matches component" : "Differs from component" }
        return Self.comparable(current, key: key) == Self.comparable(tag.value, key: key) ? "Matches component" : "Differs from component"
    }
    private static func comparable(_ input: String, key: String) -> String {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        // Padding/track totals are layout differences. Spelling, punctuation and case remain visible differences.
        if ["TrackNumber", "Season", "Episode"].contains(key), let number = Int(text.components(separatedBy: "/")[0]) { return String(number) }
        if key == "Genre" { return ID3Genres.normalized(text) }
        if key == "Year", text.count >= 4, Int(text.prefix(4)) != nil { return String(text.prefix(4)) }
        return text
    }
    public func summary(fields: Fields) -> String {
        if tags.contains(where: { comparison($0, fields: fields) == "Differs from component" }) { return "Embedded tags differ from filename components" }
        if !notes.isEmpty { return "Embedded metadata details and reading notes" }
        if tags.contains(where: { comparison($0, fields: fields) == "Additional tag information" }) { return "Additional embedded tag information" }
        return "View embedded metadata"
    }
    /// Video only: never replace a nonempty component, and never choose among disagreeing tag values.
    public func fillingVideoFields(_ input: Fields, profile: Profile, source: URL) -> (Fields, [String]) {
        guard video, profile.kind == .video else { return (input, []) }
        var fields = input, evidence: [String] = []
        var mask = PatternEngine.folderMask(for: input, profile: profile) + " " + PatternEngine.filenameMask(for: input, profile: profile)
        if MediaRouting.enabled(profile) {
            guard let context = try? MediaRouting.context(fields: input, source: source, profile: profile, requireDestination: false) else { return (input, []) }
            mask = context.folderMask + " " + context.filenameMask
        }
        let regex = try! NSRegularExpression(pattern: #"\{([A-Za-z]+)[^{}]*\}"#)
        let ns = mask as NSString
        let tokens = Set(regex.matches(in: mask, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range(at: 1)) })
        var wanted = tokens.intersection(["Title", "Year", "Series", "Season", "Episode", "EpisodeTitle", "Resolution", "Genre"])
        if tokens.contains("TitleYear") { wanted.formUnion(["Title", "Year"]) }
        if tokens.contains("EpisodeID") { wanted.formUnion(["Season", "Episode"]) }
        var candidates = Dictionary(grouping: tags.filter { !$0.binary && $0.component != nil }, by: { $0.component! })
        // A video's single title tag can supply an episode title without inventing a second tag in the inspector.
        if !input.series.isEmpty || !input.episode.isEmpty || tags.contains(where: { ["Series", "Season", "Episode"].contains($0.component ?? "") }) {
            if candidates["EpisodeTitle"] == nil { candidates["EpisodeTitle"] = candidates["Title"] }
        }
        for key in wanted.sorted() where FieldCatalog.get(key, fields).isEmpty {
            let values = Set((candidates[key] ?? []).map { Self.comparable($0.value, key: key) }.filter { !$0.isEmpty })
            guard values.count == 1, let value = values.first else { continue }
            if key == "Year", !(Int(value).map { (1900...2100).contains($0) } ?? false) { continue }
            if ["Season", "Episode"].contains(key), !(Int(value).map { (0...9999).contains($0) } ?? false) { continue }
            guard !value.contains("/"), !value.contains(":"), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
            FieldCatalog.set(key, value, &fields); evidence.append(key + " from read-only video metadata: " + value)
        }
        return (fields, evidence)
    }
}
