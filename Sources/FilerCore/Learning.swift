import Foundation
import CryptoKit

public struct ConfirmedCorrection: Codable, Identifiable {
    public var id = UUID()
    public let profileID: UUID
    public let original: String
    public let automatic: String
    public let final: String
    public let initialFields: Fields
    public let fields: Fields
    public let remember: Bool
    public let settingsSignature: String?
    public let sourceParentPath: String?
    public let folderMask: String?
    public let filenameMask: String?
    public static func make(item: Item, profile: Profile, finalName: String) -> ConfirmedCorrection? {
        let initial = item.initialFields ?? Names.basicInterpret(item.url, profile).0
        let automatic = item.initialBasename.map { $0 + (item.url.pathExtension.isEmpty ? "" : "." + item.url.pathExtension) } ?? item.url.lastPathComponent
        guard item.overrideBasename != nil || initial != item.fields else { return nil }
        return ConfirmedCorrection(profileID: profile.id, original: item.url.lastPathComponent, automatic: automatic, final: finalName, initialFields: initial, fields: item.fields, remember: item.rememberCorrection, settingsSignature: Learning.settingsSignature(profile), sourceParentPath: item.url.deletingLastPathComponent().path, folderMask: profile.folderMask, filenameMask: profile.filenameMask)
    }
    public init(profileID: UUID, original: String, automatic: String, final: String, initialFields: Fields, fields: Fields, remember: Bool, settingsSignature: String? = nil, sourceParentPath: String? = nil, folderMask: String? = nil, filenameMask: String? = nil) { self.folderMask = folderMask; self.filenameMask = filenameMask; self.settingsSignature = settingsSignature; self.sourceParentPath = sourceParentPath; self.profileID = profileID; self.original = original; self.automatic = automatic; self.final = final; self.initialFields = initialFields; self.fields = fields; self.remember = remember }
}
public enum RecommendationKind: String { case setting, development }
public struct ProfileRecommendation: Identifiable {
    public let id: String
    public let kind: RecommendationKind
    public let title: String
    public let explanation: String
    public let action: String
    public let find: String
    public let value: String
    public let examples: [ConfirmedCorrection]
    public func apply(to profile: inout Profile) {
        switch action {
        case "extension":
            if !profile.accepted.contains(value) { profile.extensions += (profile.extensions.isEmpty ? "" : ", ") + value }
        case "exception":
            let existing = profile.exceptions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            if !existing.contains(value) { profile.exceptions += (profile.exceptions.isEmpty ? "" : ", ") + value }
        case "prefix": profile.prefix = value + profile.prefix
        case "suffix": profile.suffix += value
        case "replacement", "removePrefix", "removeSuffix":
            var rules = profile.rules
            if !rules.replacements.contains(where: { $0.find == find && $0.replacement == value && $0.target == .filename }) { var rule = ReplacementRule(find: find, replacement: value)
                rule.position = action == "removePrefix" ? .prefix : action == "removeSuffix" ? .suffix : .anywhere
                rules.replacements.append(rule) }
            profile.rules = rules
        default: break
        }
    }
    public func report(profile: Profile, anonymize: Bool) -> String {
        func example(_ value: String) -> String {
            anonymize ? value.replacingOccurrences(of: #"[\p{L}\p{N}]+"#, with: "Word", options: .regularExpression) : value
        }
        var lines = ["Shelf Elf Librarian — Profile Development Recommendation", "Profile: \(anonymize ? "[profile name omitted]" : profile.name)", "Content type: \(profile.kind == .audiobook ? "Books & Comics / " + profile.effectiveBookSubtype.label : profile.kind.rawValue)", "\(title)", explanation, "Observed only from user-confirmed operations; no full-library scan.", "No source/destination paths are included."]
        for e in examples.prefix(5) {
            lines += ["Original: \(example(e.original))", "Automatic: \(example(e.automatic))", "User-approved: \(example(e.final))"]
            let fields: [(String, KeyPath<Fields, String>)] = [("Title", \.title), ("Artist", \.artist), ("Album", \.album), ("Author", \.author), ("BookTitle", \.bookTitle), ("ChapterNumber", \.chapterNumber), ("ChapterTitle", \.chapterTitle), ("Series", \.series), ("Season", \.season), ("Episode", \.episode), ("EpisodeTitle", \.episodeTitle), ("Date", \.date), ("Revision", \.revision), ("Narrator", \.narrator), ("Publisher", \.publisher), ("Illustrator", \.illustrator), ("IssueNumber", \.issueNumber), ("Volume", \.volume), ("SeriesNumber", \.seriesNumber), ("TrackNumber", \.trackNumber), ("RecordingType", \.recordingType)]
            for (label, path) in fields where e.initialFields[keyPath: path] != e.fields[keyPath: path] {
                lines.append("Field \(label): \(example(e.initialFields[keyPath: path])) → \(example(e.fields[keyPath: path]))")
            }
            if let mask = e.folderMask {
                let re = try? NSRegularExpression(pattern: #"\{[^}]+\}"#)
                let tokens = re?.matches(in: mask, range: NSRange(mask.startIndex..., in: mask)).map { (mask as NSString).substring(with: $0.range) }.joined(separator: "/") ?? ""
                lines.append("Folder mask: " + (anonymize ? tokens : mask))
            }
            lines.append("")
        }
        lines += ["Request: consider a profile capability that expresses these corrections. Preserve original evidence, show uncertainty and keep explicit preview/apply."]
        return lines.joined(separator: "\n")
    }
}
public enum Learning {
    public static func settingsSignature(_ profile: Profile) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var interpretationProfile = profile; interpretationProfile.notes = nil
        guard let data = try? encoder.encode(interpretationProfile) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    public static func observations(events: [Event], forgotten: Set<String> = []) -> [ConfirmedCorrection] {
        var seen: Set<UUID> = []
        let undone = Set(events.filter { $0.state == "Undone" }.map { $0.operation.uuidString + $0.row.id.uuidString })
        return events.compactMap { event in
            guard !undone.contains(event.operation.uuidString + event.row.id.uuidString), ["Copied", "Moved"].contains(event.state), let c = event.row.correction, !forgotten.contains(c.id.uuidString), seen.insert(c.id).inserted else { return nil }
            return c
        }
    }
    public static func recommendations(profile p: Profile, observations: [ConfirmedCorrection], excluded: [String]) -> [ProfileRecommendation] {
        var groups: [String: (String, String, [ConfirmedCorrection])] = [:]
        for example in observations where example.profileID == p.id && (example.automatic != example.final || example.initialFields != example.fields) {
            let before = URL(fileURLWithPath: example.automatic).deletingPathExtension().lastPathComponent
            let after = URL(fileURLWithPath: example.final).deletingPathExtension().lastPathComponent
            // A minimal contiguous change is expressible as a literal replacement. It is only a suggestion.
            let a = Array(before), b = Array(after)
            var start = 0
            while start < min(a.count, b.count), a[start] == b[start] { start += 1 }
            var suffix = 0
            while suffix < min(a.count - start, b.count - start), a[a.count - 1 - suffix] == b[b.count - 1 - suffix] { suffix += 1 }
            let find = String(a[start..<(a.count - suffix)]), value = String(b[start..<(b.count - suffix)])
            if find.isEmpty, !value.isEmpty, value.count <= 60, (start == 0 || suffix == 0), !(start == 0 ? p.prefix.hasPrefix(value) : p.suffix.hasSuffix(value)) {
                let key = (start == 0 ? "prefix:" : "suffix:") + value
                var g = groups[key] ?? ("", value, [])
                if !g.2.contains(where: { $0.original == example.original }) { g.2.append(example) }; groups[key] = g
            }
            if !find.isEmpty, find.count <= 60, value.count <= 60, !value.contains("/"), !value.contains(":"), !p.rules.replacements.contains(where: { $0.enabled && $0.find == find && $0.replacement == value }) {
                let type = value.isEmpty && start == 0 ? "removePrefix:" : value.isEmpty && suffix == 0 ? "removeSuffix:" : "replace:"
                let key = type + find + "→" + value
                var g = groups[key] ?? (find, value, [])
                if !g.2.contains(where: { $0.original == example.original && $0.final == example.final }) { g.2.append(example) }
                groups[key] = g
            }
            for keyPath in [\Fields.artist, \Fields.author, \Fields.bookTitle] {
                let from = example.initialFields[keyPath: keyPath], to = example.fields[keyPath: keyPath]
                if !to.isEmpty, from != to, from.caseInsensitiveCompare(to) == .orderedSame, !p.exceptions.split(separator: ",").contains(where: { $0.trimmingCharacters(in: .whitespaces) == to }) {
                    let key = "exception:" + to
                    var g = groups[key] ?? ("", to, [])
                    if !g.2.contains(where: { $0.original == example.original }) { g.2.append(example) }; groups[key] = g
                }
            }
        }
        func stableID(_ key: String) -> String { p.id.uuidString + ":" + SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() }
        var result: [ProfileRecommendation] = []
        for (key, group) in groups.sorted(by: { $0.key < $1.key }) where group.2.count >= 2 {
            let isException = key.hasPrefix("exception:")
            let action = isException ? "exception" : key.hasPrefix("prefix:") ? "prefix" : key.hasPrefix("suffix:") ? "suffix" : key.hasPrefix("removePrefix:") ? "removePrefix" : key.hasPrefix("removeSuffix:") ? "removeSuffix" : "replacement"
            let title = isException ? "Spelling exception: \(group.1)" : action == "prefix" ? "Add prefix: \(group.1)" : action == "suffix" ? "Add suffix: \(group.1)" : action == "removePrefix" ? "Remove prefix: \(group.0)" : action == "removeSuffix" ? "Remove suffix: \(group.0)" : "Replace ‘\(group.0)’ with ‘\(group.1)’"
            result.append(ProfileRecommendation(id: stableID(key), kind: .setting,
                title: title,
                explanation: "\(group.2.count) distinct user-confirmed corrections suggest this setting. This may be an exception: review examples before adding it to the draft.",
                action: action, find: group.0, value: group.1, examples: group.2))
        }
        let extensions = Dictionary(grouping: excluded.filter { !$0.contains(":") }.filter { !URL(fileURLWithPath: $0).pathExtension.isEmpty }, by: { URL(fileURLWithPath: $0).pathExtension.lowercased() })
        for (ext, names) in extensions.sorted(by: { $0.key < $1.key }) where !p.accepted.contains(ext) && names.count >= 1 {
            result.append(ProfileRecommendation(id: stableID("extension:" + ext), kind: .setting, title: "Consider accepting .\(ext)", explanation: "\(Set(names).count) excluded workspace files use .\(ext). This is weak evidence only; they may intentionally be excluded. Nothing is included until you add the extension and save the profile.", action: "extension", find: "", value: ext, examples: []))
        }
        let edited = observations.filter { $0.profileID == p.id && ($0.automatic != $0.final || $0.initialFields != $0.fields) }
        let distinct = Dictionary(grouping: edited, by: { $0.original }).compactMap { $0.value.first }
        if distinct.count >= 2 {
            result.append(ProfileRecommendation(id: stableID("development"), kind: .development, title: "Review recurring filename/structure corrections", explanation: "There are \(distinct.count) distinct manual corrections in this profile. Some may be expressible with settings above; others may need better parsing, masks, or a new capability. This is a development discussion prompt, not a claim that the app has proven a missing feature.", action: "development", find: "", value: "", examples: distinct))
        }
        return result
    }
}
