import Foundation

public enum RuleTarget: String, Codable, CaseIterable, Identifiable {
    case filename, folder, both
    public var id: String { rawValue }
}
public enum ReplacementPosition: String, Codable, CaseIterable, Identifiable { case anywhere, prefix, suffix; public var id: String { rawValue } }
public struct ReplacementRule: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var find = ""
    public var replacement = ""
    public var target: RuleTarget = .filename
    public var position: ReplacementPosition?
    public var enabled = true
    public init(find: String = "", replacement: String = "", target: RuleTarget = .filename) { self.find = find; self.replacement = replacement; self.target = target }
}
public enum EpisodeCapitalization: String, Codable, CaseIterable, Identifiable {
    case keep, uppercase, lowercase
    public var id: String { rawValue }
    public var label: String { switch self { case .keep: return "Keep original"; case .uppercase: return "Uppercase (S01E01)"; case .lowercase: return "Lowercase (s01e01)" } }
}
public struct PreparationRules: Codable, Equatable {
    public var hyphensToSpaces = false
    public var dotsToDashes = false
    public var folderHyphensToSpaces = false
    public var folderTitleCase: Bool?
    public var formatEpisodes = false
    public var lowercaseEpisodes = false // Legacy storage, superseded by episodeCapitalization.
    public var episodeCapitalization: EpisodeCapitalization?
    public var episodeCase: EpisodeCapitalization { episodeCapitalization ?? (lowercaseEpisodes ? .lowercase : .keep) }
    public var lowercaseEpisodeTitle = false
    public var smartTitleCase = false
    public var smallWords = "a, an, and, as, at, but, by, for, from, in, nor, of, on, or, per, the, to, vs, via, with"
    public var numericBucket = "0-9"
    public var symbolBucket = "#"
    public var ignoreLeadingThe = false
    public var replacements: [ReplacementRule] = []
    public var useMagic = false
    public init() {}
    public func validate() throws {
        try component(numericBucket); try component(symbolBucket)
        guard replacements.count <= 100 else { throw fail("Use at most 100 replacement rules per profile.") }
        for r in replacements where r.enabled {
            guard !r.find.isEmpty, r.find.utf8.count <= 240, r.replacement.utf8.count <= 240 else { throw fail("Each enabled replacement needs nonempty Find text of at most 240 bytes.") }
            guard !r.replacement.contains("/"), !r.replacement.contains(":"), !r.replacement.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw fail("Replacement text cannot insert path separators or control characters.") }
        }
    }
}
public struct EpisodeMatch: Equatable {
    public let series: String, season: String, episode: String, title: String
    public func identifier(lowercase: Bool) -> String { String(format: lowercase ? "s%02de%02d" : "S%02dE%02d", Int(season) ?? 0, Int(episode) ?? 0) }
}
public enum RuleEngine {
    private static let episodePattern = #"(?i)(?<![\p{L}\p{N}])s[ _]*(\d{1,3})[ ._-]*e[ _]*(\d{1,3})(?![\p{L}\p{N}])"#
    public static func episodeTokens(_ name: String) -> [(range: NSRange, raw: String, season: String, episode: String)] {
        guard let regex = try? NSRegularExpression(pattern: episodePattern) else { return [] }
        let ns = name as NSString
        return regex.matches(in: name, range: NSRange(location: 0, length: ns.length)).map {
            (range: $0.range, raw: ns.substring(with: $0.range), season: ns.substring(with: $0.range(at: 1)), episode: ns.substring(with: $0.range(at: 2)))
        }
    }
    public static func normalizeEpisodeSpacing(_ name: String) -> String {
        guard let re = try? NSRegularExpression(pattern: episodePattern) else { return name }
        var result = name
        let ns = name as NSString
        for match in re.matches(in: name, range: NSRange(location: 0, length: ns.length)).reversed() {
            let raw = ns.substring(with: match.range)
            let letters = raw.filter { $0.isLetter }
            let token = String(letters.first ?? "S") + ns.substring(with: match.range(at: 1)) + String(letters.last ?? "E") + ns.substring(with: match.range(at: 2))
            result = (result as NSString).replacingCharacters(in: match.range, with: token)
        }
        return result
    }
    public static func episode(_ name: String) -> EpisodeMatch? {
        guard let re = try? NSRegularExpression(pattern: episodePattern), let m = re.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { return nil }
        let ns = name as NSString
        let trim = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "._-"))
        return EpisodeMatch(series: ns.substring(to: m.range.location).trimmingCharacters(in: trim), season: ns.substring(with: m.range(at: 1)), episode: ns.substring(with: m.range(at: 2)), title: ns.substring(from: m.range.location + m.range.length).trimmingCharacters(in: trim))
    }
    public static func protectEpisodes(_ value: String, _ transform: (String) -> String, lowercase: Bool = false, capitalization: EpisodeCapitalization? = nil) -> String {
        guard let re = try? NSRegularExpression(pattern: episodePattern) else { return transform(value) }
        var result = "", offset = 0
        let ns = value as NSString
        for m in re.matches(in: value, range: NSRange(location: 0, length: ns.length)) {
            result += transform(ns.substring(with: NSRange(location: offset, length: m.range.location - offset)))
            let raw = ns.substring(with: m.range)
            if let capitalization {
                switch capitalization {
                case .keep: result += raw
                case .uppercase: result += raw.uppercased()
                case .lowercase: result += raw.lowercased()
                }
            } else { result += String(format: lowercase ? "s%02de%02d" : "S%02dE%02d", Int(ns.substring(with: m.range(at: 1))) ?? 0, Int(ns.substring(with: m.range(at: 2))) ?? 0) }
            offset = m.range.location + m.range.length
        }
        result += transform(ns.substring(from: offset)); return result
    }
    public static func formattedEpisodeID(source: String, season: String, episode: String, policy: EpisodeCapitalization) -> String {
        let padded = String(format: "S%02dE%02d", Int(season) ?? 0, Int(episode) ?? 0)
        if policy == .lowercase { return padded.lowercased() }
        if policy == .uppercase { return padded }
        guard let re = try? NSRegularExpression(pattern: episodePattern), let match = re.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return padded }
        let raw = (source as NSString).substring(with: match.range)
        let letters = raw.filter { $0.isLetter }
        return String(letters.first ?? "S") + String(format: "%02d", Int(season) ?? 0) + String(letters.last ?? "E") + String(format: "%02d", Int(episode) ?? 0)
    }
    public static func titleCase(_ value: String, smallWords: String) -> String {
        let small = Set(smallWords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        guard let re = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#) else { return value.capitalized }
        let matches = re.matches(in: value, range: NSRange(value.startIndex..., in: value))
        var result = value
        for (i, m) in matches.enumerated().reversed() {
            let word = (value as NSString).substring(with: m.range)
            let preceding = (value as NSString).substring(to: m.range.location).trimmingCharacters(in: .whitespaces)
            let startsPart = preceding.hasSuffix(":") || preceding.hasSuffix(" -") || preceding.hasSuffix("–") || preceding.hasSuffix("—")
            let replacement = i > 0 && i < matches.count - 1 && !startsPart && small.contains(word.lowercased()) ? word.lowercased() : word.capitalized
            result = (result as NSString).replacingCharacters(in: m.range, with: replacement)
        }
        return result
    }
    public static func applyReplacements(_ value: String, rules: PreparationRules, target: RuleTarget) -> String {
        rules.replacements.filter { $0.enabled && !$0.find.isEmpty && ($0.target == target || $0.target == .both) }.reduce(value) { text, rule in
            switch rule.position ?? .anywhere {
            case .anywhere: return text.replacingOccurrences(of: rule.find, with: rule.replacement)
            case .prefix: return text.hasPrefix(rule.find) ? rule.replacement + String(text.dropFirst(rule.find.count)) : text
            case .suffix: return text.hasSuffix(rule.find) ? String(text.dropLast(rule.find.count)) + rule.replacement : text
            }
        }
    }
    public static func folder(_ value: String, profile: Profile) -> String {
        var s = applyReplacements(value, rules: profile.rules, target: .folder)
        if profile.rules.folderHyphensToSpaces {
            s = s.replacingOccurrences(of: #"\s*[-‐‑‒–—]+\s*"#, with: " ", options: .regularExpression)
            s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        return s
    }
    public static func existingFolder(_ value: String, profile: Profile) -> (name: String, rules: [String]) {
        var applied: [String] = []
        var text = applyReplacements(value, rules: profile.rules, target: .folder)
        if text != value { applied.append("Folder replacement rules") }
        let protected = ProtectedSpellings(text, exceptions: profile.exceptions)
        text = protected.text
        if profile.rules.folderHyphensToSpaces {
            let changed = text.replacingOccurrences(of: #"\s*[-‐‑‒–—]+\s*"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
            if changed != text { applied.append("Folder hyphens to spaces") }; text = changed
        }
        if profile.rules.folderTitleCase ?? true {
            let changed = titleCase(text, smallWords: profile.rules.smallWords)
            if changed != text { applied.append("Folder smart title case") }; text = changed
        }
        let restored = protected.restore(text)
        if restored != text && restored != value { applied.append("Universal preferred spelling and punctuation") }
        return (restored, applied)
    }
    public static func bucket(artist: String, profile: Profile) -> String {
        guard profile.bucket else { return "" }
        var text = artist.trimmingCharacters(in: .whitespaces)
        if profile.rules.ignoreLeadingThe, text.lowercased().hasPrefix("the ") { text = String(text.dropFirst(4)) }
        guard let first = text.first else { return "" }
        if first.isNumber { return profile.rules.numericBucket }
        let letter = String(first).folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")).uppercased()
        return letter.range(of: "^[A-Z]$", options: .regularExpression) != nil ? letter : profile.rules.symbolBucket
    }
}
public func proposedBasename(_ item: Item, profile: Profile) throws -> String {
    if let override = item.overrideBasename { try component(override); return override }
    return try Names.render(PatternEngine.filenameMask(for: item.fields, profile: profile), fields: item.fields, profile: profile, source: item.url, folder: false)
}
public func proposedFilename(_ item: Item, profile: Profile) throws -> String {
    let stem = try proposedBasename(item, profile: profile)
    return stem + (item.url.pathExtension.isEmpty ? "" : "." + item.url.pathExtension)
}
