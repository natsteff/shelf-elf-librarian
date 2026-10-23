import Foundation
import FilerCore

extension FilerCoreTests {
    func testBuiltInMusicAndVideoParsing() throws {
        for kind in [Kind.music, .video] {
            var profile = ProfileSetup.configured(kind, name: "Existing")
            let url = src.appendingPathComponent(kind == .music ? "Monkey Boy - No Trail Leads Home.mp3" : "My Show - s01e03 - Pilot.mp4")
            let expected = Names.basicInterpret(url, profile).0
            let candidates: [[WorkspacePattern]?] = [nil, [], [WorkspacePattern("Existing interpretation", compatibility: true)], [WorkspacePattern("{Title}")], [WorkspacePattern("{Wrong} - {Broken}")]]
            for rows in candidates {
                profile.workspacePatterns = rows
                XCTAssertEqual(Names.basicInterpret(url, profile).0, expected)
                let magic = try XCTUnwrap(Magic.suggestions(url: url, profile: profile).first)
                if kind == .music { XCTAssertEqual(magic.fields.artist, "Monkey Boy"); XCTAssertEqual(magic.fields.title, "No Trail Leads Home") }
                else { XCTAssertEqual(magic.fields.series, "My Show"); XCTAssertEqual(magic.fields.episode, "03"); XCTAssertEqual(magic.fields.type, "TV Show") }
            }
            if kind == .music { XCTAssertEqual(expected.artist, "Monkey Boy") }
            else { XCTAssertEqual(expected.episodeTitle, "Pilot"); XCTAssertEqual(expected.type, "TV Show") }
        }
        var music = ProfileSetup.configured(.music, name: "Music"); music.exceptions = "BT-AI"
        let fields = Names.basicInterpret(src.appendingPathComponent("BT-AI -   The.Clock.Strikes.Thirteen.mp3"), music).0
        XCTAssertEqual(fields.artist, "BT-AI"); XCTAssertEqual(fields.title, "The Clock Strikes Thirteen")
        let numbered = Names.basicInterpret(src.appendingPathComponent("03 - Artist - Song.mp3"), music).0
        XCTAssertEqual(numbered.trackNumber, "03"); XCTAssertEqual(numbered.artist, "Artist")
    }
    func testSchemaTwoMediaProfileRepair() throws {
        for kind in [Kind.music, .video] {
            var profile = ProfileSetup.configured(kind, name: "Saved")
            profile.schemaVersion = 2; profile.root = library.path
            profile.workspacePatterns = [WorkspacePattern("Existing interpretation", compatibility: true)]
            let store = base.appendingPathComponent("profiles.json")
            try ProfileSettingsStore.write([profile], to: store)
            let read = try ProfileSettingsStore.read(from: store)
            let repaired = try read.map { try ProfileSetup.migrate($0) }
            XCTAssertNotEqual(repaired, read)
            XCTAssertEqual(repaired[0].workspacePatterns, nil)
            XCTAssertEqual(repaired[0].id, profile.id); XCTAssertEqual(repaired[0].root, profile.root)
            XCTAssertEqual(repaired[0].folderMask, profile.folderMask)
            try ProfileSettingsStore.write(repaired, to: store)
            XCTAssertEqual(try ProfileSettingsStore.read(from: store), repaired)
            XCTAssertEqual(try ProfileSetup.migrate(repaired[0]), repaired[0])
        }
        // Documents remain user-defined and their custom captures survive repair.
        let forge = try XCTUnwrap(ProfileSetup.starterProfiles.first { $0.name == "FORGE" })
        XCTAssertEqual(try ProfileSetup.migrate(forge), forge)
    }
    func testCommonVideoResolutionSetting() throws {
        var p = ProfileSetup.configured(.video, name: "Video")
        XCTAssertTrue(p.useCommonResolutionShorthand ?? true)
        let cases = ["644x480":"480p", "720x576":"480p", "1280x720":"720p", "1920x1080":"1080p", "1920x800":"1080p", "1080x1920":"1080p", "3840x2160":"4K", "4096x2160":"4K", "7680x4320":"8K", "1100x700":"720p"]
        for (raw, label) in cases { XCTAssertEqual(VideoResolution.display(raw, profile: p), label) }
        for label in ["1080i", "720p", "DVD", "Blu-ray", "4K", "", "0x480", "invalid"] { XCTAssertEqual(VideoResolution.display(label, profile: p), label) }
        var f = Fields(); f.title = "Movie"; f.resolution = "644x480"
        let url = src.appendingPathComponent("Movie.mp4")
        XCTAssertEqual(try Names.render("{Title} [{Resolution}]", fields: f, profile: p, source: url, folder: false), "Movie [480p]")
        let tags = EmbeddedMetadata(tags: [.init(key: "dimensions", label: "Resolution", value: "644x480", component: "Resolution", source: "Fixture")], video: true)
        var empty = Fields(); empty.title = "Movie"
        XCTAssertEqual(tags.fillingVideoFields(empty, profile: p, source: url).0.resolution, "480p")
        p.useCommonResolutionShorthand = false
        XCTAssertEqual(tags.fillingVideoFields(empty, profile: p, source: url).0.resolution, "644x480")
        XCTAssertEqual(try Names.render("{Title} [{Resolution}]", fields: f, profile: p, source: url, folder: false), "Movie [644x480]")
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p)).useCommonResolutionShorthand, false)
    }
    func testVideoResolutionRoundTrip() throws {
        var profile = ProfileSetup.configured(.video, name: "Videos")
        for name in ["Movie [480p].mp4", "Movie [644x480].mp4", "Movie [4K].mp4", "My Show - s01e03 - Pilot [480p].mp4"] {
            let url = src.appendingPathComponent(name)
            let fields = Names.basicInterpret(url, profile).0
            XCTAssertFalse(fields.resolution.isEmpty)
            XCTAssertFalse(fields.title.contains("[")); XCTAssertFalse(fields.episodeTitle.contains("["))
            let item = Item(url: url, size: 0, fields: fields, evidence: "", reviewed: true)
            let proposed = try proposedFilename(item, profile: profile)
            let refreshed = Names.basicInterpret(src.appendingPathComponent(proposed), profile).0
            XCTAssertEqual(try proposedFilename(Item(url: src.appendingPathComponent(proposed), size: 0, fields: refreshed, evidence: "", reviewed: true), profile: profile), proposed)
        }
        profile.useCommonResolutionShorthand = false
        let url = src.appendingPathComponent("Movie [644x480].mp4")
        let fields = Names.basicInterpret(url, profile).0
        XCTAssertEqual(try proposedFilename(Item(url: url, size: 0, fields: fields, evidence: "", reviewed: true), profile: profile), url.lastPathComponent)
    }

}
