import Foundation

public struct UniversalExceptionGroup: Identifiable {
    public let id: String
    public let title: String
    public let examples: String
    public static let all: [UniversalExceptionGroup] = [
        .init(id: "abbreviations", title: "Abbreviations & acronyms", examples: "DJ, MC, AI, NASA, ISBN"),
        .init(id: "names", title: "People, artists & organizations", examples: "VNV Nation, INXS, ABBA, AiDEN, BBC, HBO"),
        .init(id: "brands", title: "Brands, products & platforms", examples: "iPhone, macOS, GitHub, PlayStation, NES"),
        .init(id: "formats", title: "Formats & technical terms", examples: "1080p, HDR, UHD, FLAC, PDF, EPUB, Wi-Fi"),
        .init(id: "editions", title: "Editions, regions & identifiers", examples: "USA, UK, PAL, NTSC, DLC, GOTY"),
        .init(id: "other", title: "Other preferred spellings", examples: "LaTeX, myCustomName, iMonkey")
    ]
}
public enum HoverTiming: String, Codable, CaseIterable { case immediate, shortDelay, off }
public struct UniversalPreferences: Codable, Equatable {
    public var groups: [String: String] = [:]
    public var flagUnrecognizedWords: Bool?
    public var showFilenameDifferences: Bool?
    public var hoverTiming: HoverTiming?
    public var defaultFilingAction: Mode?
    public var filingAction: Mode { defaultFilingAction == .move ? .move : .copy }
    public var lowercaseTitleWords = PreparationRules().smallWords
    public init(existingExceptions: String = "") { groups["other"] = existingExceptions }
    public static func entries(_ input: String) -> [String] {
        input.components(separatedBy: CharacterSet(charactersIn: ",\n\r"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    public var allEntries: [String] { UniversalExceptionGroup.all.flatMap { Self.entries(groups[$0.id] ?? "") } }
    public var combinedEntries: [String] {
        var seen = Set<String>()
        return allEntries.filter { seen.insert($0).inserted }
    }
    public var combined: String { combinedEntries.joined(separator: ", ") }
    public var conflicts: [String] {
        var seen: [String: String] = [:], result: [String] = []
        for entry in allEntries {
            let key = entry.lowercased()
            if let old = seen[key], old != entry {
                let message = "“\(old)” and “\(entry)” specify different preferred case."
                if !result.contains(message) { result.append(message) }
            } else { seen[key] = entry }
        }
        return result
    }
    public var titleWords: String {
        var seen = Set<String>()
        return Self.entries(lowercaseTitleWords).map { $0.lowercased() }.filter { seen.insert($0).inserted }.joined(separator: ", ")
    }
    public func overlaps(removableLabels: String) -> [String] {
        let removed = Set(Self.entries(removableLabels).map { $0.lowercased() })
        return combinedEntries.filter { removed.contains($0.lowercased()) }
    }
    public func validate() throws {
        if let conflict = conflicts.first { throw fail(conflict) }
        guard allEntries.count <= 5000 else { throw fail("Use at most 5,000 exception entries.") }
        for entry in allEntries {
            guard entry.utf8.count <= 240, !entry.contains("/"), !entry.contains(":"), !entry.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw fail("Exceptions must be filename text, at most 240 bytes, without path separators or control characters: \(entry)")
            }
        }
    }
}
