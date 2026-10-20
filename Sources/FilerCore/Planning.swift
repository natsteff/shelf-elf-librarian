import Foundation
import Darwin

public enum Names {
    public static func clean(_ name: String, _ p: Profile) -> String {
        var s = name
        if p.replaceUnderscores { s = s.replacingOccurrences(of: "_", with: " ") }
        // Preserve numeric decimal separators and dotted initials; other configured separator dots become spaces.
        if p.replaceDots {
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
        for token in p.removeTokens.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            s = s.replacingOccurrences(of: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: token) + "(?![\\p{L}\\p{N}])", with: "", options: [.regularExpression, .caseInsensitive])
        }
        if p.normalizeSpaces ?? true {
            s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        }
        if p.titleCase { s = s.capitalized }
        for exception in p.exceptions.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces) }).filter({ !$0.isEmpty }) {
            s = s.replacingOccurrences(of: "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: exception) + "(?![\\p{L}\\p{N}])", with: NSRegularExpression.escapedTemplate(for: exception), options: [.regularExpression, .caseInsensitive])
        }
        return p.prefix + s + p.suffix
    }
    public static func interpret(_ url: URL, _ p: Profile) -> (Fields, String, Bool) {
        let original = url.deletingPathExtension().lastPathComponent
        let s = clean(original, p); var f = Fields(); f.title = s
        if !p.extractionMask.isEmpty {
            let token = try! NSRegularExpression(pattern: "\\{([A-Za-z]+)\\}")
            let ns = p.extractionMask as NSString; let matches = token.matches(in: p.extractionMask, range: NSRange(location: 0, length: ns.length))
            var pattern = "^", offset = 0, keys: [String] = []
            for m in matches { pattern += NSRegularExpression.escapedPattern(for: ns.substring(with: NSRange(location: offset, length: m.range.location - offset))); pattern += "(.+?)"; keys.append(ns.substring(with: m.range(at: 1))); offset = m.range.location + m.range.length }
            pattern += NSRegularExpression.escapedPattern(for: ns.substring(from: offset)) + "$"
            if let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) {
                for (i, key) in keys.enumerated() { let value = (s as NSString).substring(with: m.range(at: i + 1)); switch key { case "Title": f.title = value; case "Year": f.year = value; case "Artist": f.artist = value; case "Album": f.album = value; case "Author": f.author = value; case "BookTitle": f.bookTitle = value; case "ChapterNumber": f.chapterNumber = value; case "ChapterTitle": f.chapterTitle = value; default: break } }
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
            let parts = s.components(separatedBy: " - ")
            if parts.count == 2 { if p.kind == .music { f.artist = parts[0]; f.title = parts[1] } else if Int(parts[0]) != nil { f.chapterNumber = parts[0]; f.chapterTitle = parts[1] } else { f.author = parts[0]; f.bookTitle = parts[1] } }
            return (f, "Filename split at ‘ - ’. Confirm artist/title or author/book; chapter numbers retained.", false)
        case .documents: return (f, "Filename cleanup only. No document contents read.", true)
        case .other: return (f, "Custom profile: filename only; no media parsing. Cleaning follows your explicit profile rules.", true)
        }
    }
    public static func render(_ mask: String, fields f: Fields, profile p: Profile, source: URL, folder: Bool) throws -> String {
        let titleYear = f.title + (f.year.isEmpty ? "" : " (\(f.year))")
        var values = ["Title": f.title, "Year": f.year, "Artist": f.artist, "Album": f.album, "Author": f.author, "BookTitle": f.bookTitle, "ChapterNumber": f.chapterNumber, "ChapterTitle": f.chapterTitle, "TitleYear": titleYear, "AlbumOrIndividual": f.album.isEmpty ? p.individualTracks : f.album, "Bucket": p.bucket ? String(f.artist.prefix(1)).uppercased() : "", "ChapterOrBook": f.chapterNumber.isEmpty ? f.bookTitle : source.deletingPathExtension().lastPathComponent]
        if let n = Int(f.chapterNumber) { values["ChapterNumber:02"] = String(format: "%02d", n) }
        let re = try NSRegularExpression(pattern: "\\{([^}]+)\\}")
        var out = mask
        for m in re.matches(in: mask, range: NSRange(mask.startIndex..., in: mask)).reversed() {
            let key = (mask as NSString).substring(with: m.range(at: 1))
            guard let v = values[key] else { throw fail("Unsupported mask field: \(key)") }
            let optional = folder && ["Bucket", "AlbumOrIndividual"].contains(key)
            guard !v.isEmpty || optional else { throw fail("Missing required value: \(key)") }
            if !v.isEmpty { try component(v) }
            out = (out as NSString).replacingCharacters(in: m.range, with: v)
        }
        if folder { return try out.split(separator: "/", omittingEmptySubsequences: true).map { let s = String($0); try component(s); return s }.joined(separator: "/") }
        try component(out); return out
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
            let (f, evidence, reviewed) = Names.interpret(url, profile)
            items.append(Item(url: url, size: Int64(v.fileSize ?? 0), fields: f, evidence: evidence, reviewed: reviewed))
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
    if mode != .clean { if category.isEmpty && !p.rootAllowed { throw fail("Choose and confirm a destination category.") }; if !category.isEmpty { try component(category) }; if !p.fixedCategory.isEmpty && category != p.fixedCategory { throw fail("Confirm the fixed category: \(p.fixedCategory)") } }
    let root = try Directory(mode == .clean ? items[0].url.deletingLastPathComponent().path : p.root)
    if mode != .clean, let identity = p.rootIdentity { guard root.device == identity.device, root.inode == identity.inode else { throw fail("Configured root identity changed. Reconnect in Settings; no automatic redirection.") } }
    var rows: [PlanRow] = []
    for item in items {
        var row = PlanRow(source: item.url.path, destination: "", status: "Needs review", explanation: item.evidence, group: item.fields.bookTitle)
        do {
            guard item.reviewed else { throw fail("Needs review: confirm the interpreted fields.") }
            let ext = item.url.pathExtension
            let name = fileOnly ? item.url.lastPathComponent : try Names.render(p.filenameMask, fields: item.fields, profile: p, source: item.url, folder: false) + (ext.isEmpty ? "" : "." + ext)
            try component(name)
            var dest = mode == .clean ? item.url.deletingLastPathComponent() : URL(fileURLWithPath: p.root)
            if mode != .clean {
                if !category.isEmpty { dest.appendPathComponent(category) }
                let folder = try Names.render(p.folderMask, fields: item.fields, profile: p, source: item.url, folder: true)
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
                if collisionKey(row.source) == collisionKey(row.destination) { throw fail("Case-only/Unicode-only renames require a separate intermediate name in this alpha.") }
                try checkCollision(dest, name: name)
                row.status = mode == .copy ? "Will copy" : mode == .move ? "Will move" : "Will rename"
            }
            row.explanation += "\nOriginal: \(item.url.lastPathComponent)\nProposed: \(name)\nRemoved tokens: \(p.removeTokens.isEmpty ? "none" : p.removeTokens)\nUnderscores: \(p.replaceUnderscores); separator dots: \(p.replaceDots); title case: \(p.titleCase)."
        } catch { let message = error.localizedDescription; row.status = message.hasPrefix("Missing") ? "Missing required value" : message.contains("conflict") ? "Destination conflict" : "Needs review"; row.explanation += "\n" + message }
        rows.append(row)
    }
    let duplicates = Dictionary(grouping: rows.filter { !$0.destination.isEmpty }, by: { collisionKey($0.destination) }).filter { $0.value.count > 1 }
    for i in rows.indices where duplicates[collisionKey(rows[i].destination)] != nil { rows[i].status = "Destination conflict"; rows[i].explanation += "\nDuplicate output in this batch." }
    return Plan(profile: p, mode: mode, fileOnly: fileOnly, category: category, rootDevice: root.device, rootInode: root.inode, rows: rows)
}
public func checkCollision(_ parent: URL, name: String) throws {
    var s = stat()
    if lstat(parent.path, &s) != 0 { if errno == ENOENT { return }; throw fail("Destination unavailable.") }
    _ = try Directory(parent.path)
    if try FileManager.default.contentsOfDirectory(atPath: parent.path).contains(where: { collisionKey($0) == collisionKey(name) }) { throw fail("Destination conflict: \(name)") }
}
