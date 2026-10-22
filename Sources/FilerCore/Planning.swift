import Foundation
import Darwin

public enum Names {
    public static func clean(_ name: String, _ p: Profile, record: ((String) -> Void)? = nil) -> String {
        var s = name
        var previous = name
        var protected: ProtectedSpellings?
        func checkpoint(_ label: String) {
            let visible = protected?.restore(s) ?? s
            if !visible.utf8.elementsEqual(previous.utf8) { record?(label) }
            previous = visible
        }
        for token in p.removeTokens.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            s = s.replacingOccurrences(of: ProtectedSpellings.pattern(for: token), with: "", options: [.regularExpression, .caseInsensitive])
        }
        checkpoint("Removable labels")
        protected = ProtectedSpellings(s, exceptions: p.exceptions)
        s = protected!.text
        checkpoint("Universal preferred spelling protection")
        let handlesEpisodes = p.supportsEpisodes && (p.titleCase || p.rules.formatEpisodes || p.rules.episodeCase != .keep || p.rules.lowercaseEpisodeTitle)
        if handlesEpisodes { s = RuleEngine.normalizeEpisodeSpacing(s) }
        checkpoint("Episode spacing repair")
        if p.replaceUnderscores { s = s.replacingOccurrences(of: "_", with: " ") }
        checkpoint("Underscores to spaces")
        // Preserve numeric decimal separators and dotted initials; other configured separator dots become spaces.
        if p.rules.hyphensToSpaces { s = s.replacingOccurrences(of: #"[-‐‑‒–—]+"#, with: " ", options: .regularExpression) }
        checkpoint("Hyphens to spaces")
        if p.rules.dotsToDashes { s = s.replacingOccurrences(of: ".", with: " - ") }
        else if p.replaceDots {
            let chars = Array(s)
            s = chars.indices.map { i -> String in
                guard chars[i] == "." else { return String(chars[i]) }
                var left = i, right = i + 1
                while left > 0 && (chars[left - 1].isLetter || chars[left - 1].isNumber) { left -= 1 }
                while right < chars.count && (chars[right].isLetter || chars[right].isNumber) { right += 1 }
                let l = String(chars[left..<i]), r = String(chars[(i + 1)..<right])
                let decimal = !l.isEmpty && !r.isEmpty && l.allSatisfy(\.isNumber) && r.allSatisfy(\.isNumber)
                let initial = l.count == 1 && l.first?.isUppercase == true && r.first?.isUppercase == true
                let finalInitial = l.count == 1 && l.first?.isUppercase == true && i >= 2 && chars[i - 2] == "."
                return decimal || initial || finalInitial ? "." : " "
            }.joined()
        }
        checkpoint(p.rules.dotsToDashes ? "Periods to dashes" : "Separator dots to spaces")
        for rule in p.rules.replacements where rule.enabled && (rule.target == .filename || rule.target == .both) {
            var one = PreparationRules(); one.replacements = [rule]
            s = handlesEpisodes ? RuleEngine.protectEpisodes(s, { RuleEngine.applyReplacements($0, rules: one, target: .filename) }, capitalization: .keep) : RuleEngine.applyReplacements(s, rules: one, target: .filename)
            checkpoint("Find/replace: “" + rule.find + "”")
        }
        if p.normalizeSpaces ?? true {
            s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        checkpoint("Whitespace normalization")
        s = protected?.restore(s) ?? s
        protected = nil
        if p.titleCase {
            let title: (String) -> String = { p.rules.smartTitleCase ? RuleEngine.titleCase($0, smallWords: p.rules.smallWords) : $0.capitalized }
            s = p.supportsEpisodes ? RuleEngine.protectEpisodes(s, title, capitalization: .keep) : title(s)
        }
        checkpoint(p.rules.smartTitleCase ? "Smart title case" : "Title case")
        if p.supportsEpisodes {
            if p.rules.formatEpisodes, let episode = episodeComponents(s, profile: p) {
                let id = RuleEngine.formattedEpisodeID(source: name, season: episode.season, episode: episode.episode, policy: .keep)
                s = [episode.series, id, episode.title].filter { !$0.isEmpty }.joined(separator: " - ")
            }
            checkpoint("Episode separator formatting")
            if p.rules.lowercaseEpisodeTitle, RuleEngine.episode(s) != nil {
                s = RuleEngine.protectEpisodes(s, { $0.lowercased() }, capitalization: .keep)
            }
            checkpoint("Whole episode filename lowercase")
            s = RuleEngine.protectEpisodes(s, { $0 }, capitalization: p.rules.episodeCase)
        }
        checkpoint("Episode capitalization")
        s = protected?.restore(s) ?? s
        protected = nil
        for exception in p.exceptions.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            s = s.replacingOccurrences(of: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: exception) + "(?![\\p{L}\\p{N}])", with: NSRegularExpression.escapedTemplate(for: exception), options: [.regularExpression, .caseInsensitive])
        }
        checkpoint("Shared spelling exceptions")
        s = p.prefix + s + p.suffix
        checkpoint("Filename prefix/suffix")
        return s
    }
    public static func interpret(_ url: URL, _ p: Profile, record: ((String) -> Void)? = nil) -> (Fields, String, Bool) {
        if p.rules.useMagic, let suggestion = Magic.suggestions(url: url, profile: p).first {
            return (suggestion.fields, suggestion.evidence + "\n" + suggestion.confidence, false)
        }
        return basicInterpret(url, p, record: record)
    }
    public static func basicInterpret(_ url: URL, _ p: Profile, record: ((String) -> Void)? = nil) -> (Fields, String, Bool) {
        if p.workspacePatterns != nil { return PatternEngine.interpret(url, profile: p, record: record) }
        return legacyInterpret(url, p, record: record)
    }
    public static func legacyInterpret(_ url: URL, _ p: Profile, record: ((String) -> Void)? = nil) -> (Fields, String, Bool) {
        let original = url.deletingPathExtension().lastPathComponent
        let s = cleanField(original, p, record: record); var f = Fields(); f.title = s
        if p.kind == .video, let ep = episodeComponents(original, profile: p) {
            f.title = ""; f.series = cleanField(ep.series, p, record: record); f.season = ep.season; f.episode = ep.episode; f.episodeTitle = cleanField(ep.title, p, record: record)
            return (f, "Original filename contains a season/episode identifier. No online lookup.", false)
        }
        if !p.extractionMask.isEmpty {
            let token = try! NSRegularExpression(pattern: "\\{([A-Za-z]+)\\}")
            let ns = p.extractionMask as NSString; let matches = token.matches(in: p.extractionMask, range: NSRange(location: 0, length: ns.length))
            var pattern = "^", offset = 0, keys: [String] = []
            for m in matches { pattern += NSRegularExpression.escapedPattern(for: ns.substring(with: NSRange(location: offset, length: m.range.location - offset))); pattern += "(.+?)"; keys.append(ns.substring(with: m.range(at: 1))); offset = m.range.location + m.range.length }
            pattern += NSRegularExpression.escapedPattern(for: ns.substring(from: offset)) + "$"
            let protectedInput = ProtectedSpellings(original, exceptions: p.exceptions)
            let input = protectedInput.text
            if let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: input, range: NSRange(input.startIndex..., in: input)) {
                for (i, key) in keys.enumerated() { let value = cleanField(protectedInput.restore((input as NSString).substring(with: m.range(at: i + 1))), p, record: record); switch key { case "Title": f.title = value; case "Year": f.year = value; case "Artist": f.artist = value; case "Album": f.album = value; case "Author": f.author = value; case "BookTitle": f.bookTitle = value; case "ChapterNumber": f.chapterNumber = value; case "ChapterTitle": f.chapterTitle = value; case "Series": f.series = value; case "Season": f.season = value; case "Episode": f.episode = value; case "EpisodeTitle": f.episodeTitle = value; case "Date": f.date = value; case "Revision": f.revision = value; case "Narrator": f.narrator = value; case "Publisher": f.publisher = value; case "Illustrator": f.illustrator = value; case "IssueNumber": f.issueNumber = value; case "Volume": f.volume = value; case "SeriesNumber": f.seriesNumber = value; case "TrackNumber": f.trackNumber = value; case "RecordingType": f.recordingType = value; default: break } }
                if p.kind == .audiobook {
                    if p.extractionMask.contains("{Title}") && !p.extractionMask.contains("{BookTitle}") { f.bookTitle = f.title }
                    if !f.bookTitle.isEmpty { f.title = f.bookTitle }
                }
                return (f, "Matched extraction mask: \(p.extractionMask). Review the fields.", false)
            }
            return (f, "Extraction mask did not match.", false)
        }
        switch p.kind {
        case .video:
            let regex = try! NSRegularExpression(pattern: "(?:^|[ (])((?:19|20)[0-9]{2})(?:[ )]|$)")
            if let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                f.year = (s as NSString).substring(with: m.range(at: 1))
                f.title = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: " ").trimmingCharacters(in: .whitespaces)
            }
            return (f, "Filename title/year suggestion; confirm before including.", false)
        case .music, .audiobook:
            var parts = filenameSections(original, profile: p).map { cleanField($0, p, record: record) }
            if p.kind == .music && parts.count == 3 && Int(parts[0]) != nil { f.trackNumber = parts.removeFirst() }
            if parts.count == 2 { if p.kind == .music { f.artist = parts[0]; f.title = parts[1] } else if (p.effectiveBookSubtype == .audiobook || p.effectiveBookSubtype == .general) && Int(parts[0]) != nil { f.chapterNumber = parts[0]; f.chapterTitle = parts[1] } else { f.author = parts[0]; f.bookTitle = parts[1] } }
            if p.kind == .audiobook {
                if f.bookTitle.isEmpty && p.effectiveBookSubtype != .audiobook { f.bookTitle = s }
                if !f.bookTitle.isEmpty { f.title = f.bookTitle }
            }
            enrichYearAndRecording(&f, profile: p)
            return (f, "Filename split at ‘ - ’. Confirm artist/title or author/book; chapter numbers retained.", false)
        case .documents: return (f, "Filename cleanup only. No document contents read.", true)
        case .roms, .photos, .software, .other: return (f, "Custom profile: filename only; no media parsing. Cleaning follows your explicit profile rules.", true)
        }
    }
    public static func enrichYearAndRecording(_ fields: inout Fields, profile p: Profile) {
        guard p.kind == .music || p.kind == .audiobook else { return }
        let text = p.kind == .audiobook ? fields.bookTitle : fields.title
        // Only explicit parenthesized years and bracketed recording labels are interpreted.
        if let regex = try? NSRegularExpression(pattern: #"\s*\(((?:19|20)\d{2})\)"#), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            fields.year = (text as NSString).substring(with: match.range(at: 1))
            // Retain the marker in Title; masks can use Year independently.
        }
        if p.kind == .music, let regex = try? NSRegularExpression(pattern: #"(?i)\s*[\[(](Live|Studio)[\])]"#), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
            fields.recordingType = (text as NSString).substring(with: match.range(at: 1)).capitalized
            // Preserve an explicit marker in Title unless a user chooses to remove it.
        }
        if p.kind == .audiobook { fields.bookTitle = text; fields.title = text }
        else { fields.title = text }
    }
    public static func episodeComponents(_ name: String, profile: Profile) -> EpisodeMatch? {
        let protected = ProtectedSpellings(name, exceptions: profile.exceptions)
        guard let match = RuleEngine.episode(protected.text) else { return nil }
        return EpisodeMatch(series: protected.restore(match.series), season: match.season, episode: match.episode, title: protected.restore(match.title))
    }
    public static func filenameSections(_ original: String, profile: Profile) -> [String] {
        let protected = ProtectedSpellings(original, exceptions: profile.exceptions)
        let input = profile.replaceUnderscores ? protected.text.replacingOccurrences(of: "_", with: " ") : protected.text
        return input.components(separatedBy: " - ").map { protected.restore($0) }
    }
    public static func cleanField(_ value: String, _ p: Profile, record: ((String) -> Void)? = nil) -> String {
        var fieldProfile = p; fieldProfile.prefix = ""; fieldProfile.suffix = ""
        return clean(value, fieldProfile, record: record)
    }
    public static func render(_ mask: String, fields f: Fields, profile p: Profile, source: URL, folder: Bool) throws -> String {
        let isEpisode = p.kind == .video && !f.season.isEmpty && !f.episode.isEmpty
        var title = p.kind == .audiobook && !f.bookTitle.isEmpty ? f.bookTitle : f.title
        if isEpisode {
            guard let season = Int(f.season), let episode = Int(f.episode), (0...999).contains(season), (0...999).contains(episode) else { throw fail("Season and episode must be numbers from 0 to 999.") }
            let identifier = RuleEngine.formattedEpisodeID(source: source.deletingPathExtension().lastPathComponent, season: f.season, episode: f.episode, policy: p.rules.episodeCase)
            title = [f.series, identifier, f.episodeTitle].filter { !$0.isEmpty }.joined(separator: " - ")
        }
        let titleYear = title + (f.year.isEmpty || title.contains("(" + f.year + ")") ? "" : " (\(f.year))")
        var values = ["Title": title, "Year": f.year, "Artist": f.artist, "Album": f.album, "Author": f.author, "BookTitle": f.bookTitle, "ChapterNumber": f.chapterNumber, "ChapterTitle": f.chapterTitle, "TitleYear": title.isEmpty ? "" : titleYear, "AlbumOrIndividual": f.album.isEmpty ? p.individualTracks : f.album, "Bucket": RuleEngine.bucket(artist: f.artist, profile: p), "ChapterOrBook": f.chapterNumber.isEmpty ? f.bookTitle : clean(source.deletingPathExtension().lastPathComponent, p)]
        values.merge(["Series": f.series, "Season": f.season, "Episode": f.episode, "EpisodeTitle": f.episodeTitle, "Date": f.date, "Revision": f.revision, "EpisodeID": ""]) { _, new in new }
        values.merge(FieldCatalog.values(f)) { old, _ in old }
        values["Resolution"] = FieldCatalog.normalizedResolution(f.resolution)
        values["BookFolder"] = (f.seriesNumber.isEmpty ? "" : f.seriesNumber + " - ") + (f.bookTitle.isEmpty ? f.title : f.bookTitle)
        values.merge(["Narrator": f.narrator, "Publisher": f.publisher, "Illustrator": f.illustrator, "IssueNumber": f.issueNumber, "Volume": f.volume, "SeriesNumber": f.seriesNumber, "TrackNumber": f.trackNumber, "RecordingType": f.recordingType, "Live": f.recordingType.caseInsensitiveCompare("Live") == .orderedSame ? "(Live)" : ""]) { _, new in new }
        if let number = Int(f.trackNumber), number >= 0 { values["TrackNumber:02"] = String(format: "%02d", number) }
        if let season = Int(f.season), let episode = Int(f.episode), (0...999).contains(season), (0...999).contains(episode) {
            values["EpisodeID"] = RuleEngine.formattedEpisodeID(source: source.deletingPathExtension().lastPathComponent, season: String(season), episode: String(episode), policy: p.supportsEpisodes ? p.rules.episodeCase : .keep)
        }
        if let n = Int(f.season), (0...999).contains(n) { values["Season:02"] = String(format: "%02d", n) }
        if let n = Int(f.episode), (0...999).contains(n) { values["Episode:02"] = String(format: "%02d", n) }
        if let n = Int(f.chapterNumber) { values["ChapterNumber:02"] = String(format: "%02d", n) }
        var effectiveMask = mask
        if folder {
            effectiveMask = try mask.components(separatedBy: "/").filter { segment in
                let optional = try NSRegularExpression(pattern: #"\{([^{}]+)\?\}"#)
                return !optional.matches(in: segment, range: NSRange(segment.startIndex..., in: segment)).contains { match in
                    let key = (segment as NSString).substring(with: match.range(at: 1))
                    return values[key]?.isEmpty == true
                }
            }.joined(separator: "/")
        }
        // Optional resolution includes its brackets only when a value is present.
        if f.resolution.isEmpty {
            effectiveMask = effectiveMask.replacingOccurrences(of: " [{Resolution?}]", with: "")
                .replacingOccurrences(of: "[{Resolution?}]", with: "")
        }
        let re = try NSRegularExpression(pattern: "\\{([^}]+)\\}")
        var out = effectiveMask
        for m in re.matches(in: effectiveMask, range: NSRange(effectiveMask.startIndex..., in: effectiveMask)).reversed() {
            let key = (effectiveMask as NSString).substring(with: m.range(at: 1))
            let actualKey = key.hasSuffix("?") ? String(key.dropLast()) : key
            guard let v = values[actualKey] else { throw fail("Unsupported mask field: \(key)") }
            let optional = key.hasSuffix("?") || key == "Live" || (folder && ["Bucket", "AlbumOrIndividual"].contains(key))
            guard !v.isEmpty || optional else { throw fail("Missing required value: \(key)") }
            if !v.isEmpty { try component(v) }
            out = (out as NSString).replacingCharacters(in: m.range, with: v)
        }
        if folder { return try out.split(separator: "/", omittingEmptySubsequences: true).map { let s = RuleEngine.folder(String($0), profile: p); try component(s); return s }.joined(separator: "/") }
        if mask.contains("{Live}") && values["Live"] == "" {
            out = out.replacingOccurrences(of: #"[ \t]{2,}"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        let result = p.prefix + out + p.suffix
        try component(result); return result
    }
}
public struct ScanResult { public var items: [Item]; public var excluded: [String] }
public func scan(_ root: URL, profile: Profile, recursive: Bool, cancel: Cancellation? = nil) throws -> ScanResult {
    _ = try Directory(root.path)
    var items: [Item] = [], excluded: [String] = []
    let fm = FileManager.default
    guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .fileSizeKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { throw fail("Cannot enumerate workspace.") }
    for case let url as URL in e {
        if cancel?.cancelled == true { throw fail("Discovery cancelled; source files unchanged.") }
        do {
            let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .fileSizeKey])
            if v.isSymbolicLink == true || v.isAliasFile == true { e.skipDescendants(); excluded.append("Skipped link: " + url.lastPathComponent); continue }
            if v.isDirectory == true { if !recursive { e.skipDescendants() }; continue }
            guard profile.accepted.contains(url.pathExtension.lowercased()) else { excluded.append(url.lastPathComponent); continue }
            var triggered: [String] = []
            let (f, evidence, reviewed) = Names.basicInterpret(url, profile) { label in if !triggered.contains(label) { triggered.append(label) } }
            var item = Item(url: url, size: Int64(v.fileSize ?? 0), fields: f, evidence: evidence, reviewed: reviewed)
            item.rulesTriggered = triggered
            item.initialFields = f; item.initialBasename = try? proposedBasename(item, profile: profile)
            items.append(item)
        } catch { excluded.append("Unavailable: \(url.lastPathComponent): \(error.localizedDescription)") }
    }
    return ScanResult(items: items.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }, excluded: excluded)
}
public struct PlanRow: Codable, Identifiable {
    public var id = UUID()
    public var source: String
    public var destination: String
    public var fingerprint: Fingerprint?
    public var hash: String?
    public var sourceParentDevice: Int32 = 0
    public var sourceParentInode: UInt64 = 0
    public var existingDirectories: [String: DirectoryIdentity] = [:]
    public var newFolders: [String] = []
    public var status: String
    public var explanation: String
    public var group: String
    public var caseOnly: Bool?
    public var correction: ConfirmedCorrection?
    public var actionable: Bool { ["Will copy", "Will move", "Will rename"].contains(status) }
}
public struct DirectoryIdentity: Codable, Equatable { public var device: Int32; public var inode: UInt64; public init(device: Int32, inode: UInt64) { self.device = device; self.inode = inode } }
public struct Plan: Codable, Identifiable {
    public var id = UUID()
    public var created = Date()
    public var profile: Profile
    public var mode: Mode
    public var fileOnly: Bool
    public var category: String
    public var rootDevice: Int32
    public var rootInode: UInt64
    public var rows: [PlanRow]
}
public func categories(_ root: String) throws -> [String] {
    _ = try Directory(root)
    return try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey], options: [.skipsHiddenFiles]).filter { url in
        guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey]) else { return false }; return v.isDirectory == true && v.isSymbolicLink != true && v.isAliasFile != true
    }.map(\.lastPathComponent).sorted()
}
public func makePlan(items: [Item], profile p: Profile, mode: Mode, category: String, fileOnly: Bool) throws -> Plan {
    guard !items.isEmpty else { throw fail("Select at least one visible file.") }
    try p.rules.validate()
    guard !p.folderMask.hasPrefix("/") else { throw fail("Folder masks must be relative to the configured root.") }
    if mode != .clean { if category.isEmpty && !p.rootAllowed { throw fail("Choose and confirm a destination category.") }; if !category.isEmpty { try component(category) }; if !p.fixedCategory.isEmpty && category != p.fixedCategory { throw fail("Confirm the fixed category: \(p.fixedCategory)") } }
    let root = try Directory(mode == .clean ? items[0].url.deletingLastPathComponent().path : p.root)
    if mode != .clean, let identity = p.rootIdentity { guard root.device == identity.device, root.inode == identity.inode else { throw fail("Configured root identity changed. Reconnect in Settings; no automatic redirection.") } }
    var rows: [PlanRow] = []
    for item in items {
        var row = PlanRow(source: item.url.path, destination: "", status: "Needs review", explanation: item.evidence, group: item.fields.bookTitle)
        do {
            guard item.reviewed else { throw fail("Needs review: confirm the interpreted fields.") }
            let name = fileOnly ? item.url.lastPathComponent : try proposedFilename(item, profile: p)
            try component(name)
            var dest = mode == .clean ? item.url.deletingLastPathComponent() : URL(fileURLWithPath: p.root)
            if mode != .clean {
                if !category.isEmpty { dest.appendPathComponent(category) }
                try PatternEngine.validateClassification(item.fields, profile: p)
                let folder = try Names.render(PatternEngine.folderMask(for: item.fields, profile: p), fields: item.fields, profile: p, source: item.url, folder: true)
                for part in folder.split(separator: "/") { dest.appendPathComponent(String(part)) }
            }
            row.destination = dest.appendingPathComponent(name).path
            let sourceParent = try Directory(item.url.deletingLastPathComponent().path)
            row.sourceParentDevice = sourceParent.device; row.sourceParentInode = sourceParent.inode
            let fd = try sourceFD(item.url); defer { close(fd) }
            row.fingerprint = try Fingerprint(fd: fd); row.hash = try digest(fd: fd)
            guard row.fingerprint == (try Fingerprint(fd: fd)) else { throw fail("Source changed during preview.") }
            let base = mode == .clean ? sourceParent.path : p.root
            var cursor = URL(fileURLWithPath: base)
            let rel = dest.path == base ? "" : String(dest.path.dropFirst(base.count + 1))
            for part in rel.split(separator: "/") {
                cursor.appendPathComponent(String(part)); var s = stat()
                if lstat(cursor.path, &s) == 0 {
                    let d = try Directory(cursor.path); row.existingDirectories[cursor.path] = DirectoryIdentity(device: d.device, inode: d.inode)
                } else if errno == ENOENT { row.newFolders.append(cursor.path) } else { throw fail("Destination unavailable.") }
            }
            if row.source == row.destination { row.status = "No change needed" }
            else {
                let destinationParent = try? Directory(dest.path)
                let caseOnly = collisionKey(row.source) == collisionKey(row.destination) && destinationParent.map { sourceParent.matches($0) } == true
                if caseOnly && mode == .copy { throw fail("Destination conflict: a copy cannot replace its own source.") }
                row.caseOnly = caseOnly
                try checkCollision(dest, name: name, excluding: caseOnly ? item.url.lastPathComponent : nil)
                row.status = mode == .copy ? "Will copy" : mode == .move ? "Will move" : "Will rename"
            }
            if !fileOnly { row.correction = ConfirmedCorrection.make(item: item, profile: p, finalName: name) }
            if item.overrideBasename != nil { row.explanation += "\nManual filename override (extension preserved)." }
            row.explanation += "\nOriginal: \(item.url.lastPathComponent)\nProposed: \(name)\nRemoved tokens: \(p.removeTokens.isEmpty ? "none" : p.removeTokens)\nUnderscores: \(p.replaceUnderscores); separator dots: \(p.replaceDots); title case: \(p.titleCase). Magic analyzed: \(!item.alternatives.isEmpty); hyphens to spaces: \(p.rules.hyphensToSpaces); dots to dashes: \(p.rules.dotsToDashes); episode format: \(p.rules.formatEpisodes); episode capitalization: \(p.rules.episodeCase.rawValue); literal replacements: \(p.rules.replacements.filter(\.enabled).count)."
        } catch { let message = error.localizedDescription; row.status = message.hasPrefix("Missing") ? "Missing required value" : message.contains("conflict") ? "Destination conflict" : "Needs review"; row.explanation += "\n" + message }
        rows.append(row)
    }
    let duplicates = Dictionary(grouping: rows.filter { !$0.destination.isEmpty }, by: { collisionKey($0.destination) }).filter { $0.value.count > 1 }
    for i in rows.indices where duplicates[collisionKey(rows[i].destination)] != nil { rows[i].status = "Destination conflict"; rows[i].explanation += "\nDuplicate output in this batch." }
    return Plan(profile: p, mode: mode, fileOnly: fileOnly, category: category, rootDevice: root.device, rootInode: root.inode, rows: rows)
}
public func checkCollision(_ parent: URL, name: String, excluding: String? = nil) throws {
    var s = stat()
    if lstat(parent.path, &s) != 0 { if errno == ENOENT { return }; throw fail("Destination unavailable.") }
    _ = try Directory(parent.path)
    if try FileManager.default.contentsOfDirectory(atPath: parent.path).contains(where: { $0 != excluding && collisionKey($0) == collisionKey(name) }) { throw fail("Destination conflict: \(name)") }
}
