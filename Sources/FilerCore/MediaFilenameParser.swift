import Foundation

/// Music and Video parsing is an application capability, independent of editable profile patterns.
public enum MediaFilenameParser {
    public static func supports(_ profile: Profile) -> Bool { profile.kind == .music || profile.kind == .video }
    public static func interpret(_ url: URL, profile: Profile, record: ((String) -> Void)? = nil) -> (Fields, String, Bool) {
        if profile.kind == .music {
            let result = Names.legacyInterpret(url, profile, record: record)
            return (result.0, "Built-in Music parser. " + result.1, result.2)
        }
        var original = url.deletingPathExtension().lastPathComponent
        var readingURL = url, explicitResolution = ""
        let resolutionSuffix = try! NSRegularExpression(pattern: #"\s*\[(\d{3,4}[pPiI]|\d{1,6}[x×]\d{1,6}|[48][kK])\]$"#)
        if let match = resolutionSuffix.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)) {
            explicitResolution = FieldCatalog.normalizedResolution((original as NSString).substring(with: match.range(at: 1)))
            if explicitResolution.lowercased() == "4k" { explicitResolution = "4K" }
            if explicitResolution.lowercased() == "8k" { explicitResolution = "8K" }
            original = (original as NSString).replacingCharacters(in: match.range, with: "")
            readingURL = url.deletingLastPathComponent().appendingPathComponent(original + "." + url.pathExtension)
        }
        if RuleEngine.normalizeEpisodeSpacing(original) != original { record?("Episode spacing repair") }
        var reader = profile
        reader.workspacePatterns = PatternEngine.defaults(for: profile)
        // Recognizers remain available even if the profile has no user-defined filing Types.
        for standard in PatternEngine.defaultTypes(for: .video) where PatternEngine.lookup(standard.name, profile: reader) == nil {
            var definition = standard; definition.folderMask = nil; definition.filenameMask = nil
            reader.classifications = (reader.classifications ?? []) + [definition]
        }
        if MediaRouting.enabled(profile), let regex = try? NSRegularExpression(pattern: #"\[([^\[\]]+)\]$"#),
           let match = regex.firstMatch(in: original, range: NSRange(original.startIndex..., in: original)) {
            let label = (original as NSString).substring(with: match.range(at: 1))
            if (profile.mediaCategories ?? []).contains(where: { category in ([category.name] + UniversalPreferences.entries(category.aliases)).contains { $0.caseInsensitiveCompare(label) == .orderedSame } }) {
                reader.workspacePatterns = [WorkspacePattern("{Title} [{MediaCategory}]")] + (reader.workspacePatterns ?? [])
            }
        }
        var result = PatternEngine.interpret(readingURL, profile: reader, record: record)
        if !result.0.season.isEmpty, result.0.series.isEmpty, original.contains(".") || original.contains("_") {
            if let episode = Names.episodeComponents(original, profile: profile) {
                result.0.series = Names.cleanField(episode.series, profile)
                result.0.episodeTitle = Names.cleanField(episode.title, profile)
            }
        }
        if result.0.type == "Movie", result.0.year.isEmpty, original.contains(".") || original.contains("_") {
            let years = try! NSRegularExpression(pattern: #"(?<!\d)(?:(?:19|20)\d{2}|2100)(?!\d)"#)
            let matches = years.matches(in: original, range: NSRange(original.startIndex..., in: original))
            if matches.count == 1, let match = matches.first {
                result.0.year = (original as NSString).substring(with: match.range)
                let remainder = (original as NSString).replacingCharacters(in: match.range, with: " ")
                result.0.title = Names.cleanField(remainder, profile)
            }
        }
        if !explicitResolution.isEmpty { result.0.resolution = explicitResolution }
        return (result.0, "Built-in Video parser. " + result.1, result.2)
    }
}
