import Foundation
import Darwin

/// Bounded, read-only ID3 inspection. Unknown/binary frames remain visible, never interpreted as filenames.
public enum MP3Metadata {
    private static let limit = 16 * 1024 * 1024
    public static func read(_ url: URL) -> EmbeddedMetadata {
        var result = EmbeddedMetadata()
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return EmbeddedMetadata(notes: ["Could not open MP3 tags. Refresh after checking file access."]) }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        defer { try? handle.close() }
        do {
            var info = stat(); guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { throw fail("Not a regular file.") }
            let length = UInt64(info.st_size)
            func bytes(_ offset: UInt64, _ count: Int) throws -> [UInt8] {
                try handle.seek(toOffset: offset); return Array(try handle.read(upToCount: count) ?? Data())
            }
            let header = try bytes(0, 10)
            if header.count < 10, Array(header.prefix(3)) == Array("ID3".utf8) { result.notes.append("The ID3 header is truncated.") }
            if header.count == 10, Array(header.prefix(3)) == Array("ID3".utf8) {
                let version = Int(header[3])
                if !(2...4).contains(version) { result.notes.append("ID3 version \(version) is not supported; tags were left untouched.") }
                else if let count = number(Array(header[6...9]), sync: true), count <= limit, UInt64(count + 10) <= length {
                    parseV2(try bytes(10, count), version: version, flags: header[5], into: &result)
                } else { result.notes.append("The ID3 header is truncated, invalid or exceeds the 16 MB reading limit.") }
            }
            var tail = length
            if length >= 128 {
                let v1 = try bytes(length - 128, 128)
                if v1.count == 128, Array(v1.prefix(3)) == Array("TAG".utf8) {
                    tail -= 128
                    for (label, key, start, count) in [("Title", "Title", 3, 30), ("Artist", "Artist", 33, 30), ("Album", "Album", 63, 30), ("Year", "Year", 93, 4), ("Comment", "", 97, v1[125] == 0 ? 28 : 30)] {
                        let value = text(Array(v1[start..<start + count]), encoding: 0)
                        if !value.isEmpty { result.tags.append(.init(key: label, label: label, value: value, component: key.isEmpty ? nil : key, source: "ID3v1")) }
                    }
                    if v1[125] == 0, v1[126] != 0 { result.tags.append(.init(key: "Track", label: "Track", value: String(v1[126]), component: "TrackNumber", source: "ID3v1.1")) }
                    if v1[127] != 255 { result.tags.append(.init(key: "Genre", label: "Genre code", value: String(v1[127]), source: "ID3v1")) }
                }
            }
            // APEv2 can coexist with ID3. Retain every discovered item, including binary item descriptions.
            if tail >= 32 {
                let footer = try bytes(tail - 32, 32)
                if footer.count == 32, String(bytes: footer.prefix(8), encoding: .ascii) == "APETAGEX" {
                    let size = little(Array(footer[12..<16])), count = little(Array(footer[16..<20]))
                    if size >= 32, size <= limit, UInt64(size) <= tail, count <= 2048 {
                        parseAPE(try bytes(tail - UInt64(size), size - 32), count: count, into: &result)
                        tail -= UInt64(size)
                    } else { result.notes.append("The APE tag is invalid or exceeds the reading limit.") }
                }
            }
            // ID3v2.4 may also be appended after audio and located by its footer.
            if tail >= 20 {
                let footer = try bytes(tail - 10, 10)
                if footer.count == 10, String(bytes: footer.prefix(3), encoding: .ascii) == "3DI" {
                    if footer[3] == 4, let count = number(Array(footer[6...9]), sync: true), count <= limit, UInt64(count + 20) <= tail {
                        let start = tail - UInt64(count + 20)
                        if start > 0 {
                            let tagHeader = try bytes(start, 10)
                            if tagHeader.count == 10, String(bytes: tagHeader.prefix(3), encoding: .ascii) == "ID3", tagHeader[3] == 4 {
                                parseV2(try bytes(start + 10, count), version: 4, flags: tagHeader[5], into: &result)
                            } else { result.notes.append("Appended ID3 tag has an invalid header.") }
                        }
                    } else { result.notes.append("Appended ID3 tag is invalid or exceeds the reading limit.") }
                }
            }
        } catch { result.notes.append("Some MP3 metadata could not be read: " + error.localizedDescription) }
        return result
    }
    private static func number(_ b: [UInt8], sync: Bool = false) -> Int? {
        if sync && b.contains(where: { $0 >= 128 }) { return nil }
        return b.reduce(0) { ($0 << (sync ? 7 : 8)) | Int($1) }
    }
    private static func little(_ b: [UInt8]) -> Int { b.reversed().reduce(0) { ($0 << 8) | Int($1) } }
    private static func unsync(_ b: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []; var i = 0
        while i < b.count { out.append(b[i]); if b[i] == 255 && i + 1 < b.count && b[i + 1] == 0 { i += 1 }; i += 1 }
        return out
    }
    private static func text(_ b: [UInt8], encoding: UInt8) -> String {
        let enc: String.Encoding
        switch encoding { case 0: enc = .isoLatin1; case 1: enc = .utf16; case 2: enc = .utf16BigEndian; case 3: enc = .utf8; default: return "[Unsupported text encoding \(encoding)]" }
        return (String(data: Data(b), encoding: enc) ?? "[Undecodable text]").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.controlCharacters)).replacingOccurrences(of: "\0", with: " · ")
    }
    private static func split(_ b: [UInt8], encoding: UInt8) -> ([UInt8], [UInt8]) {
        let step = encoding == 1 || encoding == 2 ? 2 : 1
        var i = 0
        while i + step <= b.count {
            if b[i] == 0 && (step == 1 || b[i + 1] == 0) { return (Array(b[..<i]), Array(b[(i + step)...])) }; i += step
        }
        return (b, [])
    }
    private static let aliases = ["TT2": "TIT2", "TP1": "TPE1", "TP2": "TPE2", "TAL": "TALB", "TRK": "TRCK", "TYE": "TYER", "TCO": "TCON", "TPA": "TPOS", "TXX": "TXXX", "COM": "COMM", "ULT": "USLT", "PIC": "APIC", "WXX": "WXXX"]
    private static let labels = ["TIT2": "Title", "TPE1": "Artist", "TPE2": "Album Artist", "TALB": "Album", "TRCK": "Track", "TPOS": "Disc", "TYER": "Year", "TDRC": "Recording date / year", "TCON": "Genre", "TCOM": "Composer", "TCOP": "Copyright", "TENC": "Encoded by", "TBPM": "BPM", "COMM": "Comment", "USLT": "Lyrics", "APIC": "Artwork", "PRIV": "Private data", "POPM": "Rating / play count", "UFID": "Unique identifier", "TSOA": "Album sort order", "TSOP": "Artist sort order", "TSOT": "Title sort order"]
    private static let components = ["TIT2": "Title", "TPE1": "Artist", "TALB": "Album", "TRCK": "TrackNumber", "TYER": "Year", "TDRC": "Year", "TCON": "Genre"]
    private static func parseV2(_ input: [UInt8], version: Int, flags: UInt8, into result: inout EmbeddedMetadata) {
        if version == 2 && flags & 0x40 != 0 { result.notes.append("Compressed ID3v2.2 tags cannot be displayed."); return }
        let b = version < 4 && flags & 0x80 != 0 ? unsync(input) : input
        var offset = 0
        if version >= 3 && flags & 0x40 != 0 {
            guard b.count >= 4, let size = number(Array(b[0..<4]), sync: version == 4) else { result.notes.append("Invalid ID3 extended header."); return }
            offset = size + (version == 3 ? 4 : 0)
            guard offset >= (version == 3 ? 10 : 6), offset <= b.count else { result.notes.append("Invalid ID3 extended header size."); return }
        }
        var frames = 0
        let headerSize = version == 2 ? 6 : 10, keySize = version == 2 ? 3 : 4
        while offset + headerSize <= b.count, b[offset] != 0, frames < 2048 {
            let keyBytes = Array(b[offset..<offset + keySize])
            guard keyBytes.allSatisfy({ (65...90).contains($0) || (48...57).contains($0) }), let rawKey = String(bytes: keyBytes, encoding: .ascii), let count = number(Array(b[(offset + keySize)..<(offset + headerSize - (version == 2 ? 0 : 2))]), sync: version == 4), count > 0, count <= b.count - offset - headerSize else { result.notes.append("Stopped at a malformed or truncated ID3 frame; earlier tags are shown."); break }
            let key = aliases[rawKey] ?? rawKey
            let frameFlags = version == 2 ? UInt8(0) : b[offset + 9]
            var payload = Array(b[(offset + headerSize)..<(offset + headerSize + count)])
            offset += headerSize + count; frames += 1
            let opaque = version == 3 ? frameFlags & 0xC0 != 0 : frameFlags & 0x0C != 0
            if version == 4 && (frameFlags & 0x02 != 0 || flags & 0x80 != 0) { payload = unsync(payload) }
            if !opaque {
                let prefix = (version == 3 && frameFlags & 0x20 != 0 ? 1 : 0) + (version == 4 && frameFlags & 0x40 != 0 ? 1 : 0) + (version == 4 && frameFlags & 0x01 != 0 ? 4 : 0)
                guard payload.count >= prefix else { result.notes.append("Invalid frame prefix: " + rawKey); continue }; payload = Array(payload.dropFirst(prefix))
            }
            var value = "\(count) bytes of binary data", label = labels[key] ?? key, binary = true
            if opaque { value = "\(count) bytes; compressed or encrypted frame" }
            else if key.hasPrefix("T"), let encoding = payload.first {
                binary = false
                if key == "TXXX" {
                    let parts = split(Array(payload.dropFirst()), encoding: encoding)
                    label = "User text: " + text(parts.0, encoding: encoding); value = text(parts.1, encoding: encoding)
                } else { value = text(Array(payload.dropFirst()), encoding: encoding) }
            } else if ["COMM", "USLT"].contains(key), payload.count >= 4 {
                let parts = split(Array(payload.dropFirst(4)), encoding: payload[0])
                let description = text(parts.0, encoding: payload[0])
                label += description.isEmpty ? "" : " — " + description
                value = text(parts.1, encoding: payload[0]); binary = false
            } else if key == "WXXX", let encoding = payload.first {
                let parts = split(Array(payload.dropFirst()), encoding: encoding)
                label = "URL: " + text(parts.0, encoding: encoding); value = text(parts.1, encoding: 0); binary = false
            } else if key.hasPrefix("W") { value = text(payload, encoding: 0); binary = false }
            else if key == "APIC" { value = "Embedded artwork (\(count) bytes); retained unchanged" }
            result.tags.append(.init(key: rawKey, label: label, value: value, component: binary ? nil : components[key], source: "ID3v2.\(version)", binary: binary))
        }
        if frames == 2048 { result.notes.append("Stopped at the 2,048-frame reading limit.") }
    }
    private static func parseAPE(_ b: [UInt8], count: Int, into result: inout EmbeddedMetadata) {
        var offset = 0
        let mapping = ["title": "Title", "artist": "Artist", "album": "Album", "track": "TrackNumber", "year": "Year", "genre": "Genre"]
        for _ in 0..<count {
            guard offset + 8 <= b.count else { result.notes.append("Truncated APE metadata."); return }
            let size = little(Array(b[offset..<offset + 4])), flags = little(Array(b[offset + 4..<offset + 8])); offset += 8
            guard let end = b[offset...].firstIndex(of: 0), end - offset <= 255 else { result.notes.append("Invalid APE item name."); return }
            let key = String(bytes: b[offset..<end], encoding: .utf8) ?? "Unknown APE item"; offset = end + 1
            guard size <= b.count - offset else { result.notes.append("Truncated APE item."); return }
            let binary = ((flags >> 1) & 3) != 0
            let value = binary ? "\(size) bytes of binary/external data" : text(Array(b[offset..<offset + size]), encoding: 3)
            result.tags.append(.init(key: key, label: key, value: value, component: binary ? nil : mapping[key.lowercased()], source: "APEv2", binary: binary)); offset += size
        }
    }
}
