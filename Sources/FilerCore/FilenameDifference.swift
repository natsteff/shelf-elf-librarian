import Foundation

/// Character comparison for display only. Work is bounded for unusually long names.
public struct FilenameDifference: Equatable {
    public let source: String
    public let proposed: String
    public let removed: Set<Int>
    public let inserted: Set<Int>
    public var changed: Bool { !removed.isEmpty || !inserted.isEmpty }
    public var summary: String {
        guard changed else { return "No changes" }
        let a = Array(source), b = Array(proposed)
        let removedSpaces = removed.filter { a[$0].isWhitespace }.count
        let insertedSpaces = inserted.filter { b[$0].isWhitespace }.count
        if source.lowercased() == proposed.lowercased() { return "Capitalization changed" }
        var parts: [String] = []
        if removedSpaces > 0 { parts.append("Removed \(removedSpaces) whitespace character\(removedSpaces == 1 ? "" : "s")") }
        if insertedSpaces > 0 { parts.append("Added \(insertedSpaces) whitespace character\(insertedSpaces == 1 ? "" : "s")") }
        let old = removed.sorted().map { a[$0] }.filter { !$0.isWhitespace }
        let new = inserted.sorted().map { b[$0] }.filter { !$0.isWhitespace }
        if !old.isEmpty || !new.isEmpty {
            if String(old).lowercased() == String(new).lowercased() && !old.isEmpty { parts.append("Changed capitalization") }
            else { parts.append("Changed text or punctuation") }
        }
        return parts.joined(separator: " · ")
    }
    public init(source: String, proposed: String) {
        self.source = source; self.proposed = proposed
        let a = Array(source), b = Array(proposed)
        guard !source.utf8.elementsEqual(proposed.utf8) else { removed = []; inserted = []; return }
        var deleted = Set<Int>(), added = Set<Int>()
        if a.count <= 256 && b.count <= 256 {
            let width = b.count + 1
            var lengths = [Int](repeating: 0, count: (a.count + 1) * width)
            if !a.isEmpty && !b.isEmpty {
                for i in (0..<a.count).reversed() { for j in (0..<b.count).reversed() {
                    lengths[i * width + j] = a[i] == b[j] ? lengths[(i + 1) * width + j + 1] + 1 : max(lengths[(i + 1) * width + j], lengths[i * width + j + 1])
                } }
            }
            var i = 0, j = 0
            while i < a.count || j < b.count {
                if i < a.count && j < b.count && a[i] == b[j] { i += 1; j += 1 }
                else if i < a.count && (j == b.count || lengths[(i + 1) * width + j] >= lengths[i * width + j + 1]) { deleted.insert(i); i += 1 }
                else { added.insert(j); j += 1 }
            }
        } else {
            var start = 0
            while start < min(a.count, b.count) && a[start] == b[start] { start += 1 }
            var endA = a.count, endB = b.count
            while endA > start && endB > start && a[endA - 1] == b[endB - 1] { endA -= 1; endB -= 1 }
            deleted = Set(start..<endA); added = Set(start..<endB)
        }
        removed = deleted; inserted = added
    }
}

