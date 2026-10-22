import AppKit
import FilerCore

/// Checks are advisory; suggestions are requested only by user action. System learned/ignored lists stay unchanged.
@MainActor final class FilenameSpellChecker {
    static let shared = FilenameSpellChecker()
    private var cache: [String: Bool] = [:]
    private var pending: [String: Task<Bool, Never>] = [:]
    func suggestions(for word: String) -> [String] {
        let checker = NSSpellChecker.shared
        var seen = Set<String>()
        let languages: [String?] = checker.userPreferredLanguages.isEmpty ? [nil] : checker.userPreferredLanguages.map { Optional($0) }
        return languages.flatMap { language in
            checker.guesses(forWordRange: NSRange(location: 0, length: (word as NSString).length), in: word, language: language, inSpellDocumentWithTag: 0) ?? []
        }.filter { $0.caseInsensitiveCompare(word) != .orderedSame && seen.insert($0.lowercased()).inserted }.prefix(8).map { $0 }
    }
    func unrecognized(in basename: String, exceptions: [String]) async -> [FilenameSpellingWord] {
        let checker = NSSpellChecker.shared
        let languages = checker.userPreferredLanguages.joined(separator: ",")
        var result: [FilenameSpellingWord] = []
        for candidate in FilenameSpelling.candidates(in: basename, exceptions: exceptions) {
            guard !Task.isCancelled else { return [] }
            let word = candidate.word.lowercased()
            let key = languages + ":" + word
            let unknown: Bool
            if let saved = cache[key] { unknown = saved }
            else {
                let job: Task<Bool, Never>
                if let existing = pending[key] { job = existing }
                else {
                    job = Task { @MainActor in
                        let tag = NSSpellChecker.uniqueSpellDocumentTag()
                        let unknown = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                            checker.requestChecking(of: word, range: NSRange(location: 0, length: (word as NSString).length), types: NSTextCheckingResult.CheckingType.spelling.rawValue, options: nil, inSpellDocumentWithTag: tag) { _, results, _, _ in
                                continuation.resume(returning: results.contains { $0.resultType == .spelling })
                            }
                        }
                        checker.closeSpellDocument(withTag: tag)
                        return unknown
                    }
                    pending[key] = job
                }
                unknown = await job.value
                if cache.count >= 10_000 { cache.removeAll(keepingCapacity: true) }
                cache[key] = unknown; pending.removeValue(forKey: key)
            }
            if unknown { result.append(candidate) }
        }
        return result
    }
}
