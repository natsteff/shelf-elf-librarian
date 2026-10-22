import Foundation

public enum MP3KeepTag: String, Codable, CaseIterable, Identifiable {
    case artist, title, album, albumArtist, year, track, disc, genre, artwork, comments, lyrics, other
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .artist: return "Artist"; case .title: return "Title"; case .album: return "Album"; case .albumArtist: return "Album Artist"
        case .year: return "Release Year"; case .track: return "Track Number"; case .disc: return "Disc Number"; case .genre: return "Genre"
        case .artwork: return "Artwork"; case .comments: return "Comments"; case .lyrics: return "Lyrics"; case .other: return "Other / custom tags"
        }
    }
    public static func category(_ key: String) -> Self {
        switch key.uppercased() {
        case "TPE1", "TP1", "ARTIST": return .artist
        case "TIT2", "TT2", "TITLE": return .title
        case "TALB", "TAL", "ALBUM": return .album
        case "TPE2", "TP2", "ALBUM ARTIST", "ALBUMARTIST": return .albumArtist
        case "TDRC", "TYER", "TYE", "TDRL", "YEAR", "DATE": return .year
        case "TRCK", "TRK", "TRACK", "TRACKNUMBER": return .track
        case "TPOS", "TPA", "DISC", "DISCNUMBER": return .disc
        case "TCON", "TCO", "GENRE": return .genre
        case "APIC", "PIC": return .artwork
        case "COMM", "COM", "COMMENT": return .comments
        case "USLT", "ULT", "SYLT", "SLT", "LYRICS": return .lyrics
        default: return key.uppercased().hasPrefix("COVER ART") ? .artwork : .other
        }
    }
    public var component: String? {
        switch self { case .artist: return "Artist"; case .title: return "Title"; case .album: return "Album"; case .year: return "Year"; case .track: return "TrackNumber"; case .genre: return "Genre"; default: return nil }
    }
}
public struct MetadataSection: Identifiable {
    public var id: String { title }
    public var title: String
    public var tags: [EmbeddedTag]
}
public extension EmbeddedMetadata {
    func sections(fields: Fields) -> [MetadataSection] {
        let order = ["Artist", "Title", "Album", "Year", "TrackNumber", "Genre", "Series", "Season", "Episode", "EpisodeTitle", "Resolution"]
        func sorted(_ tags: [EmbeddedTag]) -> [EmbeddedTag] {
            tags.enumerated().sorted { a, b in
                let x = order.firstIndex(of: a.element.component ?? "") ?? 100, y = order.firstIndex(of: b.element.component ?? "") ?? 100
                if x != y { return x < y }
                let compared = a.element.label.localizedStandardCompare(b.element.label)
                if compared != .orderedSame { return compared == .orderedAscending }
                let source = a.element.source.localizedStandardCompare(b.element.source)
                return source == .orderedSame ? a.offset < b.offset : source == .orderedAscending
            }.map(\.element)
        }
        let conflicts = tags.filter { comparison($0, fields: fields) == "Differs from component" }
        let mapped = tags.filter { $0.component != nil && !$0.binary && comparison($0, fields: fields) != "Differs from component" }
        let other = tags.filter { $0.component == nil || $0.binary }
        return [MetadataSection(title: "Differences from filename components", tags: sorted(conflicts)), MetadataSection(title: "Filename-related tags", tags: sorted(mapped)), MetadataSection(title: "Other embedded tags", tags: sorted(other))].filter { !$0.tags.isEmpty }
    }
    static func fieldValue(_ tag: EmbeddedTag) throws -> String {
        guard !tag.binary, let key = tag.component, ["Artist", "Title", "Album", "Year", "TrackNumber", "Genre"].contains(key) else { throw fail("This tag has no editable filename component.") }
        var value = tag.value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.contains(" · "), !value.hasPrefix("[Unsupported text encoding"), value != "[Undecodable text]" else { throw fail("This tag contains multiple or unreadable values. Edit the component manually.") }
        if key == "Genre" { value = ID3Genres.normalized(value) }
        if key == "TrackNumber" { value = value.components(separatedBy: "/")[0] }
        if key == "Year", value.count >= 4 { value = String(value.prefix(4)) }
        guard !value.isEmpty, !value.contains(" · "), !value.contains("/"), !value.contains(":"), !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { throw fail("This value cannot be used as a single filename component. Edit the component manually.") }
        if ["Year", "TrackNumber"].contains(key), Int(value) == nil { throw fail("Choose a numeric value or edit this component manually.") }
        return value
    }
}

/// Standard ID3v1 genre codes, as listed in ID3v2.3 Appendix A: https://id3.org/id3v2.3.0
public enum ID3Genres {
    private static let names = "Blues|Classic Rock|Country|Dance|Disco|Funk|Grunge|Hip-Hop|Jazz|Metal|New Age|Oldies|Other|Pop|R&B|Rap|Reggae|Rock|Techno|Industrial|Alternative|Ska|Death Metal|Pranks|Soundtrack|Euro-Techno|Ambient|Trip-Hop|Vocal|Jazz+Funk|Fusion|Trance|Classical|Instrumental|Acid|House|Game|Sound Clip|Gospel|Noise|AlternRock|Bass|Soul|Punk|Space|Meditative|Instrumental Pop|Instrumental Rock|Ethnic|Gothic|Darkwave|Techno-Industrial|Electronic|Pop-Folk|Eurodance|Dream|Southern Rock|Comedy|Cult|Gangsta|Top 40|Christian Rap|Pop/Funk|Jungle|Native American|Cabaret|New Wave|Psychadelic|Rave|Showtunes|Trailer|Lo-Fi|Tribal|Acid Punk|Acid Jazz|Polka|Retro|Musical|Rock & Roll|Hard Rock".components(separatedBy: "|")
    public static func name(_ code: UInt8) -> String { Int(code) < names.count ? names[Int(code)] : String(code) }
    public static func code(_ value: String) -> UInt8? {
        if let numeric = UInt8(value), numeric < 255 { return numeric }
        return names.firstIndex { $0.caseInsensitiveCompare(value) == .orderedSame }.map { UInt8($0) }
    }
    public static func normalized(_ value: String) -> String {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = text.hasPrefix("(") && text.hasSuffix(")") ? String(text.dropFirst().dropLast()) : text
        if let code = UInt8(digits) { return name(code) }; return text
    }
}
