import Foundation
import CryptoKit
import Darwin

public enum MP3TagAction: String { case update, purge }
public struct MP3TagChange: Identifiable {
    public let id = UUID()
    public var key: String
    public var label: String
    public var before: String
    public var after: String
}
public struct MP3TagFile: Identifiable {
    public var id: String { url.path }
    public var url: URL
    public var changes: [MP3TagChange] = []
    public var blocked: String?
    public var fingerprint: Fingerprint?
    public var hash = ""
    public var parent: DirectoryIdentity?
    public init(url: URL, blocked: String? = nil) { self.url = url; self.blocked = blocked }
}
public struct MP3TagPlan {
    public var action: MP3TagAction
    public var profileName: String
    public var files: [MP3TagFile]
    public var skipped: [String]
    public var keep: Set<MP3KeepTag>
    public init(action: MP3TagAction, profile: Profile, items: [Item], cancel: Cancellation? = nil) {
        self.action = action; profileName = profile.name; let retained = profile.mp3TagsToKeep ?? Set(MP3KeepTag.allCases); keep = retained
        files = items.filter { $0.url.pathExtension.lowercased() == "mp3" }.map { cancel?.cancelled == true ? MP3TagFile(url: $0.url, blocked: "Preview cancelled") : MP3TagWriter.preview($0, action: action, keep: retained) }
        skipped = items.filter { $0.url.pathExtension.lowercased() != "mp3" }.map { $0.id }
    }
}
public enum MP3TagWriter {
    public static func historyRow(_ file: MP3TagFile) -> PlanRow {
        PlanRow(source: file.id, destination: file.id, fingerprint: file.fingerprint, hash: file.hash, status: "MP3 tag operation", explanation: "No Undo or retained backup", group: "")
    }
    public static func preview(_ item: Item, action: MP3TagAction, keep: Set<MP3KeepTag>) -> MP3TagFile {
        previewFile(item, action: action, keep: keep, temporary: false)
    }
    static func previewFile(_ item: Item, action: MP3TagAction, keep: Set<MP3KeepTag>, temporary: Bool) -> MP3TagFile {
        var result = MP3TagFile(url: item.url)
        do {
            guard item.url.pathExtension.lowercased() == "mp3" || (temporary && item.url.lastPathComponent.hasPrefix(".library-filer-") && item.url.pathExtension == "partial") else { throw fail("Only MP3 files are supported.") }
            if action == .purge && keep == Set(MP3KeepTag.allCases) { return result }
            let fd = try sourceFD(item.url); defer { close(fd) }
            var st = stat(); guard fstat(fd, &st) == 0, st.st_nlink == 1 else { throw fail("Hard-linked files are excluded from tag changes.") }
            let fingerprint = try Fingerprint(fd: fd), hash = try digest(fd: fd)
            let parent = try Directory(item.url.deletingLastPathComponent().path)
            let document = try MP3TagDocument(fd: fd)
            let metadata = MP3Metadata.read(item.url)
            guard metadata.notes.isEmpty else { throw fail("Metadata could not be fully read. " + metadata.notes.joined(separator: " ")) }
            if action == .update {
                for key in ["Artist", "Title", "Album", "Year", "TrackNumber", "Genre"] {
                    let value = FieldCatalog.get(key, item.fields).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { continue }
                    guard value.utf8.count <= 65_536, !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw fail("Invalid or excessive \(key) component; edit it before updating tags.") }
                    let existing = metadata.tags.filter { $0.component == key }
                    guard existing.isEmpty || existing.contains(where: { metadata.comparison($0, fields: item.fields) != "Matches component" }) else { continue }
                    let before = existing.isEmpty ? "Missing" : existing.map { $0.source + ": " + $0.value }.joined(separator: "\n")
                    result.changes.append(.init(key: key, label: key == "Year" ? "Release Year" : key == "TrackNumber" ? "Track Number" : key, before: before, after: value))
                }
            } else {
                for entry in document.entries where !keep.contains(MP3KeepTag.category(entry.key)) {
                    guard entry.source == "APEv2" ? entry.flags & 1 == 0 : entry.flags == 0 else { throw fail("A selected tag is protected or has unsupported frame flags. Use a dedicated tag editor for this file.") }
                    let tag = metadata.tags.first { $0.key.caseInsensitiveCompare(entry.key) == .orderedSame && $0.source.hasPrefix(entry.source) }
                    result.changes.append(.init(key: entry.id, label: tag?.label ?? entry.key, before: entry.source + " · " + entry.key + ": " + (tag?.value ?? "\(entry.raw.count) bytes"), after: "Removed"))
                }
            }
            // Validate every offered change now; unsupported representations never fail only after confirmation.
            _ = try document.encoded(changes: result.changes, action: action)
            let current = try sourceFD(item.url); defer { close(current) }
            guard try Fingerprint(fd: fd) == fingerprint, try Fingerprint(fd: current) == fingerprint, try digest(fd: fd) == hash else { throw fail("The file changed while preparing the preview. Preview again.") }
            result.fingerprint = fingerprint; result.hash = hash; result.parent = .init(device: parent.device, inode: parent.inode)
        } catch { result.blocked = error.localizedDescription; result.changes = [] }
        return result
    }
    public static func execute(_ file: MP3TagFile, action: MP3TagAction, selected: Set<UUID>, faultBeforePublish: Bool = false) throws {
        let changes = file.changes.filter { selected.contains($0.id) }
        guard !changes.isEmpty else { return }
        guard file.blocked == nil, let expected = file.fingerprint, let expectedParent = file.parent else { throw fail("This file is blocked. Preview again.") }
        let parent = try Directory(file.url.deletingLastPathComponent().path)
        guard parent.device == expectedParent.device, parent.inode == expectedParent.inode else { throw fail("The source folder changed. Preview again.") }
        let source = try sourceFD(file.url); defer { close(source) }
        guard try Fingerprint(fd: source) == expected, try digest(fd: source) == file.hash else { throw fail("Source changed since preview; no tags changed. Preview again.") }
        var st = stat(); guard fstat(source, &st) == 0, st.st_nlink == 1 else { throw fail("Hard-linked files cannot be rewritten.") }
        let document = try MP3TagDocument(fd: source), output = try document.encoded(changes: changes, action: action)
        let temporaryName = ".shelf-elf-tags-\(UUID().uuidString).partial"
        let temporaryURL = file.url.deletingLastPathComponent().appendingPathComponent(temporaryName)
        let target = openat(parent.fd, temporaryName, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
        guard target >= 0 else { throw fail("Cannot create a verified temporary replacement.") }
        var swapped = false
        defer {
            // Only remove the private temporary inode we created; a failed swap keeps recovery data.
            if !swapped, let check = try? sourceFD(temporaryURL) {
                var a = stat(), b = stat()
                if fstat(check, &a) == 0, fstat(target, &b) == 0, a.st_dev == b.st_dev, a.st_ino == b.st_ino { _ = unlinkat(parent.fd, temporaryName, 0) }
                close(check)
            }
            close(target)
        }
        guard fcopyfile(source, target, nil, copyfile_flags_t(COPYFILE_ALL)) == 0, ftruncate(target, 0) == 0, lseek(target, 0, SEEK_SET) >= 0 else { throw fail("Could not preserve file attributes; original retained.") }
        try write(output.0, fd: target)
        let audioHash = try stream(source, start: document.audioStart, count: document.audioEnd - document.audioStart, to: target)
        try write(output.1, fd: target)
        guard fsync(target) == 0 else { throw fail("Could not flush replacement; original retained.") }
        let verified = try MP3TagDocument(fd: target)
        guard verified.audioEnd - verified.audioStart == document.audioEnd - document.audioStart,
              try stream(target, start: verified.audioStart, count: verified.audioEnd - verified.audioStart, to: nil) == audioHash else { throw fail("Audio verification failed; original retained.") }
        let replacementHash = try digest(fd: target)
        guard !faultBeforePublish else { throw fail("Injected failure before publication; original retained.") }
        let currentParent = try Directory(parent.path), current = try sourceFD(file.url); defer { close(current) }
        guard currentParent.matches(parent), try Fingerprint(fd: source) == expected, try Fingerprint(fd: current) == expected, try digest(fd: source) == file.hash else { throw fail("Source or folder changed before publication; original retained.") }
        guard renameatx_np(parent.fd, temporaryName, parent.fd, file.url.lastPathComponent, UInt32(RENAME_SWAP)) == 0 else { throw fail("Atomic tag replacement failed; original retained.") }
        swapped = true
        let displaced = try sourceFD(temporaryURL); defer { close(displaced) }
        let displacedID = try Fingerprint(fd: displaced)
        guard displacedID.device == expected.device, displacedID.inode == expected.inode, try digest(fd: displaced) == file.hash else {
            // Refuse to delete an unexpected displaced file. Restore the swap when both paths still identify our held inodes.
            let published = try sourceFD(file.url); defer { close(published) }
            let publishedID = try Fingerprint(fd: published), targetID = try Fingerprint(fd: target)
            if publishedID.device == targetID.device, publishedID.inode == targetID.inode,
               renameatx_np(parent.fd, temporaryName, parent.fd, file.url.lastPathComponent, UInt32(RENAME_SWAP)) == 0 { swapped = false }
            throw fail("Source changed during publication. Inspect \(temporaryURL.path) if present; no displaced file was deleted.")
        }
        let published = try sourceFD(file.url); defer { close(published) }
        let publishedID = try Fingerprint(fd: published), targetID = try Fingerprint(fd: target)
        guard publishedID.device == targetID.device, publishedID.inode == targetID.inode, try digest(fd: published) == replacementHash else {
            throw fail("The published file changed unexpectedly. The temporary original was retained at \(temporaryURL.path). Inspect both files.")
        }
        guard unlinkat(parent.fd, temporaryName, 0) == 0 else { throw fail("Tags were updated, but the temporary original remains at \(temporaryURL.path).") }
        _ = fsync(parent.fd)
    }
    private static func write(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw fail("Temporary tag write failed; original retained.") }; offset += n
            }
        }
    }
    private static func stream(_ fd: Int32, start: Int64, count: Int64, to target: Int32?) throws -> String {
        guard count >= 0, lseek(fd, off_t(start), SEEK_SET) >= 0 else { throw fail("Invalid audio range.") }
        var left = count, hash = SHA256(), buffer = [UInt8](repeating: 0, count: 1024 * 1024)
        while left > 0 {
            let n = Darwin.read(fd, &buffer, min(buffer.count, Int(min(left, Int64(buffer.count)))))
            if n < 0 && errno == EINTR { continue }
            guard n > 0 else { throw fail("Audio read failed; original retained.") }
            let data = Data(buffer[0..<n]); hash.update(data: data); if let target { try write(data, fd: target) }; left -= Int64(n)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private struct MP3RawEntry {
    var id: String; var key: String; var source: String; var raw: Data; var payload: Data; var flags: UInt8 = 0
}
private struct MP3TagDocument {
    var version = 4, footer = false
    var id3: [MP3RawEntry] = [], ape: [MP3RawEntry] = [], legacy: Data?
    var apeFooter: Data?, apeHeader: Data?
    var audioStart: Int64 = 0, audioEnd: Int64 = 0
    var entries: [MP3RawEntry] {
        var all = id3 + ape
        if let legacy {
            for (key, start, count) in [("Title", 3, 30), ("Artist", 33, 30), ("Album", 63, 30), ("Year", 93, 4), ("Comment", 97, legacy[125] == 0 ? 28 : 30), ("Track", 126, 1), ("Genre", 127, 1)] {
                if key == "Track" && (legacy[125] != 0 || legacy[126] == 0) { continue }
                let bytes = legacy.subdata(in: start..<start + count)
                if key == "Genre" ? legacy[127] != 255 : bytes.contains(where: { $0 != 0 && $0 != 32 }) {
                    all.append(.init(id: "v1-" + key, key: key, source: "ID3v1", raw: bytes, payload: bytes))
                }
            }
        }
        return all
    }
    init(fd: Int32) throws {
        let size = try Fingerprint(fd: fd).size; audioEnd = size
        func read(_ offset: Int64, _ count: Int) throws -> Data {
            guard offset >= 0, count >= 0, Int64(count) <= size - offset, lseek(fd, off_t(offset), SEEK_SET) >= 0 else { throw fail("Invalid tag range.") }
            var data = Data(count: count)
            let got = data.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, count) }
            guard got == count else { throw fail("Truncated tag data.") }; return data
        }
        if size >= 3, try read(0, 3) == Data("ID3".utf8) {
            let header = try read(0, 10); version = Int(header[3])
            guard (2...4).contains(version), header[4] == 0, header[5] == 0 || (version == 4 && header[5] == 0x10) else { throw fail("This ID3 header uses unsupported compression, unsynchronisation or extended flags. Use a dedicated tag editor for this file.") }
            footer = header[5] == 0x10
            let length = try Self.number(header.subdata(in: 6..<10), sync: true)
            guard length <= 16 * 1024 * 1024 else { throw fail("ID3 tag exceeds the 16 MB writing limit.") }
            let body = try read(10, length); var offset = 0
            let h = version == 2 ? 6 : 10, k = version == 2 ? 3 : 4
            while offset < body.count {
                if body[offset] == 0 { guard body[offset...].allSatisfy({ $0 == 0 }) else { throw fail("Nonzero data follows ID3 padding.") }; break }
                guard id3.count < 2048, offset + h <= body.count else { throw fail("Invalid or excessive ID3 frames.") }
                let keyBytes = body.subdata(in: offset..<offset + k)
                guard keyBytes.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }), let key = String(data: keyBytes, encoding: .ascii) else { throw fail("Invalid ID3 frame identifier.") }
                let count = try Self.number(body.subdata(in: offset + k..<offset + h - (version == 2 ? 0 : 2)), sync: version == 4)
                guard count > 0, count <= body.count - offset - h else { throw fail("Invalid ID3 frame size.") }
                let raw = body.subdata(in: offset..<offset + h + count), payload = body.subdata(in: offset + h..<offset + h + count)
                id3.append(.init(id: "id3-\(id3.count)", key: key, source: "ID3v2.\(version)", raw: raw, payload: payload, flags: version == 2 ? 0 : body[offset + 9] | body[offset + 8]))
                offset += h + count
            }
            audioStart = Int64(10 + length + (footer ? 10 : 0))
            if footer { let end = try read(Int64(10 + length), 10); guard end.prefix(3) == Data("3DI".utf8), end[3...] == header[3...] else { throw fail("Invalid ID3 footer.") } }
        }
        if size >= 128 {
            let data = try read(size - 128, 128)
            if data.prefix(3) == Data("TAG".utf8) { legacy = data; audioEnd -= 128 }
        }
        if audioEnd >= 32 {
            let f = try read(audioEnd - 32, 32)
            if f.prefix(8) == Data("APETAGEX".utf8) {
                let length = Self.little(f.subdata(in: 12..<16)), count = Self.little(f.subdata(in: 16..<20))
                guard Self.little(f.subdata(in: 8..<12)) == 2000, length >= 32, length <= 16 * 1024 * 1024, count <= 2048 else { throw fail("Unsupported or excessive APE metadata.") }
                let start = audioEnd - Int64(length), body = try read(start, length - 32); var offset = 0
                for _ in 0..<count {
                    guard offset + 8 <= body.count else { throw fail("Truncated APE item.") }
                    let begin = offset, valueSize = Self.little(body.subdata(in: offset..<offset + 4)), flags = Self.little(body.subdata(in: offset + 4..<offset + 8)); offset += 8
                    guard let end = body[offset...].firstIndex(of: 0), end - offset <= 255, let key = String(data: body.subdata(in: offset..<end), encoding: .utf8) else { throw fail("Invalid APE item name.") }
                    offset = end + 1; guard valueSize <= body.count - offset else { throw fail("Truncated APE value.") }
                    ape.append(.init(id: "ape-\(ape.count)", key: key, source: "APEv2", raw: body.subdata(in: begin..<offset + valueSize), payload: body.subdata(in: offset..<offset + valueSize), flags: UInt8(flags & 255))); offset += valueSize
                }
                guard offset == body.count else { throw fail("Unrecognized data after APE items.") }
                apeFooter = f; audioEnd = start
                if f[23] & 0x80 != 0 { let h = try read(start - 32, 32); guard h.prefix(8) == Data("APETAGEX".utf8) else { throw fail("Missing APE header.") }; apeHeader = h; audioEnd -= 32 }
            }
        }
        if audioEnd >= 9 {
            let marker = try read(audioEnd - 9, 9)
            guard marker != Data("LYRICS200".utf8), marker != Data("LYRICSEND".utf8) else { throw fail("Legacy Lyrics3 tags require a dedicated tag editor before this operation.") }
        }
        if legacy != nil, audioEnd >= 227, try read(audioEnd - 227, 4) == Data("TAG+".utf8) { throw fail("Enhanced ID3v1 tags require a dedicated tag editor before this operation.") }
        if audioEnd >= 10, try read(audioEnd - 10, 3) == Data("3DI".utf8), audioEnd != audioStart { throw fail("Appended ID3 tags need a dedicated tag editor before this operation.") }
        guard audioEnd >= audioStart else { throw fail("Metadata ranges overlap; no tags can be safely changed.") }
        // Avoid treating a second leading tag as audio and silently preserving discrepancies.
        if audioEnd - audioStart >= 3, try read(audioStart, 3) == Data("ID3".utf8) { throw fail("Multiple leading ID3 tags require a dedicated tag editor.") }
    }
    func encoded(changes: [MP3TagChange], action: MP3TagAction) throws -> (Data, Data) {
        guard !changes.isEmpty else { return (Data(), Data()) }
        let removed = Set(action == .purge ? changes.map(\.key) : []), updated = action == .update ? Dictionary(uniqueKeysWithValues: changes.map { ($0.key, $0.after) }) : [:]
        var frames = Data()
        for frame in id3 where !removed.contains(frame.id) {
            if let component = Self.writeComponent(frame.key, source: frame.source), updated[component] != nil {
                guard frame.flags == 0 else { throw fail("A selected field has protected or encoded frame flags. Use a dedicated tag editor for this file.") }; continue
            }
            frames.append(frame.raw)
        }
        for key in ["Artist", "Title", "Album", "Year", "TrackNumber", "Genre"] {
            guard let value = updated[key] else { continue }
            let keys = ["Artist": version == 2 ? "TP1" : "TPE1", "Title": version == 2 ? "TT2" : "TIT2", "Album": version == 2 ? "TAL" : "TALB", "Year": version == 2 ? "TYE" : version == 3 ? "TYER" : "TDRC", "TrackNumber": version == 2 ? "TRK" : "TRCK", "Genre": version == 2 ? "TCO" : "TCON"]
            let payload = version == 4 ? Data([3]) + Data(value.utf8) : Data([1, 255, 254]) + (value.data(using: .utf16LittleEndian) ?? Data())
            frames.append(Data(keys[key]!.utf8) + Self.be(payload.count, bytes: version == 2 ? 3 : 4, sync: version == 4) + (version == 2 ? Data() : Data([0, 0])) + payload)
        }
        guard frames.count <= 16 * 1024 * 1024 else { throw fail("Resulting ID3 tag exceeds the writing limit.") }
        var head = Data()
        if !frames.isEmpty {
            let h = Data("ID3".utf8) + Data([UInt8(version), 0, footer ? 0x10 : 0]) + Self.be(frames.count, sync: true)
            head = h + frames
            if footer { head += Data("3DI".utf8) + h.dropFirst(3) }
        }
        var tail = Data(), items = Data(); var count = 0
        for entry in ape where !removed.contains(entry.id) {
            if let key = Self.writeComponent(entry.key, source: entry.source), let value = updated[key] {
                guard entry.flags == 0 else { throw fail("A selected APE item is protected or binary.") }
                let bytes = Data(value.utf8); items += Self.le(bytes.count) + Self.le(0) + Data(entry.key.utf8) + Data([0]) + bytes
            } else { items.append(entry.raw) }; count += 1
        }
        if count > 0, var f = apeFooter {
            f.replaceSubrange(12..<16, with: Self.le(items.count + 32)); f.replaceSubrange(16..<20, with: Self.le(count))
            if var h = apeHeader { h.replaceSubrange(12..<16, with: Self.le(items.count + 32)); h.replaceSubrange(16..<20, with: Self.le(count)); tail += h }
            tail += items + f
        }
        if var v1 = legacy {
            for (name, component, start, size) in [("Title", "Title", 3, 30), ("Artist", "Artist", 33, 30), ("Album", "Album", 63, 30), ("Year", "Year", 93, 4), ("Comment", "", 97, v1[125] == 0 ? 28 : 30)] {
                if removed.contains("v1-" + name) { v1.replaceSubrange(start..<start + size, with: Data(repeating: 0, count: size)) }
                if let value = updated[component] {
                    guard let bytes = value.data(using: .isoLatin1), bytes.count <= size else { throw fail("Legacy ID3v1 cannot store the complete \(component) value. Use a dedicated tag editor to remove or convert the legacy tag first.") }
                    v1.replaceSubrange(start..<start + size, with: bytes + Data(repeating: 0, count: size - bytes.count))
                }
            }
            if removed.contains("v1-Track") { v1[126] = 0 }
            if let value = updated["TrackNumber"] {
                guard v1[125] == 0, let number = UInt8(value), number > 0 else { throw fail("The legacy ID3v1 track cannot represent this value without losing comment data.") }; v1[126] = number
            }
            if removed.contains("v1-Genre") { v1[127] = 255 }
            if let value = updated["Genre"] {
                guard let number = ID3Genres.code(value) else { throw fail("Legacy ID3v1 cannot represent this genre with a supported standard code. Use a dedicated tag editor to convert the legacy tag first.") }; v1[127] = number
            }
            tail += v1
        }
        return (head, tail)
    }
    private static func writeComponent(_ key: String, source: String) -> String? {
        if source.hasPrefix("ID3v2") {
            return ["TPE1": "Artist", "TP1": "Artist", "TIT2": "Title", "TT2": "Title", "TALB": "Album", "TAL": "Album", "TYER": "Year", "TYE": "Year", "TDRC": "Year", "TRCK": "TrackNumber", "TRK": "TrackNumber", "TCON": "Genre", "TCO": "Genre"][key]
        }
        return ["artist": "Artist", "title": "Title", "album": "Album", "year": "Year", "track": "TrackNumber", "genre": "Genre"][key.lowercased()]
    }
    private static func number(_ d: Data, sync: Bool = false) throws -> Int { guard !sync || d.allSatisfy({ $0 < 128 }) else { throw fail("Invalid synchsafe tag size.") }; return d.reduce(0) { ($0 << (sync ? 7 : 8)) | Int($1) } }
    private static func little(_ d: Data) -> Int { d.reversed().reduce(0) { ($0 << 8) | Int($1) } }
    private static func be(_ n: Int, bytes: Int = 4, sync: Bool = false) -> Data { Data((0..<bytes).reversed().map { UInt8((n >> ($0 * (sync ? 7 : 8))) & (sync ? 127 : 255)) }) }
    private static func le(_ n: Int) -> Data { Data((0..<4).map { UInt8((n >> ($0 * 8)) & 255) }) }
}
