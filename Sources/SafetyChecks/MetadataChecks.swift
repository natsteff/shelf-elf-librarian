import Foundation
import FilerCore
import AVFoundation
import CoreVideo

extension FilerCoreTests {
    private func be(_ number: Int, count: Int = 4, sync: Bool = false) -> [UInt8] {
        (0..<count).reversed().map { UInt8((number >> ($0 * (sync ? 7 : 8))) & (sync ? 127 : 255)) }
    }
    private func frame(_ key: String, _ body: [UInt8], version: Int = 4, flags: UInt8 = 0) -> [UInt8] {
        Array(key.utf8) + be(body.count, count: version == 2 ? 3 : 4, sync: version == 4) + (version == 2 ? [] : [0, flags]) + body
    }
    private func tag(_ frames: [UInt8], version: Int = 4, flags: UInt8 = 0) -> [UInt8] {
        Array("ID3".utf8) + [UInt8(version), 0, flags] + be(frames.count, sync: true) + frames
    }
    private func writeMP3(_ bytes: [UInt8], name: String = "Filename Artist - Filename Title.mp3") throws -> URL {
        let url = src.appendingPathComponent(name); try Data(bytes).write(to: url); return url
    }
    func testMP3ReadOnlyReference() throws {
        var music = Profile(.music); music.root = library.path; music.folderMask = ""; music.filenameMask = "{Artist} - {Title}"; music.rootAllowed = true
        let data = tag(frame("TPE1", [3] + Array("Tag Artist".utf8)) + frame("TIT2", [3] + Array("Tag Title".utf8)) + frame("TALB", [3] + Array("Tag Album".utf8)) + frame("TRCK", [3] + Array("03/12".utf8))) + [255, 251, 144, 0]
        let url = try writeMP3(data), original = try Data(contentsOf: url)
        let found = try scan(src, profile: music, recursive: false).items[0]
        XCTAssertEqual(found.fields, Names.basicInterpret(url, music).0)
        XCTAssertEqual(found.fields.artist, "Filename Artist"); XCTAssertEqual(found.fields.album, "")
        XCTAssertEqual(found.metadata.tags.count, 4)
        XCTAssertEqual(found.metadata.comparison(found.metadata.tags[0], fields: found.fields), "Differs from component")
        XCTAssertEqual(found.metadata.comparison(found.metadata.tags[2], fields: found.fields), "Additional tag information")
        let magic = Magic.prepare([found], profile: music, memories: [])[0]
        XCTAssertEqual(magic.fields.artist, "Filename Artist"); XCTAssertEqual(magic.fields.album, "")
        XCTAssertEqual(magic.metadata, found.metadata)
        let q = try makeConfirmedFilingPlan(items: [found], profile: music, mode: .copy, keepCurrentNames: true)
        XCTAssertEqual(try executor().execute(q).completed, 1)
        XCTAssertEqual(try Data(contentsOf: url), original)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: q.rows[0].destination)), original)
        try FileManager.default.removeItem(at: URL(fileURLWithPath: q.rows[0].destination))
        var renamed = found; renamed.overrideBasename = "Chosen Artist - Chosen Title"
        let rename = try makeDirectRenamePlan(items: [renamed], profile: music)
        XCTAssertEqual(try executor().execute(rename).completed, 1)
        let renamedURL = URL(fileURLWithPath: rename.rows[0].destination)
        XCTAssertEqual(try Data(contentsOf: renamedURL), original)
        renamed.url = renamedURL
        let move = try makeConfirmedFilingPlan(items: [renamed], profile: music, mode: .move, keepCurrentNames: true)
        XCTAssertEqual(try executor().execute(move).completed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamedURL.path))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: move.rows[0].destination)), original)
        var fields = found.fields; fields.trackNumber = "3"
        XCTAssertEqual(found.metadata.comparison(found.metadata.tags[3], fields: fields), "Matches component")
    }
    func testID3VersionsAndValues() throws {
        for version in [2, 3, 4] {
            let key = version == 2 ? "TP1" : "TPE1"
            let utf16: [UInt8] = [1, 255, 254] + Array("Björk".data(using: .utf16LittleEndian)!)
            let artist = frame(key, utf16, version: version)
            let comment = frame(version == 2 ? "COM" : "COMM", [3] + Array("eng".utf8) + [0] + Array("A comment".utf8), version: version)
            let unknown = frame(version == 2 ? "XYZ" : "XABC", [0, 1, 2, 3], version: version)
            let art = frame(version == 2 ? "PIC" : "APIC", [0, 1, 2, 3], version: version)
            let url = try writeMP3(tag(artist + comment + unknown + art, version: version))
            let before = try Data(contentsOf: url), read = MP3Metadata.read(url)
            XCTAssertEqual(read.tags.count, 4); XCTAssertEqual(read.tags[0].value, "Björk")
            XCTAssertEqual(read.tags[1].value, "A comment"); XCTAssertTrue(read.tags[2].binary); XCTAssertTrue(read.tags[3].binary)
            XCTAssertTrue(read.tags[3].value.contains("artwork")); XCTAssertEqual(try Data(contentsOf: url), before)
        }
        let text = frame("TXXX", [3] + Array("Custom label".utf8) + [0] + Array("Custom value".utf8))
        let latin = frame("TPE1", [0, 66, 106, 246, 114, 107])
        let lyrics = frame("USLT", [3] + Array("eng".utf8) + [0] + Array("Long lyrics\nSecond line".utf8))
        let read = MP3Metadata.read(try writeMP3(tag(text + latin + lyrics)))
        XCTAssertEqual(read.tags[0].label, "User text: Custom label"); XCTAssertEqual(read.tags[0].value, "Custom value")
        XCTAssertEqual(read.tags[1].value, "Björk"); XCTAssertTrue(read.tags[2].value.contains("Second line"))
    }
    func testID3LegacyAndAPECoexist() throws {
        func padded(_ value: String, _ size: Int) -> [UInt8] { let b = Array(value.utf8); return b + Array(repeating: 0, count: size - b.count) }
        func little(_ n: Int) -> [UInt8] { (0..<4).map { UInt8((n >> ($0 * 8)) & 255) } }
        let apeItem = little(10) + little(0) + Array("Artist".utf8) + [0] + Array("APE Artist".utf8)
        let footer = Array("APETAGEX".utf8) + little(2000) + little(apeItem.count + 32) + little(1) + little(0) + Array(repeating: UInt8(0), count: 8)
        let v1 = Array("TAG".utf8) + padded("Old title", 30) + padded("Old artist", 30) + padded("Old album", 30) + Array("1999".utf8) + padded("Comment", 28) + [0, 7, 255]
        let url = try writeMP3(tag(frame("TPE1", [3] + Array("New artist".utf8))) + [255, 251, 0, 0] + apeItem + footer + v1)
        let found = MP3Metadata.read(url)
        XCTAssertTrue(found.tags.contains { $0.value == "New artist" && $0.source == "ID3v2.4" })
        XCTAssertTrue(found.tags.contains { $0.value == "Old artist" && $0.source == "ID3v1" })
        XCTAssertTrue(found.tags.contains { $0.value == "APE Artist" && $0.source == "APEv2" })
        XCTAssertTrue(found.tags.contains { $0.value == "7" && $0.component == "TrackNumber" })
    }
    func testID3FlagsAndMalformedInput() throws {
        let unsynced = frame("TPE1", [0, 65, 255, 0, 224, 66], flags: 2)
        let compressed = frame("TIT2", [0, 1, 2], flags: 8)
        let grouped = frame("TALB", [7, 3] + Array("Album".utf8), flags: 0x40)
        let extended: [UInt8] = [0, 0, 0, 6, 1, 0]
        let read = MP3Metadata.read(try writeMP3(tag(extended + unsynced + compressed + grouped, flags: 0x40)))
        XCTAssertEqual(read.tags[0].value, "AÿàB"); XCTAssertTrue(read.tags[1].binary); XCTAssertEqual(read.tags[2].value, "Album")
        let badFrames = frame("TPE1", [3] + Array("Artist".utf8)) + Array("TIT2".utf8) + [0, 0, 127, 127, 0, 0, 3]
        let malformed = MP3Metadata.read(try writeMP3(tag(badFrames)))
        XCTAssertEqual(malformed.tags.count, 1); XCTAssertFalse(malformed.notes.isEmpty)
        let huge = MP3Metadata.read(try writeMP3(Array("ID3".utf8) + [4, 0, 0, 127, 127, 127, 127]))
        XCTAssertFalse(huge.notes.isEmpty)
        let unsupported = MP3Metadata.read(try writeMP3(tag([], version: 5))); XCTAssertFalse(unsupported.notes.isEmpty)
        let noTags = MP3Metadata.read(try writeMP3([255, 251, 144, 0])); XCTAssertFalse(noTags.available)
        let appendedFrames = frame("TALB", [3] + Array("Appended album".utf8))
        let appendedHeader = tag(appendedFrames, flags: 0x10)
        let appendedFooter = Array("3DI".utf8) + [4, 0, 0x10] + be(appendedFrames.count, sync: true)
        let appended = MP3Metadata.read(try writeMP3([255, 251, 144, 0] + appendedHeader + appendedFooter))
        XCTAssertTrue(appended.tags.contains { $0.value == "Appended album" })
        let link = src.appendingPathComponent("link.mp3"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: src.appendingPathComponent("missing.mp3"))
        XCTAssertFalse(MP3Metadata.read(link).notes.isEmpty)
    }
    func testVideoMaskMetadataAndConflicts() throws {
        var video = Profile(.video); video.folderMask = "{Series}/Season {Season:02}"; video.filenameMask = "{Series} - {EpisodeID} - {EpisodeTitle} ({Year?}) [{Resolution?}]"
        let tags: [EmbeddedTag] = [("Series", "Tagged Show"), ("Season", "02"), ("Episode", "3"), ("EpisodeTitle", "Tagged episode"), ("Year", "2024-01-01"), ("Resolution", "1920x1080"), ("Genre", "Drama")].map { .init(key: $0.0, label: $0.0, value: $0.1, component: $0.0, source: "Fixture") }
        let metadata = EmbeddedMetadata(tags: tags, video: true)
        var fields = Fields(); fields.series = "Filename Show"
        let enriched = metadata.fillingVideoFields(fields, profile: video, source: src.appendingPathComponent("file.mp4"))
        XCTAssertEqual(enriched.0.series, "Filename Show"); XCTAssertEqual(enriched.0.season, "2"); XCTAssertEqual(enriched.0.episode, "3")
        XCTAssertEqual(enriched.0.episodeTitle, "Tagged episode"); XCTAssertEqual(enriched.0.year, "2024"); XCTAssertEqual(enriched.0.genre, "")
        XCTAssertEqual(enriched.0.resolution, "1920x1080")
        var conflict = metadata; conflict.tags.append(.init(key: "otherYear", label: "Year", value: "2001", component: "Year", source: "Fixture"))
        XCTAssertEqual(conflict.fillingVideoFields(fields, profile: video, source: src).0.year, "")
        video.filenameMask = "{Title}"; video.folderMask = ""
        XCTAssertEqual(metadata.fillingVideoFields(fields, profile: video, source: src).0, fields)
        XCTAssertEqual(metadata.fillingVideoFields(fields, profile: Profile(.music), source: src).0, fields)
        fields.season = "9"; fields.year = "1999"
        video.filenameMask = "{Year} {Season}"
        XCTAssertEqual(metadata.fillingVideoFields(fields, profile: video, source: src).0.year, "1999")
        XCTAssertEqual(metadata.fillingVideoFields(fields, profile: video, source: src).0.season, "9")
        var category = MediaCategory("Custom", folderMask: "{Genre}", filenameMask: "{Title}")
        category.rootFolder = "Videos"
        video.mediaRoutingEnabled = true; video.mediaCategories = [category]
        var routedFields = Fields(); routedFields.mediaCategory = "Custom"; routedFields.title = "Movie"
        let routed = metadata.fillingVideoFields(routedFields, profile: video, source: src)
        XCTAssertEqual(routed.0.genre, "Drama"); XCTAssertEqual(routed.0.year, "")
        let music = EmbeddedMetadata(tags: tags)
        XCTAssertEqual(music.fillingVideoFields(Fields(), profile: video, source: src).0, Fields())
    }
    func testVideoMagicAndManualPrecedence() throws {
        var video = Profile(.video); video.filenameMask = "{Title} ({Year?}) [{Resolution?}]"
        let url = try writeMP3([0], name: "Filename Movie.mp4")
        var item = Item(url: url, size: 1, fields: Names.basicInterpret(url, video).0, evidence: "Filename", reviewed: false)
        item.initialFields = item.fields
        item.metadata = EmbeddedMetadata(tags: [.init(key: "©nam", label: "Title", value: "Tag Movie", component: "Title", source: "Fixture"), .init(key: "©day", label: "Year", value: "2024", component: "Year", source: "Fixture")], video: true)
        let magic = Magic.prepare([item], profile: video, memories: [])[0]
        XCTAssertEqual(magic.fields.title, "Filename Movie"); XCTAssertEqual(magic.fields.year, "2024")
        item.fields.year = "1999"; item.overrideBasename = "My name"
        let manual = Magic.prepare([item], profile: video, memories: [])[0]
        XCTAssertEqual(manual.fields.year, "1999"); XCTAssertEqual(manual.overrideBasename, "My name")
        XCTAssertEqual(try Data(contentsOf: url), Data([0]))
    }
    func testNativeVideoMetadata() async throws {
        let url = src.appendingPathComponent("Filename Movie.mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let title = AVMutableMetadataItem(); title.identifier = .commonIdentifierTitle; title.value = "Embedded Movie" as NSString
        let date = AVMutableMetadataItem(); date.identifier = .iTunesMetadataReleaseDate; date.value = "2024" as NSString
        let show = AVMutableMetadataItem(); show.identifier = AVMetadataIdentifier(rawValue: "itsk/tvsh"); show.value = "Embedded Series" as NSString
        let season = AVMutableMetadataItem(); season.identifier = AVMetadataIdentifier(rawValue: "itsk/tvsn"); season.value = NSNumber(value: 2); season.dataType = kCMMetadataBaseDataType_UInt32 as String
        let episode = AVMutableMetadataItem(); episode.identifier = AVMetadataIdentifier(rawValue: "itsk/tves"); episode.value = NSNumber(value: 3); episode.dataType = kCMMetadataBaseDataType_UInt32 as String
        writer.metadata = [title, date, show, season, episode]
        var pixel: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess, let pixel else { throw fail("Video fixture pixel buffer failed") }
        CVPixelBufferLockBaseAddress(pixel, []); memset(CVPixelBufferGetBaseAddress(pixel), 0, CVPixelBufferGetDataSize(pixel)); CVPixelBufferUnlockBaseAddress(pixel, [])
        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &format) == noErr, let format else { throw fail("Video fixture format failed") }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? fail("Video fixture writer failed") }
        writer.startSession(atSourceTime: .zero)
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescription: format, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { throw fail("Video fixture sample failed") }
        for _ in 0..<100 where !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
        guard input.append(sample) else { throw writer.error ?? fail("Video fixture append failed") }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? fail("Video fixture finish failed") }
        let before = try Data(contentsOf: url)
        let read = await VideoMetadata.read(url)
        XCTAssertEqual(VideoMetadata.component(for: "%A9day"), "Year")
        XCTAssertEqual(VideoMetadata.component(for: "%C2%A9nam"), "Title")
        XCTAssertTrue(read.tags.contains { $0.component == "Title" && $0.value == "Embedded Movie" })
        XCTAssertTrue(read.tags.contains { $0.component == "Year" && $0.value == "2024" })
        XCTAssertTrue(read.tags.contains { $0.component == "Resolution" && $0.value == "16x16" })
        XCTAssertTrue(read.tags.contains { $0.component == "Series" && $0.value == "Embedded Series" })
        XCTAssertTrue(read.tags.contains { $0.component == "Season" && $0.value == "2" })
        XCTAssertTrue(read.tags.contains { $0.component == "Episode" && $0.value == "3" })
        var video = Profile(.video); video.filenameMask = "{Title} ({Year?}) [{Resolution?}]"
        let scan = try await scanMedia(src, profile: video, recursive: false)
        XCTAssertEqual(scan.items.count, 1); XCTAssertEqual(scan.items[0].fields.title, "Filename Movie")
        XCTAssertEqual(scan.items[0].fields.year, "2024"); XCTAssertEqual(scan.items[0].fields.resolution, "16x16")
        video.folderMask = "{Series}/Season {Season:02}"; video.filenameMask = "{Series} - {EpisodeID} - {EpisodeTitle}"
        let episodeScan = try await scanMedia(src, profile: video, recursive: false)
        XCTAssertEqual(episodeScan.items[0].fields.series, "Embedded Series")
        XCTAssertEqual(episodeScan.items[0].fields.episodeTitle, "Embedded Movie")
        XCTAssertEqual(episodeScan.items[0].fields.season, "2"); XCTAssertEqual(episodeScan.items[0].fields.episode, "3")
        XCTAssertEqual(episodeScan.items[0].fields.year, "") // not used by this mask
        XCTAssertEqual(try Data(contentsOf: url), before)
        let unsupported = await VideoMetadata.read(src.appendingPathComponent("file.mkv")); XCTAssertFalse(unsupported.notes.isEmpty)
        let bad = try writeMP3([1, 2, 3], name: "invalid.mp4")
        let invalid = await VideoMetadata.read(bad); XCTAssertFalse(invalid.notes.isEmpty)
        let cancel = Cancellation(); cancel.cancel()
        do { _ = try await scanMedia(src, profile: video, recursive: false, cancel: cancel); XCTAssertTrue(false) } catch { }
    }
}
