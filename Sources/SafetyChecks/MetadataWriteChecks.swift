import Foundation
import FilerCore
import AVFoundation
import Darwin

@_silgen_name("sqlite3_open") private func testDBOpen(_ path: UnsafePointer<CChar>!, _ db: UnsafeMutablePointer<OpaquePointer?>!) -> Int32
@_silgen_name("sqlite3_close") private func testDBClose(_ db: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_prepare_v2") private func testPrepare(_ db: OpaquePointer!, _ sql: UnsafePointer<CChar>!, _ n: Int32, _ stmt: UnsafeMutablePointer<OpaquePointer?>!, _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>!) -> Int32
@_silgen_name("sqlite3_step") private func testStep(_ stmt: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_column_int") private func testInt(_ stmt: OpaquePointer!, _ column: Int32) -> Int32
@_silgen_name("sqlite3_finalize") private func testFinalize(_ stmt: OpaquePointer!) -> Int32

extension FilerCoreTests {
    private func tagBE(_ value: Int, bytes: Int = 4, sync: Bool = false) -> Data {
        Data((0..<bytes).reversed().map { UInt8((value >> ($0 * (sync ? 7 : 8))) & (sync ? 127 : 255)) })
    }
    private func tagFrame(_ key: String, _ value: Data, version: Int = 4) -> Data {
        Data(key.utf8) + tagBE(value.count, bytes: version == 2 ? 3 : 4, sync: version == 4) + (version == 2 ? Data() : Data([0, 0])) + value
    }
    private func tagText(_ key: String, _ value: String, version: Int = 4) -> Data { tagFrame(key, Data([3]) + Data(value.utf8), version: version) }
    private func tagEnvelope(_ frames: Data, version: Int = 4) -> Data { Data("ID3".utf8) + Data([UInt8(version), 0, 0]) + tagBE(frames.count, sync: true) + frames }
    private var testAudio: Data { Data([255, 251, 144, 0]) + Data(repeating: 0, count: 413) + Data([255, 251, 144, 0]) + Data(repeating: 0, count: 413) }
    private func tagItem(_ bytes: Data, name: String = "Artist - Song.mp3", fields: Fields = Fields()) throws -> Item {
        let url = src.appendingPathComponent(name); try bytes.write(to: url)
        return Item(url: url, size: Int64(bytes.count), fields: fields, evidence: "Fixture", reviewed: true)
    }
    private func legacyTag() -> Data {
        func padded(_ s: String, _ count: Int) -> Data { Data(s.utf8) + Data(repeating: 0, count: count - s.utf8.count) }
        return Data("TAG".utf8) + padded("Old Song", 30) + padded("Old Artist", 30) + padded("Old Album", 30) + Data("1999".utf8) + padded("Comment", 28) + Data([0, 1, 255])
    }
    private func apeTag() -> Data {
        func le(_ n: Int) -> Data { Data((0..<4).map { UInt8((n >> ($0 * 8)) & 255) }) }
        func item(_ key: String, _ value: Data, flags: Int = 0) -> Data { le(value.count) + le(flags) + Data(key.utf8) + Data([0]) + value }
        let items = item("Artist", Data("Old Artist".utf8)) + item("Title", Data("Old Song".utf8)) + item("Cover Art (Front)", Data([0, 9, 8, 7]), flags: 2)
        return items + Data("APETAGEX".utf8) + le(2000) + le(items.count + 32) + le(3) + le(0) + Data(repeating: 0, count: 8)
    }
    func testMusicKeepPolicyAndSections() throws {
        var music = Profile(.music)
        XCTAssertEqual(music.mp3TagsToKeep ?? Set(MP3KeepTag.allCases), Set(MP3KeepTag.allCases))
        let signature = Learning.settingsSignature(music)
        music.mp3TagsToKeep = [.artist, .artwork, .other]
        XCTAssertEqual(Learning.settingsSignature(music), signature)
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(music))
        XCTAssertEqual(decoded.mp3TagsToKeep, music.mp3TagsToKeep)
        var fields = Fields(); fields.artist = "Artist"; fields.title = "Title"; fields.album = "Album"; fields.year = "2024"; fields.trackNumber = "3"
        let tags: [EmbeddedTag] = [EmbeddedTag(key: "USLT", label: "Lyrics", value: "Text", source: "ID3v2.4")] + ["TrackNumber", "Year", "Album", "Title", "Artist"].map { .init(key: $0, label: $0, value: FieldCatalog.get($0, fields), component: $0, source: "ID3v2.4") }
        var metadata = EmbeddedMetadata(tags: tags)
        XCTAssertEqual(metadata.sections(fields: fields).map(\.title), ["Filename-related tags", "Other embedded tags"])
        XCTAssertEqual(metadata.sections(fields: fields)[0].tags.compactMap(\.component), ["Artist", "Title", "Album", "Year", "TrackNumber"])
        metadata.tags[1].value = "4"
        XCTAssertEqual(metadata.sections(fields: fields)[0].title, "Differences from filename components")
        XCTAssertEqual(metadata.sections(fields: fields)[0].tags[0].component, "TrackNumber")
        XCTAssertEqual(MP3KeepTag.category("APIC"), .artwork); XCTAssertEqual(MP3KeepTag.category("Cover Art (Front)"), .artwork)
    }
    func testUseTagValues() throws {
        let track = EmbeddedTag(key: "TRCK", label: "Track", value: "03/12", component: "TrackNumber", source: "ID3v2.4")
        XCTAssertEqual(try EmbeddedMetadata.fieldValue(track), "03")
        let year = EmbeddedTag(key: "TDRC", label: "Year", value: "2024-01-01", component: "Year", source: "ID3v2.4")
        XCTAssertEqual(try EmbeddedMetadata.fieldValue(year), "2024")
        XCTAssertThrowsError(try EmbeddedMetadata.fieldValue(.init(key: "APIC", label: "Art", value: "binary", source: "ID3v2.4", binary: true)))
        XCTAssertThrowsError(try EmbeddedMetadata.fieldValue(.init(key: "TPE1", label: "Artist", value: "A/B", component: "Artist", source: "ID3v2.4")))
        XCTAssertThrowsError(try EmbeddedMetadata.fieldValue(.init(key: "TDRC", label: "Year", value: "1999 · 2001", component: "Year", source: "ID3v2.4")))
        XCTAssertEqual(try EmbeddedMetadata.fieldValue(.init(key: "TIT2", label: "Title", value: "[Live] Song", component: "Title", source: "ID3v2.4")), "[Live] Song")
        var music = Profile(.music); music.filenameMask = "{Artist} - {Title}"; music.rules.artistTheToEnd = true
        var before = Fields(); before.artist = "Old Artist"; before.title = "Song"
        let tag = EmbeddedTag(key: "TPE1", label: "Artist", value: "The Beatles", component: "Artist", source: "ID3v2.4")
        var chosen = before; FieldCatalog.set("Artist", try EmbeddedMetadata.fieldValue(tag), &chosen)
        XCTAssertEqual(try Names.render(music.filenameMask, fields: chosen, profile: music, source: src, folder: false), "Beatles, The - Song")
        XCTAssertEqual(before.artist, "Old Artist"); XCTAssertEqual(chosen.title, before.title)
    }
    func testSelectiveMP3Writes() throws {
        let artwork = tagFrame("APIC", Data([0, 1, 2, 3, 4, 5])), unknown = tagFrame("XABC", Data([6, 7, 8]))
        let bytes = tagEnvelope(tagText("TPE1", "Old Artist") + tagText("TIT2", "Old Song") + artwork + unknown) + testAudio
        var fields = Fields(); fields.artist = "New Artist"; fields.title = "New Song"; fields.album = "New Album"
        let item = try tagItem(bytes, fields: fields)
        try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: item.id)
        let file = MP3TagWriter.preview(item, action: .update, keep: Set(MP3KeepTag.allCases))
        XCTAssertEqual(file.blocked, nil); XCTAssertEqual(file.changes.map(\.key), ["Artist", "Title", "Album"])
        let artist = try XCTUnwrap(file.changes.first { $0.key == "Artist" })
        try MP3TagWriter.execute(file, action: .update, selected: [artist.id])
        let metadata = MP3Metadata.read(item.url), result = try Data(contentsOf: item.url)
        XCTAssertTrue(metadata.tags.contains { $0.component == "Artist" && $0.value == "New Artist" })
        XCTAssertTrue(metadata.tags.contains { $0.component == "Title" && $0.value == "Old Song" })
        XCTAssertFalse(metadata.tags.contains { $0.component == "Album" })
        XCTAssertTrue(result.suffix(testAudio.count) == testAudio); XCTAssertNotEqual(result, bytes)
        XCTAssertTrue(result.range(of: artwork) != nil); XCTAssertTrue(result.range(of: unknown) != nil)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: item.id)[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: src.path).contains { $0.hasPrefix(".shelf-elf-tags-") })
    }
    func testMP3WriteVersions() throws {
        for version in [2, 3, 4] {
            let old = tagEnvelope(tagText(version == 2 ? "TP1" : "TPE1", "Old", version: version), version: version) + testAudio
            var fields = Fields(); fields.artist = "Björk"; fields.year = "2024"
            let item = try tagItem(old, name: "version\(version).mp3", fields: fields)
            let file = MP3TagWriter.preview(item, action: .update, keep: Set(MP3KeepTag.allCases))
            XCTAssertEqual(file.blocked, nil)
            try MP3TagWriter.execute(file, action: .update, selected: Set(file.changes.map(\.id)))
            let read = MP3Metadata.read(item.url)
            XCTAssertTrue(read.tags.contains { $0.component == "Artist" && $0.value == "Björk" })
            XCTAssertTrue(read.tags.contains { $0.component == "Year" && $0.value == "2024" })
            XCTAssertEqual(try Data(contentsOf: item.url).suffix(testAudio.count), testAudio)
        }
    }
    func testLegacyAPEUpdates() throws {
        let bytes = tagEnvelope(tagText("TPE1", "Old Artist") + tagText("TIT2", "Old Song")) + testAudio + apeTag() + legacyTag()
        var fields = Fields(); fields.artist = "New Artist"; fields.title = "New Song"; fields.genre = "Rock"
        let item = try tagItem(bytes, fields: fields), file = MP3TagWriter.preview(item, action: .update, keep: Set(MP3KeepTag.allCases))
        XCTAssertEqual(file.blocked, nil)
        try MP3TagWriter.execute(file, action: .update, selected: Set(file.changes.map(\.id)))
        let read = MP3Metadata.read(item.url)
        XCTAssertEqual(read.tags.filter { $0.component == "Artist" }.map(\.value), ["New Artist", "New Artist", "New Artist"])
        XCTAssertEqual(read.tags.filter { $0.component == "Title" }.map(\.value), ["New Song", "New Song", "New Song"])
        XCTAssertEqual(read.tags.filter { $0.component == "Genre" }.map(\.value), ["Rock", "Rock"])
        XCTAssertEqual(ID3Genres.code("Rock"), 17); XCTAssertEqual(ID3Genres.name(13), "Pop")
        XCTAssertTrue(read.tags.contains { $0.label == "Cover Art (Front)" && $0.binary })
        XCTAssertTrue(try Data(contentsOf: item.url).range(of: testAudio) != nil)
        var blocked = item; blocked.fields.artist = "漢字"
        XCTAssertNotEqual(MP3TagWriter.preview(blocked, action: .update, keep: []).blocked, nil)
    }
    func testMP3PurgeKeepList() throws {
        let artwork = tagFrame("APIC", Data([0, 1, 2, 3])), artist = tagText("TPE1", "Artist")
        let comment = tagFrame("COMM", Data([3]) + Data("eng".utf8) + Data([0]) + Data("Comment".utf8))
        let lyrics = tagFrame("USLT", Data([3]) + Data("eng".utf8) + Data([0]) + Data("Lyrics".utf8))
        let bytes = tagEnvelope(artist + artwork + comment + lyrics + tagText("TXXX", "Private")) + testAudio
        let item = try tagItem(bytes), all = Set(MP3KeepTag.allCases)
        XCTAssertTrue(MP3TagWriter.preview(item, action: .purge, keep: all).changes.isEmpty)
        let file = MP3TagWriter.preview(item, action: .purge, keep: all.subtracting([.comments, .lyrics, .other]))
        XCTAssertEqual(file.blocked, nil); XCTAssertEqual(file.changes.count, 3)
        try MP3TagWriter.execute(file, action: .purge, selected: Set(file.changes.map(\.id)))
        let read = MP3Metadata.read(item.url), result = try Data(contentsOf: item.url)
        XCTAssertEqual(Set(read.tags.map(\.key)), Set(["TPE1", "APIC"]))
        XCTAssertTrue(result.range(of: artwork) != nil); XCTAssertTrue(result.range(of: artist) != nil); XCTAssertEqual(result.suffix(testAudio.count), testAudio)
        let again = MP3TagWriter.preview(item, action: .purge, keep: [])
        try MP3TagWriter.execute(again, action: .purge, selected: Set(again.changes.map(\.id)))
        XCTAssertEqual(try Data(contentsOf: item.url), testAudio)
    }
    func testPurgeLegacyArtwork() throws {
        let item = try tagItem(tagEnvelope(tagText("TPE1", "Old Artist")) + testAudio + apeTag() + legacyTag())
        let file = MP3TagWriter.preview(item, action: .purge, keep: Set(MP3KeepTag.allCases).subtracting([.artist, .artwork]))
        XCTAssertEqual(file.blocked, nil)
        try MP3TagWriter.execute(file, action: .purge, selected: Set(file.changes.map(\.id)))
        let read = MP3Metadata.read(item.url)
        XCTAssertFalse(read.tags.contains { $0.component == "Artist" || $0.binary })
        XCTAssertTrue(read.tags.contains { $0.component == "Title" && $0.value == "Old Song" })
        XCTAssertTrue(try Data(contentsOf: item.url).range(of: testAudio) != nil)
    }
    func testMP3WriteGuards() throws {
        let bytes = tagEnvelope(tagText("TPE1", "Old")) + testAudio
        var fields = Fields(); fields.artist = "New"
        let item = try tagItem(bytes, fields: fields), file = MP3TagWriter.preview(item, action: .update, keep: [])
        try MP3TagWriter.execute(file, action: .update, selected: [])
        XCTAssertEqual(try Data(contentsOf: item.url), bytes)
        XCTAssertThrowsError(try MP3TagWriter.execute(file, action: .update, selected: Set(file.changes.map(\.id)), faultBeforePublish: true))
        XCTAssertEqual(try Data(contentsOf: item.url), bytes)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: src.path).contains { $0.hasPrefix(".shelf-elf-tags-") })
        try Data("External replacement".utf8).write(to: item.url)
        XCTAssertThrowsError(try MP3TagWriter.execute(file, action: .update, selected: Set(file.changes.map(\.id))))
        XCTAssertEqual(try Data(contentsOf: item.url), Data("External replacement".utf8))
        try bytes.write(to: item.url)
        try FileManager.default.linkItem(at: item.url, to: src.appendingPathComponent("hardlink.mp3"))
        XCTAssertNotEqual(MP3TagWriter.preview(item, action: .update, keep: []).blocked, nil)
        var invalid = bytes; invalid[5] = 0x40
        let flagged = try tagItem(invalid, name: "flagged.mp3", fields: fields)
        XCTAssertNotEqual(MP3TagWriter.preview(flagged, action: .update, keep: []).blocked, nil)
        var protectedFrame = tagText("TPE1", "Old"); protectedFrame[8] = 0x10
        let protectedItem = try tagItem(tagEnvelope(protectedFrame) + testAudio, name: "protected.mp3", fields: fields)
        XCTAssertNotEqual(MP3TagWriter.preview(protectedItem, action: .update, keep: []).blocked, nil)
        XCTAssertNotEqual(MP3TagWriter.preview(protectedItem, action: .purge, keep: []).blocked, nil)
        let lyricsItem = try tagItem(bytes + Data("LYRICS200".utf8), name: "legacy-lyrics.mp3", fields: fields)
        XCTAssertNotEqual(MP3TagWriter.preview(lyricsItem, action: .update, keep: []).blocked, nil)
        let parentItem = try tagItem(bytes, name: "parent.mp3", fields: fields), parentPlan = MP3TagWriter.preview(parentItem, action: .update, keep: [])
        let previous = base.appendingPathComponent("OriginalSource")
        try FileManager.default.moveItem(at: src, to: previous)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try bytes.write(to: src.appendingPathComponent("parent.mp3"))
        XCTAssertThrowsError(try MP3TagWriter.execute(parentPlan, action: .update, selected: Set(parentPlan.changes.map(\.id))))
        XCTAssertEqual(try Data(contentsOf: src.appendingPathComponent("parent.mp3")), bytes)
        var music = Profile(.music); music.mp3TagsToKeep = []
        let nonMP3 = try tagItem(Data([0]), name: "note.txt")
        let plan = MP3TagPlan(action: .purge, profile: music, items: [nonMP3])
        XCTAssertTrue(plan.files.isEmpty); XCTAssertEqual(plan.skipped, [nonMP3.id])
        let token = Cancellation(); token.cancel()
        XCTAssertNotEqual(MP3TagPlan(action: .update, profile: music, items: [item], cancel: token).files[0].blocked, nil)
    }
    func testMP3ContainerBoundaries() throws {
        var fields = Fields(); fields.artist = "New Artist"
        var head = tagEnvelope(tagText("TPE1", "Old Artist")); head[5] = 0x10
        let footer = Data("3DI".utf8) + head.subdata(in: 3..<10)
        let footerItem = try tagItem(head + footer + testAudio, name: "footer.mp3", fields: fields)
        let footerPlan = MP3TagWriter.preview(footerItem, action: .update, keep: [])
        XCTAssertEqual(footerPlan.blocked, nil)
        try MP3TagWriter.execute(footerPlan, action: .update, selected: Set(footerPlan.changes.map(\.id)))
        let footerResult = try Data(contentsOf: footerItem.url)
        XCTAssertEqual(footerResult.suffix(testAudio.count), testAudio)
        let footerOffset = footerResult.count - testAudio.count - 10
        XCTAssertEqual(footerResult.subdata(in: footerOffset..<footerOffset + 3), Data("3DI".utf8))
        XCTAssertTrue(MP3Metadata.read(footerItem.url).tags.contains { $0.value == "New Artist" })
        var ape = apeTag(), apeHead = Data(ape.suffix(32)); ape[ape.count - 9] = 0x80; apeHead[23] = 0xA0
        let headerItem = try tagItem(tagEnvelope(tagText("TPE1", "Old Artist")) + testAudio + apeHead + ape, name: "ape-header.mp3", fields: fields)
        let headerPlan = MP3TagWriter.preview(headerItem, action: .update, keep: [])
        XCTAssertEqual(headerPlan.blocked, nil)
        try MP3TagWriter.execute(headerPlan, action: .update, selected: Set(headerPlan.changes.map(\.id)))
        let metadata = MP3Metadata.read(headerItem.url)
        XCTAssertEqual(metadata.tags.filter { $0.component == "Artist" }.map(\.value), ["New Artist", "New Artist"])
        XCTAssertTrue(metadata.tags.contains { $0.label == "Cover Art (Front)" && $0.binary })
        XCTAssertTrue(try Data(contentsOf: headerItem.url).range(of: testAudio) != nil)
        let bare = try tagItem(testAudio, name: "untagged.mp3", fields: fields)
        let barePlan = MP3TagWriter.preview(bare, action: .update, keep: [])
        XCTAssertEqual(barePlan.blocked, nil); XCTAssertEqual(barePlan.changes.count, 1)
        try MP3TagWriter.execute(barePlan, action: .update, selected: Set(barePlan.changes.map(\.id)))
        XCTAssertTrue(MP3Metadata.read(bare.url).tags.contains { $0.component == "Artist" && $0.value == "New Artist" })
        XCTAssertEqual(try Data(contentsOf: bare.url).suffix(testAudio.count), testAudio)
    }
    func testThirtyDayHistoryRetention() throws {
        let now = Date(), old = now.addingTimeInterval(-31 * 86400), boundary = now.addingTimeInterval(-30 * 86400)
        var item = try item("remember.pdf"); item.initialFields = item.fields; item.fields.title = "Edited"; item.rememberCorrection = true
        var oldPlan = try plan([item]); oldPlan.created = old
        let db = base.appendingPathComponent("retention.sqlite"), journal = try Journal(url: db)
        try journal.plan(oldPlan); try journal.record(oldPlan.id, row: oldPlan.rows[0], state: "Copied", date: old)
        let recent = try plan([try self.item("recent.pdf")]); try journal.plan(recent)
        try journal.record(recent.id, row: recent.rows[0], state: "Copied", date: boundary)
        try FileManager.default.createDirectory(at: src.appendingPathComponent("messy_folder"), withIntermediateDirectories: true)
        let folders = try planFolders(workspace: src, profile: p), row = try XCTUnwrap(folders.rows.first)
        var folder = FolderEvent(operation: folders.id, row: row, state: "Renamed folder"); folder.date = old; try journal.recordFolder(folder)
        let bytes = try Data(contentsOf: item.url)
        try journal.pruneHistory(now: now)
        XCTAssertEqual(try journal.events().count, 1); XCTAssertEqual(try journal.events()[0].operation, recent.id)
        XCTAssertTrue(try journal.folderEvents().isEmpty)
        XCTAssertEqual(try journal.rememberedCorrections().count, 1)
        try journal.pruneHistory(now: now); XCTAssertEqual(try journal.rememberedCorrections().count, 1)
        XCTAssertEqual(try Data(contentsOf: item.url), bytes); XCTAssertTrue(FileManager.default.fileExists(atPath: row.source))
        var connection: OpaquePointer?, statement: OpaquePointer?
        XCTAssertEqual(testDBOpen(db.path, &connection), 0); defer { _ = testDBClose(connection) }
        XCTAssertEqual(testPrepare(connection, "SELECT count(*) FROM plans", -1, &statement, nil), 0); defer { _ = testFinalize(statement) }
        XCTAssertEqual(testStep(statement), 100); XCTAssertEqual(testInt(statement, 0), 1)
        var expired = try journal.events()[0]; expired.date = old
        XCTAssertThrowsError(try Executor(journal: journal).undo(expired, allowDeleteCopy: true))
    }
    func testNativeMP3AfterTagWrite() async throws {
        for version in [3, 4] {
            var fields = Fields(); fields.artist = "Björk"; fields.title = "New Song"
            let item = try tagItem(tagEnvelope(tagText("TPE1", "Old"), version: version) + testAudio + testAudio, name: "native\(version).mp3", fields: fields)
            let file = MP3TagWriter.preview(item, action: .update, keep: [])
            XCTAssertEqual(file.blocked, nil)
            try MP3TagWriter.execute(file, action: .update, selected: Set(file.changes.map(\.id)))
            let asset = AVURLAsset(url: item.url), formats = try await asset.load(.availableMetadataFormats)
            var values: [String] = []
            for format in formats { for tag in try await asset.loadMetadata(for: format) { if let text = try? await tag.load(.stringValue) { values.append(text) } } }
            XCTAssertTrue(values.contains("Björk")); XCTAssertTrue(values.contains("New Song"))
        }
    }
}

