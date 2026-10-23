import Foundation
import CryptoKit

public enum ProfileSetup {
    private static func migrationID(_ profile: UUID, _ index: Int) -> UUID {
        let hash = SHA256.hash(data: Data("\(profile.uuidString)-workspace-pattern-\(index)".utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
        let chars = Array(hash)
        let text = String(chars[0..<8]) + "-" + String(chars[8..<12]) + "-" + String(chars[12..<16]) + "-" + String(chars[16..<20]) + "-" + String(chars[20..<32])
        return UUID(uuidString: text)!
    }
    public static func configured(_ kind: Kind, name: String, subtype: BookSubtype? = nil) -> Profile {
        var profile = Profile(kind, bookSubtype: subtype)
        profile.name = name; profile.schemaVersion = 2; profile.rootAllowed = true
        profile.classifications = PatternEngine.defaultTypes(for: kind)
        profile.workspacePatterns = PatternEngine.defaults(for: profile)
        if kind == .video { profile.mediaRoutingEnabled = false; profile.mediaCategories = MediaRouting.starters; profile.folderMask = "{Title} ({Year?})"; profile.filenameMask = "{Title} ({Year?}) [{Resolution?}]" }
        var rules = profile.rules
        if [.video, .music, .audiobook].contains(kind) { rules.smartTitleCase = true }
        if kind == .video { rules.formatEpisodes = true; profile.removeTokens = "" }
        profile.rules = rules
        profile.extractionMask = ""
        return profile
    }
    /// Upgrade only the exact shipped movie defaults; custom masks and ordered rules are retained.
    public static func updatingVideoDefaults(_ input: Profile) -> Profile {
        guard input.kind == .video else { return input }
        var p = input
        if p.folderMask == "{TitleYear}" || p.folderMask == "{Title} ({Year})" { p.folderMask = "{Title} ({Year?})" }
        if p.filenameMask == "{TitleYear}" || p.filenameMask == "{Title} ({Year}) [{Resolution}]" || p.filenameMask == "{Title} ({Year}) [{Resolution?}]" { p.filenameMask = "{Title} ({Year?}) [{Resolution?}]" }
        if var types = p.classifications {
            for i in types.indices {
                if types[i].name == "Movie", ["{Title} ({Year}) [{Resolution}]", "{Title} ({Year}) [{Resolution?}]"].contains(types[i].filenameMask ?? "") { types[i].filenameMask = "{Title} ({Year?}) [{Resolution?}]" }
                if types[i].name == "Movie", ["Movies/{TitleYear}", "Movies/{Title} ({Year})"].contains(types[i].folderMask ?? "") {
                    types[i].folderMask = "Movies/{Title} ({Year?})"
                    if types[i].filenameMask == nil { types[i].filenameMask = "{Title} ({Year?}) [{Resolution?}]" }
                }
                if types[i].name == "TV Show", types[i].filenameMask == nil {
                    types[i].filenameMask = "{Series} - {EpisodeID} - {EpisodeTitle}"
                }
            }
            p.classifications = types
        }
        if let rules = p.workspacePatterns {
            let current = PatternEngine.defaults(for: p)
            let addedPatterns: Set<String> = ["{EpisodeID} - {Series} - {EpisodeTitle}", "{Series} - {EpisodeTitle} - {EpisodeID}", "{EpisodeIDAnywhere}", "({Year}) - {Title}", "({Year}) {Title}", "{Year} - {Title}", "{ParenthesizedYearAnywhere}"]
            let previous = current.filter { !addedPatterns.contains($0.pattern) }
            let older = previous.filter { !$0.pattern.contains("{Resolution}") }
            if [previous, older].contains(where: { $0.map(\.pattern) == rules.map(\.pattern) && zip($0, rules).allSatisfy { $0.enabled == $1.enabled && $0.assignedType == $1.assignedType && !$1.compatibility } }) {
                p.workspacePatterns = current.map { candidate in rules.first(where: { $0.pattern == candidate.pattern }) ?? candidate }
            }
        }
        return p
    }
    /// Older/custom profiles may lack built-in naming Types required by starter categories.
    /// Supply definitions only: preserve all existing names, aliases, layouts, patterns and mappings.
    public static func addingMissingVideoTypes(_ input: Profile) -> Profile {
        guard MediaRouting.enabled(input) else { return input }
        var profile = input
        let referenced = Set((profile.mediaCategories ?? []).flatMap { [$0.associatedType] + $0.rules.map(\.type) } + (profile.workspacePatterns ?? []).map(\.assignedType))
        let standards = PatternEngine.defaultTypes(for: .video)
        for (index, standard) in standards.enumerated() {
            let requested = referenced.filter { value in
                !value.isEmpty && ([standard.name] + UniversalPreferences.entries(standard.aliases)).contains { $0.caseInsensitiveCompare(value) == .orderedSame }
            }.sorted()
            for name in requested where PatternEngine.lookup(name, profile: profile) == nil {
                var definitions = profile.classifications ?? []
                if let equivalent = ([standard.name] + UniversalPreferences.entries(standard.aliases)).compactMap({ PatternEngine.lookup($0, profile: profile) }).first,
                   let i = definitions.firstIndex(where: { $0.id == equivalent.id }) {
                    definitions[i].aliases = (UniversalPreferences.entries(definitions[i].aliases) + [name]).joined(separator: ", ")
                } else {
                    var definition = standard
                    var seed = 10000 + index
                    while definitions.contains(where: { $0.id == migrationID(profile.id, seed) }) { seed += 10000 }
                    definition.id = migrationID(profile.id, seed)
                    definition.folderMask = nil; definition.filenameMask = nil
                    definitions.append(definition)
                }
                profile.classifications = definitions
            }
        }
        return profile
    }
    public static var starterProfiles: [Profile] {
        var video = configured(.video, name: "Video Media Server")
        var rules = video.rules; rules.episodeCapitalization = .lowercase; rules.formatEpisodes = true; video.rules = rules
        var audio = configured(.audiobook, name: "Audiobooks", subtype: .audiobook)
        audio.folderMask = "{Author}/{SeriesName?}/{BookFolder}"
        audio.filenameMask = "{ChapterOrBook}"
        var parentSeries = WorkspacePattern("{Author}/{Series}/{SeriesNumber} - {BookTitle}"); parentSeries.source = .parentFolders; parentSeries.enabled = false
        var parentBook = WorkspacePattern("{Author}/{BookTitle}"); parentBook.source = .parentFolders; parentBook.enabled = false
        audio.workspacePatterns = [parentSeries, parentBook] + (audio.workspacePatterns ?? [])
        var ebooks = configured(.audiobook, name: "Ebooks & Comics", subtype: .general)
        ebooks.folderMask = "{Author}/{Series?}/{BookFolder}"; ebooks.filenameMask = "{BookTitle}"
        var forge = configured(.documents, name: "FORGE")
        forge.workspacePatterns = [WorkspacePattern("{GameTitle} - {ResourceName}")]
        forge.folderMask = "{GameTitle}"; forge.filenameMask = "{GameTitle} - {ResourceName}"
        return [video, configured(.music, name: "Music"), audio, forge, configured(.roms, name: "ROMs"), configured(.photos, name: "Photos"), configured(.documents, name: "PDF Library"), configured(.software, name: "Software & Installers"), ebooks].map { StarterDescriptions.fillingBlankNotes($0) }
    }
    public static func migrate(_ input: Profile) throws -> Profile {
        if input.schemaVersion >= 2 {
            var current = input
            if current.workspacePatterns?.contains(where: { $0.compatibility }) == true {
                let editable = (current.workspacePatterns ?? []).filter { !$0.compatibility }
                current.workspacePatterns = editable.filter(\.enabled) + PatternEngine.defaults(for: current).filter { candidate in !editable.contains { $0.pattern == candidate.pattern && $0.enabled } } + editable.filter { !$0.enabled }
            }
            if current.rules.hyphensToSpaces || current.rules.lowercaseEpisodeTitle { var cleanup = current.rules; cleanup.hyphensToSpaces = false; cleanup.lowercaseEpisodeTitle = false; current.rules = cleanup }
            current.extractionMask = ""
            return current
        }
        var p = input
        if p.workspacePatterns == nil {
            p.workspacePatterns = PatternEngine.defaults(for: p)
            for index in p.workspacePatterns!.indices { p.workspacePatterns![index].id = migrationID(p.id, index) }
        }
        // New type names are available for review, but none changes an old destination layout.
        if p.classifications == nil { p.classifications = PatternEngine.defaultTypes(for: p.kind).map { type in var inherited = type; inherited.folderMask = nil; return inherited } }
        if input.classifications == nil, var types = p.classifications {
            for index in types.indices { types[index].id = migrationID(p.id, 1000 + index) }
            p.classifications = types
        }
        if !p.fixedCategory.isEmpty {
            try component(p.fixedCategory)
            p.folderMask = p.fixedCategory + (p.folderMask.isEmpty ? "" : "/" + p.folderMask)
            if var types = p.classifications {
                for index in types.indices { if let mask = types[index].folderMask { types[index].folderMask = p.fixedCategory + (mask.isEmpty ? "" : "/" + mask) } }
                p.classifications = types
            }
            p.fixedCategory = ""
        }
        if p.rules.hyphensToSpaces || p.rules.lowercaseEpisodeTitle { var cleanup = p.rules; cleanup.hyphensToSpaces = false; cleanup.lowercaseEpisodeTitle = false; p.rules = cleanup }
        p.extractionMask = ""
        p.rootAllowed = true; p.schemaVersion = 2
        return p
    }
}
public struct SettingsArchive: Codable {
    public var version = 1
    public var created = Date()
    public var profiles: [Profile]
    public var general: UniversalPreferences
    public var activeProfileID: UUID?
    public init(profiles: [Profile], general: UniversalPreferences, activeProfileID: UUID?) {
        self.profiles = profiles; self.general = general; self.activeProfileID = activeProfileID
    }
    public func validatedProfiles() throws -> [Profile] {
        guard version == 1, profiles.count <= 200 else { throw fail("Unsupported or excessive settings archive.") }
        try general.validate()
        guard Set(profiles.map(\.id)).count == profiles.count else { throw fail("Archive contains repeated profile identifiers.") }
        return try profiles.map { profile in
            let migrated = ProfileSetup.addingMissingVideoTypes(try ProfileSetup.migrate(profile))
            // Imported destinations can be offline; normal preview/application guards still validate them.
            var check = migrated; check.root = ""; try check.validate()
            return migrated
        }
    }
}
