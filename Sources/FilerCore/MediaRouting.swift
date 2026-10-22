import Foundation

public struct MediaCategoryRule: Codable, Equatable, Identifiable {
    public var id = UUID()
    /// Both conditions must match when supplied. Rules with no conditions never match.
    public var type = ""
    public var keyword = ""
    public init(type: String = "", keyword: String = "") { self.type = type; self.keyword = keyword }
}
public struct MediaCategory: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var enabled = true
    public var name: String
    public var aliases = ""
    /// nil = unmapped; empty = explicitly use the library root; otherwise one direct child folder.
    public var rootFolder: String?
    public var associatedType = ""
    /// nil inherits Type/profile layout, empty means no subfolders beneath the mapped folder.
    public var folderMask: String?
    public var filenameMask: String?
    public var rules: [MediaCategoryRule] = []
    public init(_ name: String, type: String = "", folderMask: String? = nil, filenameMask: String? = nil, rules: [MediaCategoryRule] = []) {
        self.name = name; self.associatedType = type; self.folderMask = folderMask; self.filenameMask = filenameMask; self.rules = rules
    }
}
public struct MediaRoutingContext {
    public var fields: Fields
    public var rootFolder: String
    public var folderMask: String
    public var filenameMask: String
    public var explanation: String
}
public enum MediaRouting {
    public static var starters: [MediaCategory] {
        let movieName = "{Title} ({Year?}) [{Resolution?}]"
        return [
            MediaCategory("Commercials", type: "Commercial", folderMask: "", filenameMask: "{Title}", rules: [.init(type: "Commercial"), .init(keyword: "commercial"), .init(keyword: "commercials")]),
            MediaCategory("Documentaries", type: "Documentary", folderMask: "{Title} ({Year?})", filenameMask: movieName, rules: [.init(type: "Documentary"), .init(keyword: "documentary"), .init(keyword: "documentaries")]),
            MediaCategory("Home Videos", type: "Home Video", folderMask: "", filenameMask: "{Title}", rules: [.init(type: "Home Video"), .init(keyword: "home video"), .init(keyword: "home videos")]),
            MediaCategory("Movies", type: "Movie", folderMask: "{Title} ({Year?})", filenameMask: movieName, rules: [.init(type: "Movie")]),
            MediaCategory("Music Videos", type: "Music Video", folderMask: "{Title}", filenameMask: "{Title}", rules: [.init(type: "Music Video"), .init(keyword: "music video"), .init(keyword: "music videos")]),
            MediaCategory("TV Shows", type: "TV Show", folderMask: "{Series}/Season {Season:02}", filenameMask: "{Series} - {EpisodeID} - {EpisodeTitle}", rules: [.init(type: "TV Show")])
        ]
    }
    public static func enabled(_ profile: Profile) -> Bool { profile.kind == .video && profile.mediaRoutingEnabled == true }
    public static func lookup(_ name: String, profile: Profile) -> MediaCategory? {
        (profile.mediaCategories ?? []).first { category in
            ([category.name] + UniversalPreferences.entries(category.aliases)).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
    }
    private static func matches(_ rule: MediaCategoryRule, fields: Fields, source: URL, profile: Profile) -> Bool {
        guard !rule.type.isEmpty || !rule.keyword.isEmpty else { return false }
        if !rule.type.isEmpty {
            let canonical = PatternEngine.lookup(fields.type, profile: profile)?.name ?? fields.type
            guard canonical.caseInsensitiveCompare(PatternEngine.lookup(rule.type, profile: profile)?.name ?? rule.type) == .orderedSame else { return false }
        }
        if !rule.keyword.isEmpty {
            let text = source.deletingPathExtension().lastPathComponent.replacingOccurrences(of: #"[._\-]+"#, with: " ", options: .regularExpression)
            let keyword = rule.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty else { return false }
            let words = keyword.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: #"\s+"#)
            guard text.range(of: #"(?<![\p{L}\p{N}])"# + words + #"(?![\p{L}\p{N}])"#, options: [.regularExpression, .caseInsensitive]) != nil else { return false }
        }
        return true
    }
    public static func resolve(fields: Fields, source: URL, profile: Profile) -> (MediaCategory?, String) {
        guard enabled(profile) else { return (nil, "Media Category routing is off; existing Type/profile layouts apply.") }
        if !fields.mediaCategory.isEmpty {
            guard let category = lookup(fields.mediaCategory, profile: profile), category.enabled else { return (nil, "Media Category is unknown or disabled: " + fields.mediaCategory) }
            return (category, "Media Category: \(category.name) — explicitly selected or captured from the filename.")
        }
        let categories = (profile.mediaCategories ?? []).filter(\.enabled)
        // Specific Type+keyword, then keyword-only, then broad Type-only rules.
        for tier in [2, 1, 0] {
            for category in categories {
                for rule in category.rules where (rule.keyword.isEmpty ? 0 : (rule.type.isEmpty ? 1 : 2)) == tier {
                    if matches(rule, fields: fields, source: source, profile: profile) {
                        let reason = [rule.type.isEmpty ? "" : "Type “\(rule.type)”", rule.keyword.isEmpty ? "" : "filename keyword “\(rule.keyword)”"].filter { !$0.isEmpty }.joined(separator: " and ")
                        return (category, "Media Category: \(category.name) — matched \(reason).")
                    }
                }
            }
        }
        if let id = profile.defaultMediaCategoryID, let category = categories.first(where: { $0.id == id }) { return (category, "Media Category: \(category.name) — profile default; no matching rule.") }
        return (nil, "No Media Category matched. Select one or configure a default before filing.")
    }
    public static func context(fields: Fields, source: URL, profile: Profile, requireDestination: Bool = false) throws -> MediaRoutingContext {
        let (category, reason) = resolve(fields: fields, source: source, profile: profile)
        if enabled(profile) && requireDestination && category == nil { throw fail(reason) }
        var effective = fields
        var folder = ""
        if let category {
            effective.mediaCategory = category.name
            if !category.associatedType.isEmpty { effective.type = category.associatedType }
            if requireDestination {
                guard let mapped = category.rootFolder else { throw fail("Choose a destination folder for Media Category “\(category.name)” in Profile Settings → Media Categories.") }
                if !mapped.isEmpty { try component(mapped) }
                folder = mapped
            }
        }
        if requireDestination { try PatternEngine.validateMask(category?.folderMask ?? PatternEngine.folderMask(for: effective, profile: profile), folder: true) }
        return MediaRoutingContext(fields: effective, rootFolder: folder, folderMask: category?.folderMask ?? PatternEngine.folderMask(for: effective, profile: profile), filenameMask: category?.filenameMask ?? PatternEngine.filenameMask(for: effective, profile: profile), explanation: reason)
    }
    public static func validate(_ profile: Profile) throws {
        let categories = profile.mediaCategories ?? []
        guard Set(categories.map(\.id)).count == categories.count else { throw fail("Media Category identifiers must be unique.") }
        var names = Set<String>(), ruleIDs = Set<UUID>()
        for category in categories {
            try component(category.name)
            guard !category.name.hasPrefix("@") else { throw fail("Media Category names cannot begin with @.") }
            for name in [category.name] + UniversalPreferences.entries(category.aliases) {
                guard names.insert(name.lowercased()).inserted else { throw fail("Duplicate Media Category name or alias: " + name) }
            }
            if let folder = category.rootFolder, !folder.isEmpty { try component(folder) }
            if let mask = category.folderMask { try PatternEngine.validateMask(mask, folder: true) }
            if let mask = category.filenameMask { try PatternEngine.validateMask(mask, folder: false) }
            if enabled(profile), category.enabled, !category.associatedType.isEmpty, PatternEngine.lookup(category.associatedType, profile: profile) == nil { throw fail("Media Category “\(category.name)” refers to unknown Type “\(category.associatedType)”. Choose a configured Type or inherit the file’s Type.") }
            for rule in category.rules {
                if enabled(profile), category.enabled, !rule.type.isEmpty, PatternEngine.lookup(rule.type, profile: profile) == nil { throw fail("Media Category “\(category.name)” has a rule for unknown Type “\(rule.type)”. Update the rule or add that Type.") }
                guard ruleIDs.insert(rule.id).inserted else { throw fail("Media Category rule identifiers must be unique.") }
                guard rule.keyword.count <= 500 else { throw fail("Use a keyword or phrase of at most 500 characters.") }
            }
        }
        if enabled(profile), let id = profile.defaultMediaCategoryID {
            guard categories.contains(where: { $0.id == id && $0.enabled }) else { throw fail("Choose an enabled default Media Category or select Needs review.") }
        }
    }
}
