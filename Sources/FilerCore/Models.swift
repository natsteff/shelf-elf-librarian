import Foundation
import CryptoKit
import Darwin

public enum FilerError: Error, LocalizedError {
    case message(String)
    public var errorDescription: String? { if case .message(let s) = self { return s }; return nil }
}
public func fail(_ s: String) -> FilerError { .message(s) }
public enum Kind: String, Codable, CaseIterable, Identifiable { case video, music, audiobook, documents, other; public var id: String { rawValue } }
public enum Mode: String, Codable, CaseIterable, Identifiable { case copy, move, clean; public var id: String { rawValue } }
public struct Profile: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var schemaVersion = 1
    public var name: String
    public var kind: Kind
    public var root = ""
    public var bookmark: Data?
    public var rootIdentity: DirectoryIdentity?
    public var extensions: String
    public var normalizeSpaces: Bool? = true
    public var replaceUnderscores = true
    public var replaceDots = true
    public var titleCase = true
    public var removeTokens = ""
    public var exceptions = "DJ, VNV Nation"
    public var prefix = ""
    public var suffix = ""
    public var extractionMask = ""
    public var folderMask: String
    public var filenameMask: String
    public var individualTracks = ""
    public var bucket = true
    public var rootAllowed = false
    public var fixedCategory = ""
    public init(_ kind: Kind) {
        self.kind = kind
        switch kind {
        case .video: name = "Movies — Demo"; extensions = "mkv, mp4, m4v, avi, mov"; folderMask = "{TitleYear}"; filenameMask = "{TitleYear}"; removeTokens = "1080p, WEB-DL"
        case .music: name = "Music — Demo"; extensions = "mp3, flac, m4a, aac, wav, aiff"; folderMask = "{Bucket}/{Artist}/{AlbumOrIndividual}"; filenameMask = "{Artist} - {Title}"
        case .audiobook: name = "Audiobooks — Demo"; extensions = "m4b, mp3"; folderMask = "{Author}/{BookTitle}"; filenameMask = "{ChapterOrBook}"
        case .documents: name = "Documents — Demo"; extensions = "pdf"; folderMask = ""; filenameMask = "{Title}"; replaceDots = false
        case .other:
            name = "Other / Custom"; extensions = ""; folderMask = ""; filenameMask = "{Title}"
            replaceUnderscores = false; replaceDots = false; titleCase = false; normalizeSpaces = false
            exceptions = ""; bucket = false
        }
    }
    public var accepted: Set<String> { Set(extensions.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) }.filter { !$0.isEmpty }) }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !accepted.isEmpty else { throw fail("Profile needs a name and file extensions.") }
        if !fixedCategory.isEmpty { try component(fixedCategory) }
        if !individualTracks.isEmpty { try component(individualTracks) }
        if !root.isEmpty { _ = try Directory(root) }
    }
}
public struct Fields: Codable, Equatable {
    public var title = "", year = "", artist = "", album = "", author = "", bookTitle = "", chapterNumber = "", chapterTitle = ""
    public init() {}
}
public struct Item: Identifiable {
    public var id: String { url.path }
    public var url: URL
    public var size: Int64
    public var fields: Fields
    public var evidence: String
    public var reviewed: Bool
    public init(url: URL, size: Int64, fields: Fields, evidence: String, reviewed: Bool) { self.url = url; self.size = size; self.fields = fields; self.evidence = evidence; self.reviewed = reviewed }
}
public func component(_ value: String) throws {
    guard !value.isEmpty, value != ".", value != "..", !value.contains("/"), !value.contains(":"), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }), value.utf8.count <= 240 else { throw fail("Invalid or excessive path component: \(value)") }
}
public func collisionKey(_ s: String) -> String { s.precomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
public struct Fingerprint: Codable, Equatable {
    public var device: Int32
    public var inode: UInt64
    public var size: Int64
    public var seconds: Int64
    public var nanos: Int64
    public var changedSeconds: Int64
    public var changedNanos: Int64
    public init(fd: Int32) throws {
        var s = stat(); guard fstat(fd, &s) == 0, (s.st_mode & S_IFMT) == S_IFREG else { throw fail("Source is not an available regular file.") }
        device = s.st_dev; inode = s.st_ino; size = s.st_size; seconds = Int64(s.st_mtimespec.tv_sec); nanos = Int64(s.st_mtimespec.tv_nsec); changedSeconds = Int64(s.st_ctimespec.tv_sec); changedNanos = Int64(s.st_ctimespec.tv_nsec)
    }
}
// Holds the entire directory chain open. Symlinks and Finder aliases are refused.
public final class Directory {
    public let fd: Int32
    public let path: String
    public let device: Int32
    public let inode: UInt64
    public init(_ path: String) throws {
        guard path.hasPrefix("/"), !path.contains("//"), !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { throw fail("Use a normalized absolute directory path.") }
        var current = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard current >= 0 else { throw fail("Cannot open filesystem root.") }
        do {
            for part in path.split(separator: "/") {
                try component(String(part))
                let next = openat(current, String(part), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
                guard next >= 0 else { throw fail("Unavailable or linked directory: \(path) (\(String(cString: strerror(errno))))") }
                close(current); current = next
            }
            let v = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isAliasFileKey])
            guard v.isAliasFile != true else { throw fail("Finder aliases are unsupported.") }
            var s = stat(); guard fstat(current, &s) == 0 else { throw fail("Cannot identify directory.") }
            self.fd = current; self.path = path; device = s.st_dev; inode = s.st_ino
        } catch { close(current); throw error }
    }
    deinit { close(fd) }
    public func matches(_ other: Directory) -> Bool { device == other.device && inode == other.inode }
}
public func digest(fd: Int32) throws -> String {
    guard lseek(fd, 0, SEEK_SET) >= 0 else { throw fail("Cannot seek file.") }
    var hash = SHA256(); var data = [UInt8](repeating: 0, count: 1024 * 1024)
    while true { let n = read(fd, &data, data.count); if n == 0 { break }; guard n > 0 else { throw fail("Cannot read file for verification.") }; hash.update(data: Data(data[0..<n])) }
    return hash.finalize().map { String(format: "%02x", $0) }.joined()
}
public func sourceFD(_ url: URL) throws -> Int32 {
    let parent = try Directory(url.deletingLastPathComponent().path)
    let f = openat(parent.fd, url.lastPathComponent, O_RDONLY | O_NOFOLLOW)
    guard f >= 0 else { throw fail("Source unavailable or linked: \(url.path)") }
    do { _ = try Fingerprint(fd: f); let v = try url.resourceValues(forKeys: [.isAliasFileKey]); guard v.isAliasFile != true else { throw fail("Finder alias skipped.") }; return f } catch { close(f); throw error }
}
