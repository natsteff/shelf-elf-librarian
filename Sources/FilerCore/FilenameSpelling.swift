import Foundation

public struct FilenameSpellingWord: Equatable {
    public let word: String
    public let range: NSRange
    public let characterIndices: Set<Int>
}
public enum FilenameSpelling {
    public static func replacing(_ word: String, in proposal: String, with replacement: String, profile: Profile) throws -> String {
        let entered = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !entered.isEmpty else { throw fail("Enter a replacement word.") }
        try component(entered)
        let preferred = Names.cleanField(entered, profile)
        let matches = candidates(in: proposal, exceptions: []).filter { $0.word.caseInsensitiveCompare(word) == .orderedSame }
        guard !matches.isEmpty else { throw fail("This word is no longer in the proposed filename. Edit the proposed name directly if needed.") }
        var result = proposal
        for match in matches.reversed() { result = (result as NSString).replacingCharacters(in: match.range, with: preferred) }
        try component(result)
        return result
    }
    /// Input is a basename, never an extension. Return only words worth checking.
    public static func candidates(in basename: String, exceptions: [String]) -> [FilenameSpellingWord] {
        let ns = basename as NSString
        var excluded: [NSRange] = RuleEngine.episodeTokens(basename).map(\.range)
        for entry in exceptions where !entry.isEmpty {
            let pattern = ProtectedSpellings.pattern(for: entry)
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                excluded += regex.matches(in: basename, range: NSRange(location: 0, length: ns.length)).map(\.range)
            }
        }
        guard let words = try? NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['’][\p{L}\p{N}]+)*"#) else { return [] }
        var offsets: [Int] = [], offset = 0
        for c in basename { offsets.append(offset); offset += String(c).utf16.count }
        return words.matches(in: basename, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let word = ns.substring(with: match.range)
            // Episode tags, years, track numbers and mixed numeric identifiers are not dictionary words.
            guard word.count > 1, !word.contains(where: { $0.isNumber }),
                  !excluded.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) else { return nil }
            let indices = Set(offsets.indices.filter { NSLocationInRange(offsets[$0], match.range) })
            return FilenameSpellingWord(word: word, range: match.range, characterIndices: indices)
        }
    }
}
