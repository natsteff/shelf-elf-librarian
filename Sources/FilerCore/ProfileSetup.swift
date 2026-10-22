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
        if kind == .video { profile.folderMask = "{Title} ({Year})"; profile.filenameMask = "{Title} ({Year}) [{Resolution}]" }
        profile.extractionMask = ""
        return profile
    }
    /// Upgrade only the exact shipped movie defaults; custom masks and ordered rules are retained.
    public static func updatingVideoDefaults(_ input: Profile) -> Profile {
        guard input.kind == .video else { return input }
        var p = input
        if p.folderMask == "{TitleYear}" { p.folderMask = "{Title} ({Year})" }
        if p.filenameMask == "{TitleYear}" { p.filenameMask = "{Title} ({Year}) [{Resolution}]" }
        if var types = p.classifications {
            for i in types.indices {
                if types[i].name == "Movie", types[i].folderMask == "Movies/{TitleYear}" {
                    types[i].folderMask = "Movies/{Title} ({Year})"
                    if types[i].filenameMask == nil { types[i].filenameMask = "{Title} ({Year}) [{Resolution}]" }
                }
                if types[i].name == "TV Show", types[i].filenameMask == nil {
                    types[i].filenameMask = "{Series} - {EpisodeID} - {EpisodeTitle}"
                }
            }
            p.classifications = types
        }
        if var rules = p.workspacePatterns, rules.map(\.pattern) == PatternEngine.defaults(for: p).filter({ !$0.pattern.contains("{Resolution}") }).map(\.pattern), let fallback = rules.firstIndex(where: { $0.pattern == "{Title} [{Type}]" }) {
            let additions = PatternEngine.defaults(for: p).filter { candidate in candidate.pattern.contains("{Resolution}") && !rules.contains(where: { $0.pattern == candidate.pattern }) }
            rules.insert(contentsOf: additions, at: fallback)
            p.workspacePatterns = rules
        }
        return p
    }
    public static var starterProfiles: [Profile] {
        var video = configured(.video, name: "Video Media Server")
        var rules = video.rules; rules.episodeCapitalization = .lowercase; rules.formatEpisodes = true; video.rules = rules
        var audio = configured(.audiobook, name: "Audiobooks", subtype: .audiobook)
        audio.folderMask = "{Author}/{Series?}/{BookFolder}"
        audio.filenameMask = "{ChapterOrBook}"
        var parentSeries = WorkspacePattern("{Author}/{Series}/{SeriesNumber} - {BookTitle}"); parentSeries.source = .parentFolders; parentSeries.enabled = false
        var parentBook = WorkspacePattern("{Author}/{BookTitle}"); parentBook.source = .parentFolders; parentBook.enabled = false
        audio.workspacePatterns = [parentSeries, parentBook] + (audio.workspacePatterns ?? [])
        var ebooks = configured(.audiobook, name: "Ebooks & Comics", subtype: .general)
        ebooks.folderMask = "{Author}/{Series?}/{BookFolder}"; ebooks.filenameMask = "{BookTitle}"
        var forge = configured(.documents, name: "FORGE")
        forge.workspacePatterns = [WorkspacePattern("{Game} - {Title}")]
        forge.folderMask = "{Game}"; forge.filenameMask = "{Game} - {Title}"
        return [video, configured(.music, name: "Music"), audio, forge, configured(.roms, name: "ROMs"), configured(.photos, name: "Photos"), configured(.documents, name: "PDF Library"), configured(.software, name: "Software & Installers"), ebooks].map { StarterDescriptions.fillingBlankNotes($0) }
    }
    public static func migrate(_ input: Profile) throws -> Profile {
        guard input.schemaVersion < 2 else { return input }
        var p = input
        if p.workspacePatterns == nil {
            var compatibility = WorkspacePattern("Existing " + p.kind.label + " interpretation", compatibility: true)
            compatibility.id = p.id
            var suggested = PatternEngine.defaults(for: p)
            if !p.extractionMask.isEmpty { suggested.insert(WorkspacePattern(p.extractionMask), at: 0) }
            for index in suggested.indices { suggested[index].enabled = false; suggested[index].id = migrationID(p.id, index) }
            p.workspacePatterns = [compatibility] + suggested
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
            let migrated = try ProfileSetup.migrate(profile)
            // Imported destinations can be offline; normal preview/application guards still validate them.
            var check = migrated; check.root = ""; try check.validate()
            return migrated
        }
    }
}
