import Foundation

public struct ROMExtensionMapping: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var extensions: String
    public var system: String
    public init(_ extensions: String, system: String) { self.extensions = extensions; self.system = system }
}
public enum ROMRouting {
    public static var defaults: [ROMExtensionMapping] {
        [ROMExtensionMapping("nes", system: "NES"), .init("sfc, smc", system: "SNES"), .init("gb", system: "Game Boy"), .init("gbc", system: "Game Boy Color"), .init("gba", system: "Game Boy Advance"), .init("n64, z64, v64", system: "Nintendo 64"), .init("nds", system: "Nintendo DS"), .init("3ds", system: "Nintendo 3DS")]
    }
    public static func entries(_ p: Profile) -> [ROMExtensionMapping] { p.romExtensionMappings ?? defaults.filter { PatternEngine.lookup($0.system, profile: p) != nil } }
    public static func validate(_ p: Profile) throws {
        var seen = Set<String>()
        guard entries(p).count <= 200 else { throw fail("Use at most 200 ROM extension mappings.") }
        for entry in entries(p) {
            guard PatternEngine.lookup(entry.system, profile: p) != nil else { throw fail("ROM extension mapping refers to unknown System: \(entry.system). Choose a configured System.") }
            let extensions = UniversalPreferences.entries(entry.extensions)
            guard !extensions.isEmpty else { throw fail("Enter at least one extension for each ROM mapping.") }
            for ext in extensions {
                let normalized = ext.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
                guard normalized.range(of: "^[a-z0-9]+$", options: .regularExpression) != nil, seen.insert(normalized).inserted else { throw fail("Invalid or repeated ROM extension: \(ext)") }
            }
        }
    }
    public static func resolve(_ url: URL, fields: Fields, evidence: String, profile: Profile) -> (Fields, String, Bool) {
        var f = fields
        let mapped = entries(profile).first { UniversalPreferences.entries($0.extensions).contains { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")).caseInsensitiveCompare(url.pathExtension) == .orderedSame } }?.system
        if !f.system.isEmpty {
            if let known = PatternEngine.lookup(f.system, profile: profile) { f.system = known.name }
            let conflict = mapped.map { $0.caseInsensitiveCompare(f.system) != .orderedSame } ?? false
            return (f, evidence + (conflict ? " Filename System differs from extension mapping (\(mapped!)); review System. Explicit filename value retained." : " System read from filename or parent folders."), false)
        }
        if let mapped, let known = PatternEngine.lookup(mapped, profile: profile) {
            f.system = known.name
            return (f, evidence + " System inferred from .\(url.pathExtension): \(known.name). Original filename preserved.", false)
        }
        return (f, evidence + " System cannot be determined from this extension. Use a filename/parent-folder pattern containing {System}, or choose System manually. Original filename preserved.", false)
    }
    /// Disc descriptors and playlists can reference siblings with unrelated basenames.
    /// Until set-level filing exists, never move/copy/rename individual members from such a directory.
    public static func validateOperation(_ url: URL, renaming: Bool) throws {
        let descriptors: Set<String> = ["cue", "m3u", "m3u8", "gdi", "ccd", "mds"]
        let siblings = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        if descriptors.contains(url.pathExtension.lowercased()) || siblings.contains(where: { descriptors.contains($0.pathExtension.lowercased()) }) {
            throw fail("Linked ROM set needs review: this folder contains a disc descriptor or playlist. Individual filing or renaming could break its references. Keep the set together and organize it as a complete folder outside this operation.")
        }
    }
}