public struct FilenameDisplayPart: Equatable {
    public let text: String
    public let changed: Bool
}
extension FilenameDifference {
    /// Labels are used only in the expanded comparison; literal row/editor text stays intact.
    public func displayParts(sourceSide: Bool, markWhitespace: Bool) -> [FilenameDisplayPart] {
        let characters = Array(sourceSide ? source : proposed)
        let changed = sourceSide ? removed : inserted
        var parts: [FilenameDisplayPart] = [], index = 0
        while index < characters.count {
            let first = index, isChanged = changed.contains(index)
            if markWhitespace && isChanged && (characters[index] == " " || characters[index] == "\t") {
                let character = characters[index]
                while index < characters.count && characters[index] == character && changed.contains(index) { index += 1 }
                let count = index - first
                let kind = character == " " ? "SPACE" : "TAB"
                let label = count == 1 ? "[[\(kind)]]" : "[[\(kind)S × \(count)]]"
                parts.append(FilenameDisplayPart(text: label, changed: true))
            } else {
                index += 1
                while index < characters.count && changed.contains(index) == isChanged {
                    if markWhitespace && isChanged && (characters[index] == " " || characters[index] == "\t") { break }
                    index += 1
                }
                parts.append(FilenameDisplayPart(text: String(characters[first..<index]), changed: isChanged))
            }
        }
        return parts
    }
    public var literalWhitespaceLabels: [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[(?:SPACE|SPACES(?: × \d+)?|TAB|TABS(?: × \d+)?)\]\]"#) else { return [] }
        var labels: [String] = []
        for name in [source, proposed] {
            let ns = name as NSString
            for match in regex.matches(in: name, range: NSRange(location: 0, length: ns.length)) {
                let value = ns.substring(with: match.range)
                if !labels.contains(value) { labels.append(value) }
            }
        }
        return labels
    }
    /// Identify a capitalization-only edit at the hovered word, even when other words or spaces change.
    public func preferredCaseDescription(at index: Int, sourceSide: Bool) -> String? {
        let text = sourceSide ? source : proposed
        let counterpart = sourceSide ? proposed : source
        let chars = Array(text)
        guard index >= 0 && index < chars.count else { return nil }
        func wordCharacter(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "'" || c == "’" }
        guard wordCharacter(chars[index]) else { return nil }
        var start = index, end = index + 1
        while start > 0 && wordCharacter(chars[start - 1]) { start -= 1 }
        while end < chars.count && wordCharacter(chars[end]) { end += 1 }
        let word = String(chars[start..<end])
        func words(_ input: String) -> [String] { input.split(whereSeparator: { !wordCharacter($0) }).map(String.init) }
        let earlierOccurrences = words(String(chars[..<start])).filter { $0.lowercased() == word.lowercased() }.count
        let matches = words(counterpart).filter { $0.lowercased() == word.lowercased() }
        guard earlierOccurrences < matches.count else { return nil }
        let other = matches[earlierOccurrences]
        guard !word.utf8.elementsEqual(other.utf8) else { return nil }
        return sourceSide ? "Corrected preferred case: \(word) → \(other)" : "Corrected preferred case: \(other) → \(word)"
    }
}

extension FilenameDifference {
    public func episodeChangeDescription(at index: Int, sourceSide: Bool) -> String? {
        let name = sourceSide ? source : proposed
        let chars = Array(name)
        guard index >= 0 && index < chars.count else { return nil }
        let offset = String(chars[..<index]).utf16.count
        let tokens = RuleEngine.episodeTokens(name)
        guard let hovered = tokens.firstIndex(where: { NSLocationInRange(offset, $0.range) }) else { return nil }
        let token = tokens[hovered]
        let otherTokens = RuleEngine.episodeTokens(sourceSide ? proposed : source)
        guard hovered < otherTokens.count else { return nil }
        let other = otherTokens[hovered]
        guard Int(token.season) == Int(other.season), Int(token.episode) == Int(other.episode) else { return nil }
        let old = sourceSide ? token.raw : other.raw
        let new = sourceSide ? other.raw : token.raw
        let cleanOld = RuleEngine.normalizeEpisodeSpacing(old), cleanNew = RuleEngine.normalizeEpisodeSpacing(new)
        let oldLetters = old.filter { $0.isLetter }, newLetters = new.filter { $0.isLetter }
        var messages: [String] = []
        if oldLetters != newLetters { messages.append("Corrected preferred case for episode component: \(cleanOld) → \(cleanNew).") }
        if old != cleanOld || new != cleanNew { messages.append("Corrected spacing in episode component: \(old) → \(new).") }
        if token.season.count != other.season.count || token.episode.count != other.episode.count { messages.append("Normalized episode number padding: \(old) → \(new).") }
        return messages.isEmpty ? nil : messages.joined(separator: " ")
    }
}
