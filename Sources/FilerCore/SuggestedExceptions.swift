import Foundation

public struct SuggestionLoadResult {
    public var added = 0
    public var existing = 0
    public var conflicts = 0
    public var summary: String { "\(added) added · \(existing) already present · \(conflicts) conflicting spellings kept" }
}
extension UniversalPreferences {
    /// Curated suggestions only. No defaults belong in Other. Values contain no embedded newlines.
    public static let suggestedGroups: [String: String] = [
        "abbreviations": "AI, BPM, DIY, DJ, EP, FAQ, FPS, LP, MC, MMORPG, NASA, OST, RPG, RTS, TV",
        "names": "ABBA, ABC, AC-DC, AFI, a-ha, alt-J, AMC, AWOLNATION, B2K, bbno$, BBC, beabadoobee, BLACKPINK, blink-182, BØRNS, BTS, CBS, CHVRCHES, CNBC, CNN, D12, deadmau5, dEUS, ELO, ESPN, HBO, IDW, INXS, ITV, k.d. lang, keshi, KMFDM, LMFAO, M83, MGMT, MSNBC, MTV, NBC, NHK, NOFX, OMD, PBS, P!nk, PVRIS, R.E.M., Sum 41, SWV, TLC, U2, UB40, VNV Nation, will.i.am, XTC, ZZ Top",
        "brands": "AirDrop, AirPlay, AirPods, dBpoweramp, DOSBox, FFmpeg, foobar2000, Game Boy, GameCube, GitHub, GitLab, HomePod, iOS, iPad, iPadOS, iPhone, iPod, Jellyfin, MacBook, macOS, MusicBrainz, NES, Nintendo 3DS, Nintendo DS, Picard, PlayStation, Plex, PSP, PS Vita, RetroArch, ScummVM, SNES, tvOS, visionOS, VLC, watchOS, Wii, Wii U, Xbox, YouTube",
        "formats": "4K, 8K, 720p, 1080p, 2160p, 4320p, AAC, AC3, AIFF, ALAC, AV1, AVC, AVIF, AZW3, Blu-ray, CBR, CBZ, CD, CMYK, DMG, DNG, DSD, DTS, DVD, EAC3, EPUB, EXE, EXIF, FLAC, HD, HDR, HEIC, HEIF, HEVC, IMAX, IPTC, ISO, JPEG, JPG, MOBI, MP3, MSI, OCR, PCM, PDF, PKG, PNG, RAR, RGB, SACD, SDR, sRGB, TIFF, TrueHD, UHD, USB, WAV, WebP, Wi-Fi, WiFi, x264, x265, XMP, ZIP",
        "editions": "DLC, DOI, EU, GOTY, ISBN, ISSN, NTSC, PAL, Rev, UK, USA, Vol"
    ]
    public static var suggestedDefaults: UniversalPreferences {
        var prefs = UniversalPreferences()
        _ = prefs.appendSuggestions()
        return prefs
    }
    @discardableResult public mutating func appendSuggestions() -> SuggestionLoadResult {
        var result = SuggestionLoadResult()
        var found: [String: String] = [:]
        for entry in allEntries where found[entry.lowercased()] == nil { found[entry.lowercased()] = entry }
        for group in UniversalExceptionGroup.all where group.id != "other" {
            // Curated order is case-insensitive alphabetical, ignoring punctuation; do not reorder user entries.
            for entry in Self.entries(Self.suggestedGroups[group.id] ?? "").sorted(by: { a, b in
                func key(_ value: String) -> String { value.replacingOccurrences(of: "Ø", with: "O").replacingOccurrences(of: "ø", with: "o").filter { $0.isLetter || $0.isNumber }.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")) }
                return key(a).compare(key(b), options: [.numeric], locale: Locale(identifier: "en_US_POSIX")) == .orderedAscending
            }) {
                if let prior = found[entry.lowercased()] {
                    if prior == entry { result.existing += 1 } else { result.conflicts += 1 }
                    continue
                }
                let old = groups[group.id] ?? ""
                groups[group.id] = old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? entry : old + ", " + entry
                found[entry.lowercased()] = entry; result.added += 1
            }
        }
        return result
    }
}
