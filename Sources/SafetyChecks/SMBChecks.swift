import Foundation
import Darwin
import FilerCore

extension FilerCoreTests {
    /// Run the same algorithm on local fixtures; optionally use a dedicated disposable SMB folder.
    func testSMBTransfers() throws {
        XCTAssertFalse(LibraryStorage.isSMB(src.path))
        for mode in [Mode.copy, .move] {
            let input = try item("smb-\(mode.rawValue).pdf")
            let original = try Data(contentsOf: input.url), q = try plan([input], mode)
            let e = try executor(), result = try e.execute(q, forceSMBForTests: true)
            XCTAssertEqual(result.completed, 1)
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: q.rows[0].destination)), original)
            XCTAssertEqual(FileManager.default.fileExists(atPath: input.id), mode == .copy)
        }
        let input = try item("smb-collision.pdf"), q = try plan([input], .move)
        let occupied = URL(fileURLWithPath: q.rows[0].destination)
        try FileManager.default.createDirectory(at: occupied.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("KEEP".utf8).write(to: occupied)
        XCTAssertEqual(try executor().execute(q, forceSMBForTests: true).failed, 1)
        XCTAssertEqual(try Data(contentsOf: occupied), Data("KEEP".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: input.id))
        let lowSpace = try item("smb-low-space.pdf"), lowPlan = try plan([lowSpace], .move)
        let lowExecutor = try executor()
        XCTAssertThrowsError(try lowExecutor.execute(lowPlan, forceSMBForTests: true, availableSMBBytesForTests: 0))
        XCTAssertTrue(FileManager.default.fileExists(atPath: lowSpace.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lowPlan.rows[0].destination))
        let interrupted = try item("smb-interrupted.pdf"), stopped = try plan([interrupted], .move)
        let e = try executor()
        XCTAssertEqual(try e.execute(stopped, fault: .verification, forceSMBForTests: true).failed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: interrupted.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: stopped.rows[0].destination))
        XCTAssertTrue(try e.journal.events().contains { $0.temporary == stopped.rows[0].destination })
        var profile = p!; profile.bucket = true; profile.rules.numericBucket = "Numbers"; profile.rules.symbolBucket = "Symbols"; profile.rules.ignoreLeadingThe = true
        profile.smbNoticeLibraries = [library.path]; profile.bucket = false
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(profile))
        XCTAssertFalse(decoded.bucket); XCTAssertEqual(decoded.rules.numericBucket, "Numbers")
        XCTAssertEqual(decoded.rules.symbolBucket, "Symbols"); XCTAssertTrue(decoded.rules.ignoreLeadingThe)
        XCTAssertEqual(decoded.smbNoticeLibraries, [library.path])
    }
    func testSMBMagic() throws {
        for mode in [Mode.copy, .move] {
            var profile = magicMusic(); profile.magicUpdateMP3Tags = true
            let input = try magicSong( "smb-magic-\(mode.rawValue).mp3", title: "SMB \(mode.rawValue)")
            let original = try Data(contentsOf: input.url)
            let q = try makeMagicFilingPlan(items: [input], profile: profile, mode: mode)
            let e = try executor(), result = try e.execute(q, forceSMBForTests: true)
            XCTAssertEqual(result.completed, 1)
            let output = URL(fileURLWithPath: q.rows[0].destination)
            XCTAssertTrue(MP3Metadata.read(output).tags.contains { $0.component == "Artist" && $0.value == "New Artist" })
            XCTAssertEqual(FileManager.default.fileExists(atPath: input.id), mode == .copy)
            if mode == .copy { XCTAssertEqual(try Data(contentsOf: input.url), original) }
            let event = try XCTUnwrap(try e.journal.events().first { $0.state == "Copied" && $0.operation == q.id })
            let fd = try sourceFD(output); defer { close(fd) }
            XCTAssertEqual(event.resultIdentity, try Fingerprint(fd: fd))
        }
    }
}