extension FilerCoreTests {
    func magicMusic() -> Profile {
        var p = Profile(.music); p.root = library.path; p.rootAllowed = true; p.folderMask = ""; p.filenameMask = "{Artist} - {Title}"
        p.rules.useMagic = true; p.classifications = [FilingType("Pop"), FilingType("Rock")]; return p
    }
    func magicSong(_ name: String = "Original Artist - Original Song.mp3", title: String = "New Song") throws -> Item {
        var f = Fields(); f.artist = "New Artist"; f.title = title; f.album = "New Album"; f.year = "2024"; f.trackNumber = "03"; f.genre = "Pop"
        let art = tagFrame("APIC", Data([0, 1, 2, 3, 4]))
        let comment = tagFrame("COMM", Data([3]) + Data("eng".utf8) + Data([0]) + Data("Comment".utf8))
        return try tagItem(tagEnvelope(tagText("TPE1", "Original Artist") + tagText("TIT2", "Original Song") + tagText("TCON", "Rock") + comment + art) + testAudio, name: name, fields: f)
    }
    func testMagicMP3DefaultsAndSnapshot() throws {
        var profile = magicMusic(); let item = try magicSong(), original = try Data(contentsOf: item.url)
        XCTAssertFalse(profile.magicUpdateMP3Tags ?? false); XCTAssertFalse(profile.magicPurgeMP3Tags ?? false)
        let normal = try makeMagicFilingPlan(items: [item], profile: profile, mode: .copy)
        XCTAssertEqual(normal.magicRun, true); XCTAssertEqual(normal.rows[0].magicMP3?.willChange, nil)
        let signature = Learning.settingsSignature(profile)
        profile.magicUpdateMP3Tags = true; profile.magicPurgeMP3Tags = true
        XCTAssertEqual(Learning.settingsSignature(profile), signature)
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded.magicUpdateMP3Tags, true); XCTAssertEqual(decoded.magicPurgeMP3Tags, true)
        let magic = try makeMagicFilingPlan(items: [item], profile: profile, mode: .copy)
        let saved = try JSONDecoder().decode(Plan.self, from: JSONEncoder().encode(magic))
        XCTAssertEqual(saved.magicRun, true); XCTAssertEqual(saved.rows[0].magicMP3?.fields.artist, "New Artist")
        profile.magicUpdateMP3Tags = false; profile.magicPurgeMP3Tags = false
        XCTAssertEqual(saved.profile.magicUpdateMP3Tags, true); XCTAssertEqual(saved.rows[0].magicMP3?.update, true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: magic.rows[0].destination))
        XCTAssertEqual(try Data(contentsOf: item.url), original)
    }
    func testMagicMP3CopyPipeline() throws {
        var p = magicMusic(); p.magicUpdateMP3Tags = true; p.magicPurgeMP3Tags = true
        p.mp3TagsToKeep = [.artist, .title, .album, .year, .track, .artwork]
        let item = try magicSong(), original = try Data(contentsOf: item.url)
        let plan = try makeMagicFilingPlan(items: [item], profile: p, mode: .copy)
        XCTAssertTrue(plan.rows[0].actionable); XCTAssertEqual(plan.rows[0].magicMP3?.willChange, true)
        let e = try executor(); XCTAssertEqual(try e.execute(plan).completed, 1)
        let output = URL(fileURLWithPath: plan.rows[0].destination), tags = MP3Metadata.read(output)
        XCTAssertEqual(output.lastPathComponent, "New Artist - New Song.mp3")
        XCTAssertTrue(tags.tags.contains { $0.component == "Artist" && $0.value == "New Artist" })
        XCTAssertTrue(tags.tags.contains { $0.component == "Album" && $0.value == "New Album" })
        XCTAssertTrue(tags.tags.contains { $0.key == "APIC" })
        XCTAssertFalse(tags.tags.contains { $0.component == "Genre" || $0.key == "COMM" })
        XCTAssertEqual(try Data(contentsOf: item.url), original)
        XCTAssertEqual(try Data(contentsOf: output).suffix(testAudio.count), testAudio)
        let event = try XCTUnwrap(try e.journal.events().first { $0.operation == plan.id && $0.state == "Copied" })
        XCTAssertTrue(event.hasMagicTagChanges)
        let fd = try sourceFD(output); defer { close(fd) }; XCTAssertEqual(event.row.hash, try digest(fd: fd))
        XCTAssertThrowsError(try e.undo(event, allowDeleteCopy: true))
        XCTAssertEqual(OperationPresentation.completedSources(plan: plan, events: try e.journal.events()), Set([item.id]))
    }
    func testMagicMP3MovePipeline() throws {
        var p = magicMusic(); p.magicUpdateMP3Tags = true; p.magicPurgeMP3Tags = true
        p.mp3TagsToKeep = Set(MP3KeepTag.allCases).subtracting([.artwork])
        let item = try magicSong(), plan = try makeMagicFilingPlan(items: [item], profile: p, mode: .move)
        let e = try executor(); XCTAssertEqual(try e.execute(plan).completed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.id))
        let output = URL(fileURLWithPath: plan.rows[0].destination), tags = MP3Metadata.read(output)
        XCTAssertTrue(tags.tags.contains { $0.component == "Artist" && $0.value == "New Artist" })
        XCTAssertFalse(tags.tags.contains { $0.key == "APIC" })
        XCTAssertEqual(try Data(contentsOf: output).suffix(testAudio.count), testAudio)
        let events = try e.journal.events().filter { $0.operation == plan.id }
        XCTAssertTrue(events.contains { $0.state == "Creating temporary copy" })
        let published = try XCTUnwrap(events.first { $0.state == "Copied" }), removed = try XCTUnwrap(events.first { $0.state == "Moved" })
        XCTAssertTrue(published.date <= removed.date); XCTAssertTrue(removed.hasMagicTagChanges)
        XCTAssertEqual(OperationPresentation.completedSources(plan: plan, events: events), Set([item.id]))
    }
    func testMagicMP3FailureAndBlockedRows() throws {
        var p = magicMusic(); p.magicUpdateMP3Tags = true; p.magicPurgeMP3Tags = true; p.mp3TagsToKeep = [.artist, .title]
        let item = try magicSong(), original = try Data(contentsOf: item.url)
        let plan = try makeMagicFilingPlan(items: [item], profile: p, mode: .move), e = try executor()
        XCTAssertEqual(try e.execute(plan, fault: .magicTagFailure).failed, 1)
        XCTAssertEqual(try Data(contentsOf: item.url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.rows[0].destination))
        XCTAssertTrue(OperationPresentation.completedSources(plan: plan, events: try e.journal.events()).isEmpty)
        let purgeFailure = try makeMagicFilingPlan(items: [item], profile: p, mode: .copy)
        XCTAssertEqual(try e.execute(purgeFailure, fault: .magicPurgeFailure).failed, 1)
        XCTAssertEqual(try Data(contentsOf: item.url), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: purgeFailure.rows[0].destination))
        let privatePath = try XCTUnwrap(try e.journal.events().first { $0.operation == purgeFailure.id && $0.state == "Preparing Magic MP3 tags" }?.temporary)
        XCTAssertTrue(MP3Metadata.read(URL(fileURLWithPath: privatePath)).tags.contains { $0.component == "Artist" && $0.value == "New Artist" })
        var invalidBytes = original; invalidBytes[5] = 0x40
        var invalidFields = item.fields; invalidFields.title = "Invalid Song"
        let invalid = try tagItem(invalidBytes, name: "invalid.mp3", fields: invalidFields)
        let mixed = try makeMagicFilingPlan(items: [item, invalid], profile: p, mode: .copy)
        XCTAssertEqual(mixed.rows.filter(\.actionable).count, 1)
        XCTAssertEqual(mixed.rows.first { $0.source == invalid.id }?.status, "MP3 tag steps blocked")
        XCTAssertEqual(try Data(contentsOf: invalid.url), invalidBytes)
    }
    func testMagicMP3CancellationAndPartialMove() throws {
        var p = magicMusic(); p.magicUpdateMP3Tags = true
        let a = try magicSong("First.mp3", title: "First"), b = try magicSong("Second.mp3", title: "Second")
        let beforeB = try Data(contentsOf: b.url), token = Cancellation()
        let plan = try makeMagicFilingPlan(items: [a, b], profile: p, mode: .move), e = try executor()
        let result = try e.execute(plan, cancel: token) { _, _ in token.cancel() }
        XCTAssertEqual(result.completed, 1); XCTAssertFalse(FileManager.default.fileExists(atPath: a.id))
        XCTAssertEqual(try Data(contentsOf: b.url), beforeB); XCTAssertFalse(FileManager.default.fileExists(atPath: plan.rows[1].destination))
        XCTAssertEqual(OperationPresentation.completedSources(plan: plan, events: try e.journal.events()), Set([a.id]))
        let partial = try makeMagicFilingPlan(items: [b], profile: p, mode: .move)
        XCTAssertEqual(try e.execute(partial, fault: .beforeDelete).failed, 1)
        XCTAssertEqual(try Data(contentsOf: b.url), beforeB)
        XCTAssertTrue(FileManager.default.fileExists(atPath: partial.rows[0].destination))
        XCTAssertTrue(MP3Metadata.read(URL(fileURLWithPath: partial.rows[0].destination)).tags.contains { $0.component == "Title" && $0.value == "Second" })
        XCTAssertTrue(OperationPresentation.completedSources(plan: partial, events: try e.journal.events()).isEmpty)
    }
    func testMagicMP3ScopeAndOptionalSteps() throws {
        let item = try magicSong(), before = try Data(contentsOf: item.url)
        var p = magicMusic(); p.magicUpdateMP3Tags = true; p.magicPurgeMP3Tags = true; p.mp3TagsToKeep = []
        p.folderMask = "Ordinary"
        let ordinary = try makeConfirmedFilingPlan(items: [item], profile: p, mode: .copy, keepCurrentNames: false)
        XCTAssertEqual(ordinary.magicRun, nil); XCTAssertEqual(ordinary.rows[0].magicMP3?.willChange, nil)
        XCTAssertEqual(try executor().execute(ordinary).completed, 1)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: ordinary.rows[0].destination)), before)
        p.folderMask = "Update"; p.magicPurgeMP3Tags = false
        let update = try makeMagicFilingPlan(items: [item], profile: p, mode: .copy)
        XCTAssertEqual(try executor().execute(update).completed, 1)
        let updated = MP3Metadata.read(URL(fileURLWithPath: update.rows[0].destination))
        XCTAssertTrue(updated.tags.contains { $0.component == "Artist" && $0.value == "New Artist" })
        XCTAssertTrue(updated.tags.contains { $0.key == "APIC" })
        p.folderMask = "Purge"; p.magicUpdateMP3Tags = false; p.magicPurgeMP3Tags = true; p.mp3TagsToKeep = [.artist, .title]
        let purge = try makeMagicFilingPlan(items: [item], profile: p, mode: .copy)
        XCTAssertEqual(try executor().execute(purge).completed, 1)
        let purged = MP3Metadata.read(URL(fileURLWithPath: purge.rows[0].destination))
        XCTAssertEqual(Set(purged.tags.map(\.key)), Set(["TPE1", "TIT2"]))
        XCTAssertTrue(purged.tags.contains { $0.component == "Artist" && $0.value == "Original Artist" })
        p.folderMask = "NonMP3"; p.extensions = "mp3, flac"; p.magicUpdateMP3Tags = true
        let flac = try tagItem(Data("Unchanged non-MP3 payload".utf8), name: "Artist - Song.flac", fields: item.fields)
        let other = try makeMagicFilingPlan(items: [flac], profile: p, mode: .copy)
        XCTAssertEqual(other.rows[0].magicMP3?.willChange, nil)
        XCTAssertEqual(try executor().execute(other).completed, 1)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: other.rows[0].destination)), try Data(contentsOf: flac.url))
    }
    func testMagicMP3StaleAndCollisionGuards() throws {
        var p = magicMusic(); p.magicUpdateMP3Tags = true
        let item = try magicSong(), plan = try makeMagicFilingPlan(items: [item], profile: p, mode: .copy)
        let external = Data("External replacement".utf8); try external.write(to: item.url)
        XCTAssertEqual(try executor().execute(plan).failed, 1); XCTAssertEqual(try Data(contentsOf: item.url), external)
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.rows[0].destination))
        let fresh = try magicSong("Fresh.mp3"), current = try makeMagicFilingPlan(items: [fresh], profile: p, mode: .move)
        let dest = URL(fileURLWithPath: current.rows[0].destination); try external.write(to: dest)
        let before = try Data(contentsOf: fresh.url)
        XCTAssertEqual(try executor().execute(current).failed, 1)
        XCTAssertEqual(try Data(contentsOf: dest), external); XCTAssertEqual(try Data(contentsOf: fresh.url), before)
        let token = Cancellation(); token.cancel()
        XCTAssertThrowsError(try makeMagicFilingPlan(items: [fresh], profile: p, mode: .copy, cancel: token))
    }
    func testMagicMP3NoopAndPreviewIsolation() throws {
        var p = magicMusic(); p.magicPurgeMP3Tags = true
        let item = try magicSong(), before = try Data(contentsOf: item.url)
        let contents = try FileManager.default.contentsOfDirectory(atPath: library.path)
        let plan = try makeMagicFilingPlan(items: [item], profile: p, mode: .move)
        XCTAssertEqual(plan.rows[0].magicMP3?.willChange, false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.path), contents)
        XCTAssertEqual(try Data(contentsOf: item.url), before)
        let e = try executor(); XCTAssertEqual(try e.execute(plan).completed, 1)
        let event = try XCTUnwrap(try e.journal.events().first { $0.operation == plan.id && $0.state == "Moved" })
        XCTAssertFalse(event.hasMagicTagChanges)
        try e.undo(event, allowDeleteCopy: false); XCTAssertEqual(try Data(contentsOf: item.url), before)
    }
}
