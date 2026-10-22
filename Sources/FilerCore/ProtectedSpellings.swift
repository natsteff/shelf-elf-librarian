import Foundation

/// Temporarily shields preferred entries from cleanup and delimiter parsing. Longest matches win.
struct ProtectedSpellings {
    private(set) var text: String
    private var saved: [(String, String)] = []
    init(_ value: String, exceptions: String) {
        text = value
        for (entry, regex) in PreferredPatternCache.shared.patterns(exceptions) {
            let ns = text as NSString
            for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
                // Private-use characters keep placeholders stable under whitespace and case transforms.
                let marker = "\u{E000}" + UUID().uuidString.unicodeScalars.map { String(UnicodeScalar(0xE100 + $0.value)!) }.joined() + "\u{E001}"
                saved.append((marker, entry))
                text = (text as NSString).replacingCharacters(in: match.range, with: marker)
            }
        }
    }
    static func pattern(for entry: String) -> String {
        let pieces = entry.components(separatedBy: "-").map(NSRegularExpression.escapedPattern(for:))
        return "(?<![\\p{L}\\p{N}])" + pieces.joined(separator: "[ \\t]*-[ \\t]*") + "(?![\\p{L}\\p{N}])"
    }
    func restore(_ value: String) -> String {
        saved.reduce(value) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
    }
}

private final class PreferredPatternCache {
    static let shared = PreferredPatternCache()
    private let lock = NSLock()
    private var cache: [String: [(String, NSRegularExpression)]] = [:]
    func patterns(_ exceptions: String) -> [(String, NSRegularExpression)] {
        lock.lock(); defer { lock.unlock() }
        if let found = cache[exceptions] { return found }
        let result: [(String, NSRegularExpression)] = UniversalPreferences.entries(exceptions).sorted { $0.count > $1.count }.compactMap { entry in
            guard let regex = try? NSRegularExpression(pattern: ProtectedSpellings.pattern(for: entry), options: [.caseInsensitive]) else { return nil }
            return (entry, regex)
        }
        if cache.count >= 64 { cache.removeAll() }
        cache[exceptions] = result
        return result
    }
}
