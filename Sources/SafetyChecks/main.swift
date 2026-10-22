
var failures = 0
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a != b { failures += 1; print("FAIL \(file):\(line): \(a) != \(b)") } }
func XCTAssertNotEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { if a == b { failures += 1; print("FAIL \(file):\(line): values equal") } }
func XCTAssertTrue(_ a: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a, true, file: file, line: line) }
func XCTAssertFalse(_ a: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a, false, file: file, line: line) }
func XCTAssertThrowsError<T>(_ a: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) { do { _ = try a(); failures += 1; print("FAIL \(file):\(line): expected failure") } catch {} }
func XCTUnwrap<T>(_ a: T?) throws -> T { guard let a else { throw fail("Missing expected test value") }; return a }
import Foundation
import FilerCore
import Darwin

if let index = CommandLine.arguments.firstIndex(of: "--write-starter-settings"), CommandLine.arguments.count > index + 1 {
    do {
        let profiles = ProfileSetup.starterProfiles
        let archive = SettingsArchive(profiles: profiles, general: .suggestedDefaults, activeProfileID: profiles.first?.id)
        _ = try archive.validatedProfiles()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(archive).write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), options: .atomic)
        print("Wrote starter settings archive."); exit(0)
    } catch { print("Starter settings export failed: \(error.localizedDescription)"); exit(1) }
}

if let index = CommandLine.arguments.firstIndex(of: "--validate-settings"), CommandLine.arguments.count > index + 1 {
    do {
        let archive = try JSONDecoder().decode(SettingsArchive.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[index + 1])))
        let validated = try archive.validatedProfiles()
        print("Settings archive validated: \(validated.count) profiles; original file unchanged.")
        exit(0)
    } catch { print("Settings archive validation failed: \(error.localizedDescription)"); exit(1) }
}

final class FilerCoreTests {
    var base: URL!; var src: URL!; var library: URL!; var p: Profile!
    func setUpWithError() throws {
        base = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("LibraryFilerTests-\(UUID())")
        src = base.appendingPathComponent("Source"); library = base.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: library.appendingPathComponent("Reports"), withIntermediateDirectories: true)
        p = Profile(.documents); p.root = library.path
    }
    func tearDownWithError() throws { if base != nil { try FileManager.default.removeItem(at: base) } }
    func item(_ name: String = "project_report__2025_FINAL.pdf") throws -> Item {
        let u = src.appendingPathComponent(name); try Data("FICTIONAL PAYLOAD\n\(name)".utf8).write(to: u)
        let r = Names.interpret(u, p); return Item(url: u, size: Int64(try Data(contentsOf: u).count), fields: r.0, evidence: r.1, reviewed: true)
    }
    func plan(_ items: [Item], _ mode: Mode = .copy) throws -> Plan { try makePlan(items: items, profile: p, mode: mode, category: "Reports", fileOnly: false) }
    func executor() throws -> Executor { try Executor(journal: Journal(url: base.appendingPathComponent("journal.sqlite"))) }
    func testGroupedDestinations() throws {
        let a = try item("Episode10.pdf"), b = try item("Episode2.pdf"), c = try item("Movie.pdf")
        var q = try plan([a, b, c]); q.rows[0].destination = library.path + "/TV Shows/Season 01/Episode10.pdf"
        q.rows[1].destination = library.path + "/TV Shows/Season 01/Episode2.pdf"
        q.rows[2].destination = library.path + "/Movies/Movie.pdf"
        var blocked = q.rows[0]; blocked.id = UUID(); blocked.status = "Needs review"; blocked.destination = ""; q.rows.append(blocked)
        let groups = OperationPresentation.groups(q)
        XCTAssertEqual(groups.map(\.title), ["Movies", "TV Shows / Season 01", "Needs attention"])
        XCTAssertEqual(groups[1].rows.map(\.source), [b.id, a.id]); XCTAssertTrue(groups[2].blocked)
        XCTAssertEqual(Set(groups.flatMap(\.rows).map(\.id)), Set(q.rows.map(\.id)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.path + "/TV Shows"))
    }
    func testMoveCompletionAndRefresh() throws {
        let a = try item("a.pdf"); var b = try item("b.pdf"); b.overrideBasename = "My edited name"; b.reviewed = false
        var reviewedB = b; reviewedB.reviewed = true
        let q = try plan([a, reviewedB], .move), e = try executor(), token = Cancellation()
        _ = try e.execute(q, cancel: token) { _, _ in token.cancel() }
        let done = OperationPresentation.completedSources(plan: q, events: try e.journal.events())
        XCTAssertEqual(done, Set([a.id]))
        let fresh = try scan(src, profile: p, recursive: false)
        let updated = OperationPresentation.reconcile(existing: [a, b], scanned: fresh.items, selected: Set([a.id, b.id]), completed: done, rememberNew: false)
        XCTAssertEqual(updated.selected, Set([b.id])); XCTAssertEqual(updated.items.count, 1)
        XCTAssertEqual(updated.items[0].overrideBasename, "My edited name"); XCTAssertFalse(updated.items[0].reviewed)
        let copy = try plan([try item("failed.pdf")]); _ = try e.execute(copy, fault: .afterPublish)
        XCTAssertTrue(OperationPresentation.completedSources(plan: copy, events: try e.journal.events()).isEmpty)
    }
    func testReplacementRootRepreview() throws {
        let i = try item(); let original = try Directory(library.path)
        p.rootIdentity = DirectoryIdentity(device: original.device, inode: original.inode)
        try FileManager.default.moveItem(at: library, to: base.appendingPathComponent("OldLibrary"))
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        XCTAssertThrowsError(try plan([i]))
        let replacement = try Directory(library.path)
        p.rootIdentity = DirectoryIdentity(device: replacement.device, inode: replacement.inode)
        let q = try plan([i]); XCTAssertTrue(FileManager.default.fileExists(atPath: i.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: q.rows[0].destination))
        try FileManager.default.moveItem(at: library, to: base.appendingPathComponent("SecondLibrary"))
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        XCTAssertEqual(try executor().execute(q).failed, 1); XCTAssertTrue(FileManager.default.fileExists(atPath: i.id))
    }
    func testArtistTheToEnd() throws {
        var music = Profile(.music)
        XCTAssertEqual(RuleEngine.artistName("The Beatles", profile: music), "The Beatles")
        XCTAssertFalse(music.rules.ignoreLeadingThe); music.rules.artistTheToEnd = true
        for (input, expected) in [("The Beatles", "Beatles, The"), ("the 1975", "1975, The"), ("Theocracy", "Theocracy"), ("The", "The"), ("Beatles, The", "Beatles, The")] {
            XCTAssertEqual(RuleEngine.artistName(input, profile: music), expected)
        }
        let url = src.appendingPathComponent("The Beatles - Yesterday.mp3")
        let fields = Names.basicInterpret(url, music).0
        XCTAssertEqual(fields.artist, "Beatles, The")
        XCTAssertEqual(try Names.render("{Artist}", fields: fields, profile: music, source: url, folder: true), "Beatles, The")
        var video = Profile(.video); video.rules.artistTheToEnd = true
        XCTAssertEqual(RuleEngine.artistName("The Beatles", profile: video), "The Beatles")
        XCTAssertEqual(UniversalExceptionGroup.all.first { $0.id == "other" }?.examples, "LaTeX, myCustomName, iMonkey")
    }
    func testCopyAndGuardedUndo() throws {
        let i = try item(), original = try Data(contentsOf: i.url); let q = try plan([i]); let e = try executor()
        XCTAssertEqual(try e.execute(q).completed, 1)
        XCTAssertEqual(try Data(contentsOf: i.url), original)
        let dest = URL(fileURLWithPath: q.rows[0].destination)
        XCTAssertEqual(try Data(contentsOf: dest), original)
        let event = try XCTUnwrap(e.journal.events().first { $0.state == "Copied" })
        XCTAssertThrowsError(try e.undo(event, allowDeleteCopy: false))
        try e.undo(event, allowDeleteCopy: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: i.url.path))
    }
    func testSameVolumeMoveUndoAndOccupiedSource() throws {
        let i = try item(); let q = try plan([i], .move); let e = try executor()
        XCTAssertEqual(try e.execute(q).completed, 1); XCTAssertFalse(FileManager.default.fileExists(atPath: i.url.path))
        let event = try XCTUnwrap(e.journal.events().first { $0.state == "Moved" })
        try Data("external".utf8).write(to: i.url); XCTAssertThrowsError(try e.undo(event, allowDeleteCopy: false)); try FileManager.default.removeItem(at: i.url)
        try e.undo(event, allowDeleteCopy: false); XCTAssertTrue(FileManager.default.fileExists(atPath: i.url.path))
    }
    func testVerifiedCopyMoveEngine() throws {
        let i = try item(); let original = try Data(contentsOf: i.url); let q = try plan([i], .move)
        XCTAssertEqual(try executor().execute(q, forceCopyMoveForTests: true).completed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: i.url.path)); XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: q.rows[0].destination)), original)
    }
    func testVerificationFailureRetainsSourceAndRecovery() throws {
        let i = try item(); let q = try plan([i], .move); let e = try executor()
        let r = try e.execute(q, fault: .verification, forceCopyMoveForTests: true)
        XCTAssertEqual(r.failed, 1); XCTAssertTrue(FileManager.default.fileExists(atPath: i.url.path)); XCTAssertFalse(FileManager.default.fileExists(atPath: q.rows[0].destination))
        let reopened = try Journal(url: base.appendingPathComponent("journal.sqlite"))
        XCTAssertTrue(try reopened.events().contains { $0.temporary != nil })
    }
    func testPublicationFailureRetainsBothAndTruthfulState() throws {
        let i = try item(); let q = try plan([i], .move); let e = try executor()
        XCTAssertEqual(try e.execute(q, fault: .afterPublish, forceCopyMoveForTests: true).failed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: i.url.path)); XCTAssertTrue(FileManager.default.fileExists(atPath: q.rows[0].destination)); XCTAssertFalse(try e.journal.events().contains { $0.state == "Moved" })
    }
    func testExistingAndLateConflictsNeverOverwrite() throws {
        let i = try item(); let q = try plan([i]); let d = URL(fileURLWithPath: q.rows[0].destination)
        try Data("EXTERNAL".utf8).write(to: d)
        XCTAssertEqual(try executor().execute(q).failed, 1); XCTAssertEqual(try Data(contentsOf: d), Data("EXTERNAL".utf8))
        XCTAssertEqual(try plan([i]).rows[0].status, "Destination conflict")
    }
    func testBatchCollisionAndNoOp() throws {
        let a = try item("a.pdf"), b = try item("b.pdf"); var aa = a, bb = b; aa.fields.title = "Same"; bb.fields.title = "same"
        XCTAssertTrue(try plan([aa, bb]).rows.allSatisfy { $0.status == "Destination conflict" })
        let q = try makePlan(items: [a], profile: p, mode: .clean, category: "", fileOnly: true)
        XCTAssertEqual(q.rows[0].status, "No change needed")
    }
    func testStaleSourceAndReplacedRoot() throws {
        let i = try item(); let q = try plan([i]); try Data("changed".utf8).write(to: i.url)
        XCTAssertEqual(try executor().execute(q).failed, 1)
        let q2 = try plan([i]); try FileManager.default.moveItem(at: library, to: base.appendingPathComponent("OldLibrary")); try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        XCTAssertEqual(try executor().execute(q2).failed, 1)
    }
    func testLinksAndTraversal() throws {
        _ = try item(); try FileManager.default.createSymbolicLink(at: src.appendingPathComponent("linked.pdf"), withDestinationURL: src.appendingPathComponent("missing.pdf"))
        let scanResult = try scan(src, profile: p, recursive: true); XCTAssertEqual(scanResult.items.count, 1); XCTAssertEqual(scanResult.excluded.count, 1)
        XCTAssertThrowsError(try component("..")); XCTAssertThrowsError(try component("A/B")); XCTAssertThrowsError(try component("/tmp"))
        var i = scanResult.items[0]; i.fields.title = "../escape"; XCTAssertFalse(try plan([i]).rows[0].actionable)
        let link = base.appendingPathComponent("LinkedLibrary"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: library); XCTAssertThrowsError(try Directory(link.path))
    }
    func testCancellationBetweenFiles() throws {
        let q = try plan([item("a.pdf"), item("b.pdf")]); let token = Cancellation()
        let r = try executor().execute(q, cancel: token) { _, _ in token.cancel() }
        XCTAssertEqual(r.completed, 1); XCTAssertTrue(FileManager.default.fileExists(atPath: q.rows[1].source)); XCTAssertFalse(FileManager.default.fileExists(atPath: q.rows[1].destination))
    }
    func testChangedCopyUndoRefused() throws {
        let i = try item(); let q = try plan([i]); let e = try executor(); _ = try e.execute(q)
        let event = try XCTUnwrap(e.journal.events().first { $0.state == "Copied" }); try Data("external changed".utf8).write(to: URL(fileURLWithPath: q.rows[0].destination))
        XCTAssertThrowsError(try e.undo(event, allowDeleteCopy: true))
    }
    func testProfilesMixedAndNames() throws {
        for name in ["Film.mkv", "Video.MP4", "Artist - Title.mp3", "Author - Book.m4b", "Report.pdf", "notes.txt"] { _ = try item(name) }
        XCTAssertEqual(try scan(src, profile: p, recursive: false).items.count, 1)
        var music = Profile(.music); music.root = library.path
        var books = Profile(.audiobook); books.root = base.appendingPathComponent("OtherLibrary").path
        XCTAssertTrue(music.accepted.contains("mp3")); XCTAssertTrue(books.accepted.contains("mp3")); XCTAssertNotEqual(music.root, books.root)
        XCTAssertEqual(Names.clean("project_report__2025_FINAL", p), "Project Report 2025 Final")
        var v = Profile(.video); XCTAssertEqual(Names.clean("The.Example.Film.2024.1080p.WEB-DL", v), "The Example Film 2024"); XCTAssertEqual(Names.clean("Version 1.2 DJ", v), "Version 1.2 DJ"); XCTAssertEqual(Names.clean("J.R.R. Tolkien", v), "J.R.R. Tolkien"); XCTAssertTrue(Names.clean("Film (Director's Cut) 2024", v).contains("Director"))
        v.replaceDots = false; XCTAssertTrue(Names.clean("Version 1.2 DJ", v).contains("1.2 DJ"))
    }
    func testSharedChapterGroupAndNewFolderRace() throws {
        p = Profile(.audiobook); p.root = library.path
        var chapters = try [item("01 - Arrival.mp3"), item("02 - The Letter.mp3"), item("03 - Harbor Lights.mp3")]
        for i in chapters.indices { chapters[i].fields.author = "Mira Vale"; chapters[i].fields.bookTitle = "The Glass Harbor"; chapters[i].reviewed = true }
        let q = try plan(chapters)
        XCTAssertTrue(q.rows.allSatisfy(\.actionable))
        let r = try executor().execute(q); XCTAssertEqual(r.completed, 3)
        XCTAssertTrue(q.rows[0].destination.hasSuffix("Mira Vale/The Glass Harbor/01 - Arrival.mp3"))
        for row in q.rows { XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: row.source)), try Data(contentsOf: URL(fileURLWithPath: row.destination))) }
        var other = try item("04 - Next.mp3"); other.fields.author = "New Author"; other.fields.bookTitle = "New Book"; other.reviewed = true
        let race = try plan([other]); try FileManager.default.createDirectory(atPath: race.rows[0].newFolders[0], withIntermediateDirectories: true)
        XCTAssertEqual(try executor().execute(race).failed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: other.url.path))
    }
    func testMusicAndVideoPlansAndExtensionCase() throws {
        p = Profile(.music); p.root = library.path
        let song = try item("northbound_-_midnight_lines.MP3")
        let music = try plan([song]); XCTAssertTrue(music.rows[0].destination.hasSuffix("N/Northbound/Northbound - Midnight Lines.MP3"))
        XCTAssertEqual(try executor().execute(music).completed, 1)
        p = Profile(.video); p.root = library.path
        let movie = try item("The.Example.Film.2024.1080p.WEB-DL.mkv")
        let video = try plan([movie]); XCTAssertTrue(video.rows[0].destination.hasSuffix("The Example Film (2024)/The Example Film (2024).mkv"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.rows[0].newFolders[0]))
        XCTAssertEqual(try executor().execute(video).completed, 1)
    }
    func testNewRulesAndExtensionPreservation() throws {
        p = Profile(.other); p.root = library.path; p.extensions = "rom, pdf"; var rules = p.rules
        rules.hyphensToSpaces = true; p.rules = rules
        let i = try item("My--Game (USA) v1.2.ROM")
        XCTAssertEqual(try proposedFilename(i, profile: p), "My Game (USA) v1.2.ROM") // no whitespace normalization until enabled
        rules.hyphensToSpaces = false; rules.dotsToDashes = true; p.rules = rules
        XCTAssertEqual(Names.clean("one.two.three", p), "one - two - three")
        rules.dotsToDashes = false
        rules.replacements = [ReplacementRule(find: "__", replacement: "-"), ReplacementRule(find: "-", replacement: " ")]
        p.rules = rules; XCTAssertEqual(Names.clean("one__two", p), "one two")
        rules.replacements = [ReplacementRule(find: "old", replacement: "new", target: .folder)]
        p.rules = rules; XCTAssertEqual(Names.clean("old", p), "old"); XCTAssertEqual(RuleEngine.folder("old", profile: p), "new")
        var anchored = ReplacementRule(find: "TAG ", replacement: ""); anchored.position = .prefix
        rules.replacements = [anchored]; p.rules = rules
        XCTAssertEqual(Names.clean("TAG Song TAG Remix", p), "Song TAG Remix")
        var music = Profile(.music); music.prefix = "[Approved] "; music.suffix = " [Local]"
        let song = URL(fileURLWithPath: "/private/tmp/artist - title.MP3")
        let interpreted = Names.basicInterpret(song, music)
        let songItem = Item(url: song, size: 1, fields: interpreted.0, evidence: interpreted.1, reviewed: true)
        XCTAssertEqual(try proposedFilename(songItem, profile: music), "[Approved] Artist - Title [Local].MP3")
        XCTAssertThrowsError(try { var invalid = rules; invalid.replacements = [ReplacementRule(find: "x", replacement: "../bad")]; try invalid.validate() }())
    }
    func testSmartTitleAndEpisodeRules() throws {
        p = Profile(.video); p.extensions = "mkv"; p.titleCase = true
        var rules = p.rules; rules.smartTitleCase = true; rules.formatEpisodes = true; rules.lowercaseEpisodes = true; p.rules = rules
        XCTAssertEqual(Names.clean("the lord of the rings", p), "The Lord of the Rings")
        p.replaceDots = true; p.replaceUnderscores = true
        XCTAssertEqual(Names.clean("my.show.S1E2.the_rise_of_the_elf", p), "My Show - s01e02 - The Rise of the Elf")
        let fields = Names.basicInterpret(URL(fileURLWithPath: "/private/tmp/My.Show.S01E02.The.Elf.mkv"), p).0
        XCTAssertEqual(fields.season, "01"); XCTAssertEqual(fields.episode, "02")
        XCTAssertEqual(try Names.render("{Series} - {EpisodeID} - {EpisodeTitle}", fields: fields, profile: p, source: URL(fileURLWithPath: "/private/tmp/a.mkv"), folder: false), "My Show - s01e02 - The Elf")
        rules.lowercaseEpisodeTitle = true; p.rules = rules
        XCTAssertEqual(Names.clean("Show S01E02 The Elf", p), "show - s01e02 - the elf")
        XCTAssertEqual(Names.clean("Non TV Name", p), "Non Tv Name")
        rules.episodeCapitalization = .uppercase; p.rules = rules
        XCTAssertEqual(Names.clean("Show s01e02 The Elf", p), "show - S01E02 - the elf")
        rules.episodeCapitalization = .keep; p.rules = rules
        XCTAssertEqual(Names.clean("Show s01E02 The Elf", p), "show - s01E02 - the elf")
        rules.formatEpisodes = false; rules.lowercaseEpisodeTitle = false; p.rules = rules
        XCTAssertEqual(Names.clean("Show s1e2 The Elf", p), "Show s1e2 The Elf")
        rules.episodeCapitalization = .lowercase; p.rules = rules
        XCTAssertEqual(Names.clean("Show S01E02 The Elf", p), "Show s01e02 The Elf")
        for kind in [Kind.music, .audiobook] {
            var audio = Profile(kind); audio.rules = rules
            XCTAssertEqual(Names.clean("Show S01E02 The Elf", audio), "Show s01e02 The Elf")
        }
        for kind in [Kind.documents, .other] {
            var plain = Profile(kind); plain.titleCase = false; plain.rules = rules
            XCTAssertEqual(Names.clean("Show S01E02 The Elf", plain), "Show S01E02 The Elf")
        }
        p.exceptions = "DJ, BT-AI"
        XCTAssertEqual(Names.clean("dj bt-ai S01E02", p), "DJ BT-AI s01e02")

    }
    func testArtistBuckets() throws {
        var music = Profile(.music)
        XCTAssertEqual(RuleEngine.bucket(artist: "Northbound", profile: music), "N")
        XCTAssertEqual(RuleEngine.bucket(artist: "2 Example", profile: music), "0-9")
        XCTAssertEqual(RuleEngine.bucket(artist: "#Band", profile: music), "#")
        XCTAssertEqual(RuleEngine.bucket(artist: "Élan", profile: music), "E")
        var rules = music.rules; rules.ignoreLeadingThe = true; music.rules = rules
        XCTAssertEqual(RuleEngine.bucket(artist: "The Northbound", profile: music), "N")
        var fields = Fields(); fields.artist = "The Northbound"
        XCTAssertEqual(try Names.render("{Bucket}/{Artist}", fields: fields, profile: music, source: src.appendingPathComponent("a.mp3"), folder: true), "N/The Northbound")
    }
    func testManualOverrideAndCorrectionJournal() throws {
        let i = try item("original.pdf"); var edited = i; edited.overrideBasename = "Exact MANUAL name"; edited.rememberCorrection = true
        let q = try plan([edited]); XCTAssertTrue(q.rows[0].destination.hasSuffix("Exact MANUAL name.pdf"))
        let e = try executor(); XCTAssertEqual(try e.execute(q).completed, 1)
        let examples = Learning.observations(events: try e.journal.events()); XCTAssertEqual(examples.count, 1); XCTAssertTrue(examples[0].remember)
        XCTAssertEqual(examples[0].original, "original.pdf"); XCTAssertEqual(examples[0].final, "Exact MANUAL name.pdf")
        XCTAssertEqual(Learning.observations(events: try e.journal.events(), forgotten: [examples[0].id.uuidString]).count, 0)
        let event = try XCTUnwrap(e.journal.events().first { $0.state == "Copied" }); try e.undo(event, allowDeleteCopy: true)
        XCTAssertEqual(Learning.observations(events: try e.journal.events()).count, 0)
        edited.overrideBasename = "../escape"; XCTAssertFalse(try plan([edited]).rows[0].actionable)
    }
    func testCaseOnlyRenameUndoAndInterruptedRecovery() throws {
        var edited = try item("report.pdf"); edited.overrideBasename = "REPORT"
        let q = try makePlan(items: [edited], profile: p, mode: .clean, category: "", fileOnly: false)
        XCTAssertTrue(q.rows[0].actionable); XCTAssertEqual(q.rows[0].caseOnly, true)
        let e = try executor(); let bytes = try Data(contentsOf: edited.url)
        XCTAssertEqual(try e.execute(q).completed, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: src.path).contains("REPORT.pdf"))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: q.rows[0].destination)), bytes)
        let event = try XCTUnwrap(e.journal.events().first { $0.state == "Moved" }); try e.undo(event, allowDeleteCopy: false)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: src.path).contains("report.pdf"))
        let second = try makePlan(items: [edited], profile: p, mode: .clean, category: "", fileOnly: false)
        XCTAssertEqual(try e.execute(second, fault: .afterCaseStage).failed, 1)
        let reopened = try Journal(url: base.appendingPathComponent("journal.sqlite"))
        let recovery = try XCTUnwrap(reopened.events().first { $0.operation == second.id && $0.temporary != nil }?.temporary)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: recovery)), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: edited.url.path))
        let staged = try XCTUnwrap(reopened.events().first { $0.operation == second.id && $0.state == "Case rename staged" })
        try e.recoverCaseStage(staged)
        XCTAssertEqual(try Data(contentsOf: edited.url), bytes)
    }
    func testFolderCleanUndoAndStaleContents() throws {
        var rules = p.rules; rules.folderHyphensToSpaces = true; p.rules = rules
        let folder = src.appendingPathComponent("A - Nice-Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Unchanged-Name.MP3"); try Data("payload".utf8).write(to: file)
        try Data("hidden".utf8).write(to: folder.appendingPathComponent(".hidden"))
        let q = try planFolders(workspace: src, profile: p)
        let row = try XCTUnwrap(q.rows.first); XCTAssertTrue(row.actionable); XCTAssertTrue(row.destination.hasSuffix("A Nice Folder")); XCTAssertEqual(row.members.count, 2)
        let e = try executor(); let folders = FolderExecutor(journal: e.journal)
        XCTAssertEqual(try folders.execute(q, included: [row.id]).completed, 1)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: row.destination).appendingPathComponent("Unchanged-Name.MP3")), Data("payload".utf8))
        let event = try XCTUnwrap(e.journal.folderEvents().first { $0.state == "Renamed folder" }); try folders.undo(event)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        let stale = try planFolders(workspace: src, profile: p); try Data("new".utf8).write(to: file)
        XCTAssertEqual(try folders.execute(stale, included: Set(stale.rows.map(\.id))).failed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
    func testFolderConflictsLinksAndSelection() throws {
        var rules = p.rules; rules.folderHyphensToSpaces = true; p.rules = rules
        for name in ["A-B", "A B", "Linked-Folder", "Not-Selected"] { try FileManager.default.createDirectory(at: src.appendingPathComponent(name), withIntermediateDirectories: true) }
        try FileManager.default.createSymbolicLink(at: src.appendingPathComponent("Linked-Folder/link"), withDestinationURL: src.appendingPathComponent("missing"))
        let q = try planFolders(workspace: src, profile: p)
        XCTAssertFalse(try XCTUnwrap(q.rows.first { $0.source.hasSuffix("A-B") }).actionable)
        XCTAssertFalse(try XCTUnwrap(q.rows.first { $0.source.hasSuffix("Linked-Folder") }).actionable)
        let selected = try planFolders(workspace: src, profile: p, selectedPaths: [src.appendingPathComponent("Not-Selected").path]); XCTAssertEqual(selected.rows.count, 1)
        let token = Cancellation(); token.cancel()
        let result = try FolderExecutor(journal: executor().journal).execute(selected, included: Set(selected.rows.map(\.id)), cancel: token)
        XCTAssertEqual(result.completed, 0); XCTAssertTrue(FileManager.default.fileExists(atPath: src.appendingPathComponent("Not-Selected").path))
    }
    func testMagicOriginalEvidenceAndManualPrecedence() throws {
        var books = Profile(.audiobook); var rules = books.rules; rules.useMagic = true; rules.hyphensToSpaces = true; books.rules = rules
        let url = URL(fileURLWithPath: "/private/tmp/Author_Name - Book_Title - 03.mp3")
        let suggestions = Magic.suggestions(url: url, profile: books)
        XCTAssertEqual(suggestions[0].fields.author, "Author Name"); XCTAssertEqual(suggestions[0].fields.bookTitle, "Book Title"); XCTAssertEqual(suggestions[0].fields.chapterNumber, "03")
        var music = Profile(.music); music.rules = rules
        XCTAssertFalse(Magic.suggestions(url: url, profile: music).contains { !$0.fields.author.isEmpty })
        var input = Item(url: url, size: 1, fields: Fields(), evidence: "", reviewed: false); input.overrideBasename = "Do Not Replace"
        XCTAssertEqual(Magic.prepare([input], profile: books, memories: [])[0].overrideBasename, "Do Not Replace")
        let unknown = Magic.suggestions(url: URL(fileURLWithPath: "/private/tmp/chapter.mp3"), profile: books)
        XCTAssertTrue(unknown.allSatisfy { $0.fields.author.isEmpty && $0.fields.bookTitle.isEmpty })
        var video = Profile(.video); video.rules = rules; video.removeTokens = "2024"
        XCTAssertEqual(Magic.suggestions(url: URL(fileURLWithPath: "/private/tmp/The.Example.Film.2024.mkv"), profile: video)[0].fields.year, "2024")
    }
    func testMagicSelectionEvidenceAndRememberedIsolation() throws {
        var books = Profile(.audiobook); var rules = books.rules; rules.useMagic = true; books.rules = rules
        var known = Item(url: src.appendingPathComponent("01 - Start.mp3"), size: 1, fields: Fields(), evidence: "", reviewed: true)
        known.fields.author = "Mira Vale"; known.fields.bookTitle = "The Harbor"
        let url = src.appendingPathComponent("02 - Next.mp3")
        let proposals = Magic.suggestions(url: url, profile: books, related: [known])
        XCTAssertTrue(proposals.contains { $0.fields.author == "Mira Vale" && $0.fields.bookTitle == "The Harbor" })
        let correction = ConfirmedCorrection(profileID: books.id, original: url.lastPathComponent, automatic: "02 - Next.mp3", final: "02 - Approved.mp3", initialFields: Fields(), fields: known.fields, remember: true, settingsSignature: Learning.settingsSignature(books), sourceParentPath: url.deletingLastPathComponent().path)
        XCTAssertEqual(Magic.suggestions(url: url, profile: books, memories: [correction])[0].overrideBasename, "02 - Approved")
        var changed = books; changed.prefix = "NEW "
        XCTAssertFalse(Magic.suggestions(url: url, profile: changed, memories: [correction]).contains { $0.label == "Remembered correction" })
        XCTAssertFalse(Magic.suggestions(url: URL(fileURLWithPath: "/private/tmp/Other Book/02 - Next.mp3"), profile: books, memories: [correction]).contains { $0.label == "Remembered correction" })
        let other = Profile(.audiobook)
        XCTAssertFalse(Magic.suggestions(url: url, profile: other, memories: [correction]).contains { $0.label == "Remembered correction" })
    }
    func testRecommendationsAndAnonymizedReport() throws {
        let a = ConfirmedCorrection(profileID: p.id, original: "a.pdf", automatic: "A.pdf", final: "TAG A.pdf", initialFields: Fields(), fields: Fields(), remember: false)
        let b = ConfirmedCorrection(profileID: p.id, original: "b.pdf", automatic: "B.pdf", final: "TAG B.pdf", initialFields: Fields(), fields: Fields(), remember: false)
        XCTAssertEqual(Learning.recommendations(profile: p, observations: [a], excluded: []).count, 0)
        let recommendations = Learning.recommendations(profile: p, observations: [a, b, a], excluded: ["one.xyz", "two.xyz"])
        let prefix = try XCTUnwrap(recommendations.first { $0.action == "prefix" }); XCTAssertEqual(prefix.examples.count, 2)
        XCTAssertEqual(p.prefix, ""); prefix.apply(to: &p); XCTAssertEqual(p.prefix, "TAG ")
        let ext = try XCTUnwrap(recommendations.first { $0.action == "extension" }); XCTAssertFalse(p.accepted.contains("xyz")); ext.apply(to: &p); XCTAssertTrue(p.accepted.contains("xyz"))
        let report = try XCTUnwrap(recommendations.first { $0.kind == .development })
        let text = report.report(profile: p, anonymize: true); XCTAssertFalse(text.contains("TAG A.pdf")); XCTAssertFalse(text.contains(p.name))
        XCTAssertTrue(report.report(profile: p, anonymize: false).contains("TAG A.pdf"))
    }
    func testProfileMigrationAndCustomNamesUnchanged() throws {
        var old = Profile(.other); old.extensions = "rom"
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any]); json.removeValue(forKey: "preparation")
        let decoded = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertFalse(decoded.rules.useMagic); XCTAssertEqual(Names.clean("Name__-__v1.2 (USA)  Final", decoded), "Name__-__v1.2 (USA)  Final")
        let fields = try JSONDecoder().decode(Fields.self, from: Data("{\"title\":\"Old\"}".utf8)); XCTAssertEqual(fields.title, "Old"); XCTAssertEqual(fields.series, "")
    }

    func testFolderCaseRecoveryAndUndoGuard() throws {
        let folder = src.appendingPathComponent("case-folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("bytes".utf8).write(to: folder.appendingPathComponent("file.txt"))
        var rules = p.rules; rules.replacements = [ReplacementRule(find: "case-folder", replacement: "CASE-FOLDER", target: .folder)]; p.rules = rules
        let q = try planFolders(workspace: src, profile: p)
        let e = try executor(); let executor = FolderExecutor(journal: e.journal)
        let row = try XCTUnwrap(q.rows.first)
        XCTAssertEqual(try executor.execute(q, included: [row.id], faultAfterStage: true).failed, 1)
        let stage = try XCTUnwrap(e.journal.folderEvents().first { $0.state == "Case rename staged" })
        try executor.recoverCaseStage(stage)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: src.path).contains("case-folder"))
        let next = try planFolders(workspace: src, profile: p)
        XCTAssertEqual(try executor.execute(next, included: Set(next.rows.map(\.id))).completed, 1)
        let done = try XCTUnwrap(e.journal.folderEvents().first { $0.state == "Renamed folder" })
        let destination = URL(fileURLWithPath: done.row.destination)
        try Data("externally changed".utf8).write(to: destination.appendingPathComponent("file.txt"))
        XCTAssertThrowsError(try executor.undo(done))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }
    func testConflictingMagicGroupsAndMissingFields() throws {
        var books = Profile(.audiobook); var rules = books.rules; rules.useMagic = true; books.rules = rules
        var first = Item(url: src.appendingPathComponent("01 - One.mp3"), size: 1, fields: Fields(), evidence: "", reviewed: true)
        first.fields.author = "Author One"; first.fields.bookTitle = "Book One"
        var second = first; second.url = src.appendingPathComponent("02 - Two.mp3"); second.fields.bookTitle = "Book Two"
        let alternatives = Magic.suggestions(url: src.appendingPathComponent("03 - Three.mp3"), profile: books, related: [first, second])
        XCTAssertEqual(alternatives[0].confidence, "Needs review"); XCTAssertTrue(alternatives[0].fields.author.isEmpty)
        XCTAssertTrue(alternatives.contains { $0.fields.bookTitle == "Book One" }); XCTAssertTrue(alternatives.contains { $0.fields.bookTitle == "Book Two" })
        let authorBookChapter = Magic.suggestions(url: src.appendingPathComponent("Author - Book - 03.mp3"), profile: books)
        XCTAssertTrue(authorBookChapter[0].fields.chapterTitle.isEmpty)
        var fields = Fields(); fields.season = "invalid"; fields.episode = "3"
        XCTAssertThrowsError(try Names.render("{EpisodeID}", fields: fields, profile: books, source: first.url, folder: false))
        fields.year = "2024"
        XCTAssertThrowsError(try Names.render("{TitleYear}", fields: fields, profile: books, source: first.url, folder: false))
    }
    func testDirectRenameAndUndoIndependentOfComponents() throws {
        var video = Profile(.video); video.filenameMask = "{Title}"; video.root = "/missing-library"
        var file = try item("original.mp4"); file.reviewed = false
        file.overrideBasename = "Manual Name"
        let plan = try makeDirectRenamePlan(items: [file], profile: video)
        XCTAssertFalse(file.reviewed)
        XCTAssertEqual(plan.mode, .clean)
        XCTAssertEqual(plan.rows[0].destination, src.appendingPathComponent("Manual Name.mp4").path)
        let journal = try Journal(url: base.appendingPathComponent("direct.sqlite"))
        let executor = Executor(journal: journal)
        XCTAssertEqual(try executor.execute(plan).completed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: plan.rows[0].destination))
        let event = try XCTUnwrap(journal.events().first { $0.state == "Moved" })
        try executor.undo(event, allowDeleteCopy: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.rows[0].destination))
    }
    func testDirectRenameNoopCollisionAndStaleUndo() throws {
        var file = try item("original.pdf"); file.reviewed = false; file.overrideBasename = "original"
        XCTAssertThrowsError(try makeDirectRenamePlan(items: [file], profile: p))
        file.overrideBasename = "Taken"
        try Data("occupied".utf8).write(to: src.appendingPathComponent("Taken.pdf"))
        let blocked = try makeDirectRenamePlan(items: [file], profile: p)
        XCTAssertFalse(blocked.rows[0].actionable)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        file.overrideBasename = "../bad"
        XCTAssertThrowsError(try makeDirectRenamePlan(items: [file], profile: p))
        file.overrideBasename = "new"
        let plan = try makeDirectRenamePlan(items: [file], profile: p)
        let journal = try Journal(url: base.appendingPathComponent("direct.sqlite"))
        let executor = Executor(journal: journal)
        XCTAssertEqual(try executor.execute(plan).completed, 1)
        let event = try XCTUnwrap(journal.events().first { $0.state == "Moved" })
        try Data("externally changed".utf8).write(to: URL(fileURLWithPath: event.row.destination))
        XCTAssertThrowsError(try executor.undo(event, allowDeleteCopy: false))
        XCTAssertTrue(FileManager.default.fileExists(atPath: event.row.destination))
    }
    func testDirectCaseOnlyRenameAndUndo() throws {
        var file = try item("name.pdf"); file.reviewed = false; file.overrideBasename = "NAME"
        let plan = try makeDirectRenamePlan(items: [file], profile: p)
        XCTAssertTrue(plan.rows[0].caseOnly == true)
        let journal = try Journal(url: base.appendingPathComponent("direct.sqlite"))
        let executor = Executor(journal: journal)
        XCTAssertEqual(try executor.execute(plan).completed, 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: src.path).contains("NAME.pdf"))
        try executor.undo(try XCTUnwrap(journal.events().first { $0.state == "Moved" }), allowDeleteCopy: false)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: src.path).contains("name.pdf"))
    }
    func testFilenameDifferenceDisplay() throws {
        let casing = FilenameDifference(source: "EVEROS.mp4", proposed: "Everos.mp4")
        XCTAssertEqual(casing.summary, "Capitalization changed")
        XCTAssertEqual(casing.removed.count, 5); XCTAssertEqual(casing.inserted.count, 5)
        let spaces = FilenameDifference(source: "A  B.mp4", proposed: "A B.mp4")
        XCTAssertEqual(spaces.removed.count, 1); XCTAssertTrue(spaces.inserted.isEmpty)
        XCTAssertTrue(spaces.summary.contains("Removed 1 whitespace"))
        let insert = FilenameDifference(source: "AB.mp4", proposed: "A B.mp4")
        XCTAssertEqual(insert.inserted, Set([1])); XCTAssertTrue(insert.removed.isEmpty)
        XCTAssertFalse(FilenameDifference(source: "same", proposed: "same").changed)
        let unicode = FilenameDifference(source: "Elf 🧝 Name", proposed: "Elf 🧝 New Name")
        XCTAssertTrue(unicode.changed); XCTAssertTrue(unicode.removed.isEmpty)
        let long = FilenameDifference(source: String(repeating: "a", count: 1000), proposed: String(repeating: "a", count: 999) + "b")
        XCTAssertEqual(long.removed, Set([999])); XCTAssertEqual(long.inserted, Set([999]))
    }
    func testEpisodeRepairOrderAndTriggeredRules() throws {
        var profile = Profile(.video)
        var rules = profile.rules; rules.hyphensToSpaces = true; rules.formatEpisodes = true
        rules.episodeCapitalization = .lowercase; profile.rules = rules
        var triggered: [String] = []
        let result = Names.clean("Show - s01e 10 - CLAUDIO", profile) { triggered.append($0) }
        XCTAssertEqual(result, "Show - s01e10 - Claudio")
        XCTAssertEqual(triggered.first, "Episode spacing repair")
        XCTAssertTrue(triggered.contains("Hyphens to spaces"))
        XCTAssertTrue(triggered.contains("Title case"))
        XCTAssertTrue(triggered.contains("Episode separator formatting"))
        XCTAssertFalse(triggered.contains("Underscores to spaces"))
        XCTAssertFalse(triggered.contains("Shared spelling exceptions"))
        XCTAssertEqual(RuleEngine.normalizeEpisodeSpacing("Show s 01 e 10 Pilot"), "Show s01e10 Pilot")
        XCTAssertEqual(RuleEngine.normalizeEpisodeSpacing("Show season 1 episode 10"), "Show season 1 episode 10")
        XCTAssertEqual(RuleEngine.normalizeEpisodeSpacing("Show s01e1 0 Pilot"), "Show s01e1 0 Pilot")
        var document = Profile(.documents); document.titleCase = false
        XCTAssertEqual(Names.clean("s01e 10", document), "s01e 10")
        triggered = []
        rules.hyphensToSpaces = false; rules.formatEpisodes = false; profile.rules = rules
        XCTAssertEqual(Names.clean("Show S01E10 Pilot", profile) { triggered.append($0) }, "Show s01e10 Pilot")
        XCTAssertTrue(triggered.contains("Episode capitalization"))
        XCTAssertFalse(triggered.contains("Episode spacing repair"))
        var file = try item("Show - s01e 10 - CLAUDIO.pdf")
        profile.extensions = "pdf"; rules.hyphensToSpaces = true; rules.formatEpisodes = true; profile.rules = rules
        let scanned = try scan(src, profile: profile, recursive: false)
        file = try XCTUnwrap(scanned.items.first)
        XCTAssertTrue(file.rulesTriggered.contains("Episode spacing repair"))
    }
    func testWhitespaceDisplayLabelsAndPreferredCase() throws {
        let diff = FilenameDifference(source: "A   B\tC", proposed: "A B C")
        let sourceParts = diff.displayParts(sourceSide: true, markWhitespace: true)
        XCTAssertTrue(sourceParts.contains { $0.text == "[[SPACES × 2]]" })
        XCTAssertTrue(sourceParts.contains { $0.text == "[[TAB]]" })
        XCTAssertEqual(diff.displayParts(sourceSide: true, markWhitespace: false).map(\.text).joined(), "A   B\tC")
        XCTAssertTrue(diff.displayParts(sourceSide: false, markWhitespace: true).contains { $0.text == "[[SPACE]]" })
        let collision = FilenameDifference(source: "Literal [[SPACE]] [[SPACES]] [[SPACES × 2]] [[TAB]]", proposed: "New [[SPACE]]")
        XCTAssertEqual(collision.literalWhitespaceLabels.count, 4)
        XCTAssertTrue(FilenameDifference(source: "ordinary", proposed: "Ordinary").literalWhitespaceLabels.isEmpty)
        let casing = FilenameDifference(source: "Show S01E09 - EVEROS", proposed: "Show s01e09 - Everos")
        XCTAssertEqual(casing.preferredCaseDescription(at: 18, sourceSide: true), "Corrected preferred case: EVEROS → Everos")
        XCTAssertEqual(casing.preferredCaseDescription(at: 16, sourceSide: false), "Corrected preferred case: EVEROS → Everos")
        let replaced = FilenameDifference(source: "Alpha", proposed: "Beta")
        XCTAssertTrue(replaced.preferredCaseDescription(at: 1, sourceSide: true) == nil)
    }
    func testUniversalPreferencesAndRemovalPrecedence() throws {
        var prefs = UniversalPreferences(existingExceptions: "AiDEN, BT-AI")
        prefs.groups["abbreviations"] = "DJ\nAI, DJ"
        prefs.groups["formats"] = "1080p, HDR"
        XCTAssertEqual(prefs.combinedEntries.filter { $0 == "DJ" }.count, 1)
        XCTAssertTrue(prefs.combinedEntries.contains("AiDEN"))
        XCTAssertEqual(prefs.overlaps(removableLabels: "1080P, WEB-DL"), ["1080p"])
        try prefs.validate()
        let roundtrip = try JSONDecoder().decode(UniversalPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(roundtrip, prefs)
        prefs.groups["other"] = "AiDEN, BT-AI, ai"
        XCTAssertFalse(prefs.conflicts.isEmpty)
        XCTAssertThrowsError(try prefs.validate())
        prefs.groups["other"] = "AiDEN, BT-AI"
        prefs.lowercaseTitleWords = "a, THE\nof, the"
        XCTAssertEqual(prefs.titleWords, "a, the, of")
        for kind in [Kind.video, .music, .documents, .other] {
            var profile = Profile(kind); profile.titleCase = true; profile.normalizeSpaces = true; profile.exceptions = prefs.combined
            profile.removeTokens = "1080p"
            var rules = profile.rules; rules.smartTitleCase = true; rules.smallWords = prefs.titleWords; profile.rules = rules
            var trace: [String] = []
            XCTAssertEqual(Names.clean("dj and the elf 1080P", profile) { trace.append($0) }, "DJ And the Elf")
            XCTAssertTrue(trace.contains("Removable labels"))
            profile.removeTokens = ""
            XCTAssertEqual(Names.clean("dj 1080P", profile), "DJ 1080p")
        }
    }
    func testEpisodeComponentHoverDescriptions() throws {
        let diff = FilenameDifference(source: "Show S01 E10 Pilot", proposed: "Show s01e10 Pilot")
        let sourceHelp = try XCTUnwrap(diff.episodeChangeDescription(at: 5, sourceSide: true))
        XCTAssertTrue(sourceHelp.contains("Corrected preferred case for episode component"))
        XCTAssertTrue(sourceHelp.contains("Corrected spacing in episode component"))
        let proposedHelp = try XCTUnwrap(diff.episodeChangeDescription(at: 8, sourceSide: false))
        XCTAssertEqual(sourceHelp, proposedHelp)
        let spacing = FilenameDifference(source: "s01e 10", proposed: "s01e10")
        let help = try XCTUnwrap(spacing.episodeChangeDescription(at: 4, sourceSide: true))
        XCTAssertTrue(help.contains("spacing")); XCTAssertFalse(help.contains("preferred case"))
        XCTAssertTrue(FilenameDifference(source: "s01e10", proposed: "s01e11").episodeChangeDescription(at: 0, sourceSide: true) == nil)
        let padding = FilenameDifference(source: "S1E2", proposed: "S01E02")
        XCTAssertTrue(try XCTUnwrap(padding.episodeChangeDescription(at: 1, sourceSide: true)).contains("padding"))
    }
    func testFilenameSpellingCandidates() throws {
        let words = FilenameSpelling.candidates(in: "VNV NATION AiDEN s01e 10 1080p 2026 U2 qzxwrong hello", exceptions: ["VNV Nation", "aiden"])
        XCTAssertEqual(words.map(\.word), ["qzxwrong", "hello"])
        let boundary = FilenameSpelling.candidates(in: "AiDEN AiDENextra", exceptions: ["aiden"])
        XCTAssertEqual(boundary.map(\.word), ["AiDENextra"])
        XCTAssertTrue(FilenameSpelling.candidates(in: "ac - dc", exceptions: ["AC-DC"]).isEmpty)
        XCTAssertEqual(FilenameSpelling.candidates(in: "bac - dc", exceptions: ["AC-DC"]).map(\.word), ["bac", "dc"])
        let unicode = "🧝 Café Typppo"
        let candidates = FilenameSpelling.candidates(in: unicode, exceptions: [])
        XCTAssertEqual(candidates.map(\.word), ["Café", "Typppo"])
        XCTAssertEqual(candidates.last?.characterIndices, Set(7..<13))
        XCTAssertTrue(FilenameSpelling.candidates(in: "12345 S01E02 1080p", exceptions: []).isEmpty)
        var preferences = UniversalPreferences(); preferences.flagUnrecognizedWords = false
        let encoded = try JSONEncoder().encode(preferences)
        XCTAssertEqual(try JSONDecoder().decode(UniversalPreferences.self, from: encoded).flagUnrecognizedWords, false)
    }
    func testConfigurablePatternsAndRouting() throws {
        var video = ProfileSetup.configured(.video, name: "Video")
        video.titleCase = false
        var rules = video.rules; rules.episodeCapitalization = .lowercase; video.rules = rules
        try video.validate()
        let tvURL = src.appendingPathComponent("My Best Life - s01e02 - Moving Day.mp4")
        let tv = Names.basicInterpret(tvURL, video)
        XCTAssertEqual(tv.0.type, "TV Show"); XCTAssertEqual(tv.0.series, "My Best Life"); XCTAssertEqual(tv.0.title, "")
        XCTAssertEqual(try Names.render(PatternEngine.folderMask(for: tv.0, profile: video), fields: tv.0, profile: video, source: tvURL, folder: true), "TV Shows/My Best Life/Season 01")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Movie (1999).mp4"), video).0.type, "Movie")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Movie Without Year.mp4"), video).0.type, "Movie")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Commercial - Weekend Sale.mp4"), video).0.type, "Commercial")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Documentary - Oceans.mp4"), video).0.type, "Documentary")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Sale [Commercial].mp4"), video).0.type, "Commercial")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Sale [TV].mp4"), video).0.type, "TV Show")
        let unknown = Names.basicInterpret(src.appendingPathComponent("Sale [Unregistered].mp4"), video)
        XCTAssertTrue(unknown.1.contains("Unrecognized")); XCTAssertThrowsError(try PatternEngine.validateClassification(unknown.0, profile: video))
        video.workspacePatterns = [WorkspacePattern("{Title}", type: "Movie"), WorkspacePattern("{Title} [Commercial]", type: "Commercial")]
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Sale [Commercial].mp4"), video).0.type, "Movie")
        video.workspacePatterns?[0].enabled = false
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Sale [Commercial].mp4"), video).0.type, "Commercial")
        video.classifications?[3].filenameMask = "Ad - {Title}"
        let f = Names.basicInterpret(src.appendingPathComponent("Sale [Commercial].mp4"), video).0
        XCTAssertEqual(try proposedFilename(Item(url: tvURL, size: 0, fields: f, evidence: "", reviewed: false), profile: video), "Ad - Sale.mp4")
    }
    func testPatternLiteralsValidationAndCustomFields() throws {
        let defaults = ProfileSetup.configured(.video, name: "Video")
        var untitledYear = Fields(); untitledYear.title = "Movie"
        XCTAssertEqual(try Names.render(defaults.folderMask, fields: untitledYear, profile: defaults, source: src, folder: true), "Movie")
        XCTAssertEqual(try Names.render(defaults.filenameMask, fields: untitledYear, profile: defaults, source: src, folder: false), "Movie")
        untitledYear.resolution = "720p"
        XCTAssertEqual(try Names.render(defaults.filenameMask, fields: untitledYear, profile: defaults, source: src, folder: false), "Movie [720p]")
        untitledYear.year = "1999"
        XCTAssertEqual(try Names.render(defaults.filenameMask, fields: untitledYear, profile: defaults, source: src, folder: false), "Movie (1999) [720p]")
        XCTAssertTrue(defaults.rules.hyphensToSpaces); XCTAssertTrue(defaults.rules.smartTitleCase); XCTAssertTrue(defaults.rules.formatEpisodes)
        XCTAssertEqual(defaults.removeTokens, "")
        for kind in Kind.allCases {
            var profile = ProfileSetup.configured(kind, name: kind.label)
            if kind == .other { profile.extensions = "txt" }
            XCTAssertFalse(profile.replaceDots && profile.rules.dotsToDashes)
            XCTAssertFalse(profile.rules.useMagic)
            if [.video, .music, .audiobook].contains(kind) { XCTAssertTrue(profile.rules.smartTitleCase) }
            try profile.validate()
        }
        var conflict = defaults; var conflictRules = conflict.rules; conflictRules.dotsToDashes = true; conflict.rules = conflictRules
        XCTAssertThrowsError(try conflict.validate())
        conflict.replaceDots = false; try conflict.validate()
        for original in ["s01e10 - My Series - Claudio", "My Series - s01e10 - Claudio", "My Series - Claudio - s01e10"] {
            let url = src.appendingPathComponent(original + ".mp4")
            let f = Names.basicInterpret(url, defaults).0
            XCTAssertEqual(f.season, "01"); XCTAssertEqual(f.episode, "10")
            XCTAssertEqual(f.series, "My Series"); XCTAssertEqual(f.episodeTitle, "Claudio"); XCTAssertEqual(f.type, "TV Show")
            XCTAssertEqual(Magic.suggestions(url: url, profile: defaults).first?.fields, f)
        }
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Series - s01e01 - s01e02.mp4"), defaults).0.season, "")
        let unstructured = Names.basicInterpret(src.appendingPathComponent("Unclear s02e03 text.mp4"), defaults).0
        XCTAssertEqual(unstructured.season, "02"); XCTAssertEqual(unstructured.episode, "03"); XCTAssertEqual(unstructured.series, "")
        for original in ["(1999) - My Favorite Movie", "(1999) My Favorite Movie", "1999 - My Favorite Movie", "My Favorite (1999) Movie"] {
            let f = Names.basicInterpret(src.appendingPathComponent(original + ".mp4"), defaults).0
            XCTAssertEqual(f.year, "1999"); XCTAssertEqual(f.title, "My Favorite Movie")
        }
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("1999 My Favorite Movie.mp4"), defaults).0.year, "")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Film (1999) (2000).mp4"), defaults).0.year, "")
        var previous = defaults
        previous.folderMask = "{TitleYear}"; previous.filenameMask = "{TitleYear}"
        previous.workspacePatterns = defaults.workspacePatterns?.filter { !$0.pattern.contains("{Resolution}") && !["{EpisodeID} - {Series} - {EpisodeTitle}", "{Series} - {EpisodeTitle} - {EpisodeID}", "{EpisodeIDAnywhere}", "({Year}) - {Title}", "({Year}) {Title}", "{Year} - {Title}", "{ParenthesizedYearAnywhere}"].contains($0.pattern) }
        let upgraded = ProfileSetup.updatingVideoDefaults(previous)
        XCTAssertEqual(upgraded.workspacePatterns?.count, defaults.workspacePatterns?.count)
        XCTAssertEqual(upgraded.filenameMask, "{Title} ({Year?}) [{Resolution?}]")
        XCTAssertEqual(ProfileSetup.updatingVideoDefaults(upgraded), upgraded)
        for original in ["Kingdom of Heaven (Extended Version) 2005 1280p.mp4", "Kingdom of Heaven (Extended Version) (2005) [1280P].mp4"] {
            let url = src.appendingPathComponent(original)
            let fields = Names.basicInterpret(url, defaults).0
            XCTAssertEqual(fields.year, "2005"); XCTAssertEqual(fields.resolution, "1280p")
            XCTAssertEqual(fields.type, "Movie")
            XCTAssertEqual(Magic.suggestions(url: url, profile: defaults).first?.fields, fields)
            XCTAssertTrue(try Names.render(PatternEngine.filenameMask(for: fields, profile: defaults), fields: fields, profile: defaults, source: url, folder: false).hasSuffix("(2005) [1280p]"))
        }
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("2001 A Space Odyssey.mp4"), defaults).0.year, "")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Film (2100).mp4"), defaults).0.year, "2100")
        let missing = Names.basicInterpret(src.appendingPathComponent("Film (2005).mp4"), defaults).0
        XCTAssertEqual(try Names.render(defaults.filenameMask, fields: missing, profile: defaults, source: src, folder: false), "Film (2005)")
        XCTAssertThrowsError(try Names.render("{Title} ({Year}) [{Resolution}]", fields: missing, profile: defaults, source: src, folder: false))
        var requiredDefault = defaults
        requiredDefault.filenameMask = "{Title} ({Year}) [{Resolution}]"
        requiredDefault.classifications?[0].filenameMask = requiredDefault.filenameMask
        let optionalDefault = ProfileSetup.updatingVideoDefaults(requiredDefault)
        XCTAssertEqual(optionalDefault.filenameMask, "{Title} ({Year?}) [{Resolution?}]")
        XCTAssertEqual(optionalDefault.classifications?[0].filenameMask, "{Title} ({Year?}) [{Resolution?}]")
        var custom = defaults; custom.filenameMask = "{Title}, {Year}"; custom.folderMask = "{Title}"
        XCTAssertEqual(ProfileSetup.updatingVideoDefaults(custom).filenameMask, custom.filenameMask)
        XCTAssertEqual(ProfileSetup.updatingVideoDefaults(custom).folderMask, custom.folderMask)
        var video = ProfileSetup.configured(.video, name: "Video")
        video.workspacePatterns = [WorkspacePattern("{Title} {Year} {Resolution}", type: "Movie")]
        video.filenameMask = "{TitleYear} [{Resolution?}]"
        let movieURL = src.appendingPathComponent("Kong of Hell 2005 720P.mp4")
        var movieFields = Names.basicInterpret(movieURL, video).0
        XCTAssertEqual(movieFields.resolution, "720p")
        XCTAssertEqual(try Names.render(video.filenameMask, fields: movieFields, profile: video, source: movieURL, folder: false), "Kong of Hell (2005) [720p]")
        movieFields.resolution = ""
        XCTAssertEqual(try Names.render(video.filenameMask, fields: movieFields, profile: video, source: movieURL, folder: false), "Kong of Hell (2005)")
        let oldFields = try JSONDecoder().decode(Fields.self, from: Data(#"{"title":"Movie","custom":{"Resolution":"1080P"}}"#.utf8))
        XCTAssertEqual(oldFields.resolution, "1080p")
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: Data(#"{"title":"Movie"}"#.utf8)).resolution, "")
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: JSONEncoder().encode(oldFields)).resolution, "1080p")
        var p = ProfileSetup.configured(.other, name: "Custom")
        p.workspacePatterns = [WorkspacePattern("Item - {Collection} [{Title}]")]
        let url = src.appendingPathComponent("Item - Archive [Original].PDF")
        let f = Names.basicInterpret(url, p).0
        XCTAssertEqual(f.custom?["Collection"], "Archive")
        p.folderMask = "{Collection}"; p.filenameMask = "{Title}"
        XCTAssertEqual(try Names.render(p.folderMask, fields: f, profile: p, source: url, folder: true), "Archive")
        XCTAssertEqual(try proposedFilename(Item(url: url, size: 0, fields: f, evidence: "", reviewed: false), profile: p), "Original.PDF")
        p.workspacePatterns = [WorkspacePattern("{Title} ({Year})")]
        XCTAssertTrue(Names.basicInterpret(src.appendingPathComponent("Name (Year).pdf"), p).1.contains("No enabled"))
        p.workspacePatterns = [WorkspacePattern("{Title} {Title}")]; XCTAssertThrowsError(try PatternEngine.validate(p))
        p.workspacePatterns = [WorkspacePattern("{Title} [{Type}]", type: "@capture")]; p.classificationComponent = "System"
        XCTAssertThrowsError(try PatternEngine.validate(p))
        p.workspacePatterns = []; p.folderMask = "../Escape"; XCTAssertThrowsError(try PatternEngine.validate(p))
    }
    func testRomsForgeAndOtherContentDefaults() throws {
        let starters = ProfileSetup.starterProfiles
        XCTAssertEqual(starters.count, 9)
        XCTAssertEqual(Set(starters.map(\.name)).count, 9)
        for profile in starters { try profile.validate() }
        let roms = try XCTUnwrap(starters.first { $0.kind == .roms })
        let f = Names.basicInterpret(src.appendingPathComponent("My Game [SFC].sfc"), roms).0
        XCTAssertEqual(f.system, "SNES"); XCTAssertEqual(f.title, "My Game")
        XCTAssertEqual(try Names.render(roms.folderMask, fields: f, profile: roms, source: src, folder: true), "SNES")
        let forge = try XCTUnwrap(starters.first { $0.name == "FORGE" })
        let url = src.appendingPathComponent("Traveller - Sector Map.pdf")
        let resource = Names.basicInterpret(url, forge).0
        XCTAssertEqual(resource.game, "Traveller"); XCTAssertEqual(resource.title, "Sector Map")
        XCTAssertEqual(try proposedFilename(Item(url: url, size: 0, fields: resource, evidence: "", reviewed: false), profile: forge), url.lastPathComponent)
        var genreMusic = ProfileSetup.configured(.music, name: "Genres")
        genreMusic.workspacePatterns = [WorkspacePattern("{Artist} - {Title} [{Genre}]", type: "@capture")]
        genreMusic.classifications = [FilingType("Rock", aliases: "Rock Music", folderMask: "{Genre}/{Artist}")]
        let songURL = src.appendingPathComponent("Band - Song [Rock Music].mp3")
        let genre = Names.basicInterpret(songURL, genreMusic).0
        XCTAssertEqual(genre.genre, "Rock")
        XCTAssertEqual(try Names.render(PatternEngine.folderMask(for: genre, profile: genreMusic), fields: genre, profile: genreMusic, source: songURL, folder: true), "Rock/Band")
        let software = try XCTUnwrap(starters.first { $0.kind == .software })
        let install = Names.basicInterpret(src.appendingPathComponent("Player - 1.2.3 [macOS].dmg"), software).0
        XCTAssertEqual(install.product, "Player"); XCTAssertEqual(install.version, "1.2.3"); XCTAssertEqual(install.platform, "macOS")
        let photos = try XCTUnwrap(starters.first { $0.kind == .photos })
        let photo = Names.basicInterpret(src.appendingPathComponent("2026-10-21 - Holiday - Beach.jpg"), photos).0
        XCTAssertEqual(photo.dateTaken, "2026-10-21"); XCTAssertEqual(photo.event, "Holiday")
    }
    func testBookHierarchyAndParentPatterns() throws {
        var audio = try XCTUnwrap(ProfileSetup.starterProfiles.first { $0.name == "Audiobooks" })
        audio.titleCase = false
        let singleURL = src.appendingPathComponent("Full Author - Standalone.m4b")
        let single = Names.basicInterpret(singleURL, audio).0
        XCTAssertEqual(try Names.render(audio.folderMask, fields: single, profile: audio, source: singleURL, folder: true), "Full Author/Standalone")
        let seriesURL = src.appendingPathComponent("Full Author - Great Series - #02 - Book Name.m4b")
        let series = Names.basicInterpret(seriesURL, audio).0
        XCTAssertEqual(series.seriesNumber, "02"); XCTAssertEqual(series.series, "Great Series")
        XCTAssertEqual(try Names.render(audio.folderMask, fields: series, profile: audio, source: seriesURL, folder: true), "Full Author/Great Series/02 - Book Name")
        audio.workspacePatterns?[0].enabled = true
        let chapterURL = src.appendingPathComponent("Full Author/Great Series/02 - Book Name/03 - Chapter Name.mp3")
        let chapter = Names.basicInterpret(chapterURL, audio).0
        XCTAssertEqual(chapter.author, "Full Author"); XCTAssertEqual(chapter.bookTitle, "Book Name"); XCTAssertEqual(chapter.chapterNumber, "03")
        XCTAssertEqual(chapter.chapterTitle, "Chapter Name")
    }
    func testProfileMigrationArchiveAndNotes() throws {
        var legacy = Profile(.music); legacy.notes = "Personal notes\nSecond line"; legacy.fixedCategory = "Rock"; legacy.root = library.path
        legacy.extractionMask = "{Artist} - {Title}"; legacy.bookmark = Data([1, 2, 3])
        let url = src.appendingPathComponent("Artist - Song.mp3")
        let before = Names.basicInterpret(url, legacy)
        let migrated = try ProfileSetup.migrate(legacy)
        XCTAssertEqual(migrated.id, legacy.id); XCTAssertEqual(migrated.notes, legacy.notes)
        XCTAssertEqual(migrated.root, legacy.root); XCTAssertEqual(migrated.bookmark, legacy.bookmark)
        XCTAssertEqual(migrated.folderMask, "Rock/" + legacy.folderMask); XCTAssertEqual(migrated.fixedCategory, "")
        XCTAssertEqual(Names.basicInterpret(url, migrated).0, before.0)
        XCTAssertEqual(try ProfileSetup.migrate(migrated), migrated)
        var notesOnly = migrated; notesOnly.notes = "Changed description"
        XCTAssertEqual(Learning.settingsSignature(notesOnly), Learning.settingsSignature(migrated))
        XCTAssertTrue((migrated.workspacePatterns?.count ?? 0) > 1)
        XCTAssertTrue(migrated.workspacePatterns?.dropFirst().allSatisfy { !$0.enabled } == true)
        let archive = SettingsArchive(profiles: [legacy], general: .suggestedDefaults, activeProfileID: legacy.id)
        let restored = try JSONDecoder().decode(SettingsArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(try restored.validatedProfiles()[0], migrated)
        var duplicate = archive; duplicate.profiles.append(legacy); XCTAssertThrowsError(try duplicate.validatedProfiles())
        let f = try JSONDecoder().decode(Fields.self, from: Data(#"{"title":"Old"}"#.utf8))
        XCTAssertEqual(f.type, ""); XCTAssertEqual(f.system, ""); XCTAssertEqual(f.custom, nil)
    }
    func testVideoCategoryCompatibilityAndPersistence() throws {
        var legacy = ProfileSetup.configured(.video, name: "Existing Videos")
        legacy.root = library.path; legacy.mediaRoutingEnabled = true; legacy.classifications = []
        legacy.mediaCategories![1].rootFolder = "Nonfiction"
        legacy.mediaCategories![3].rootFolder = "My Films"
        legacy.mediaCategories![5].rootFolder = "Television"
        legacy.defaultMediaCategoryID = legacy.mediaCategories![3].id
        let repaired = ProfileSetup.addingMissingVideoTypes(legacy)
        try repaired.validate()
        XCTAssertEqual(repaired.mediaCategories, legacy.mediaCategories)
        XCTAssertEqual(repaired.defaultMediaCategoryID, legacy.defaultMediaCategoryID)
        XCTAssertEqual(repaired.workspacePatterns, legacy.workspacePatterns)
        XCTAssertEqual(repaired.folderMask, legacy.folderMask)
        XCTAssertEqual(repaired.filenameMask, legacy.filenameMask)
        XCTAssertEqual(repaired.id, legacy.id)
        XCTAssertEqual(ProfileSetup.addingMissingVideoTypes(repaired), repaired)
        XCTAssertTrue(PatternEngine.lookup("Commercial", profile: repaired) != nil)
        XCTAssertEqual(PatternEngine.lookup("Commercial", profile: repaired)?.folderMask, nil)
        let file = base.appendingPathComponent("Saved profiles.json")
        try ProfileSettingsStore.write([repaired], to: file)
        let reopened = try ProfileSettingsStore.read(from: file)
        XCTAssertEqual(reopened, [repaired])
        XCTAssertEqual(try ProfileSettingsStore.read(from: file)[0].mediaCategories?[3].rootFolder, "My Films")
        var edited = reopened[0]; edited.mediaCategories![3].rootFolder = "Films - Updated"
        try ProfileSettingsStore.write([edited], to: file)
        XCTAssertEqual(try ProfileSettingsStore.read(from: file)[0].mediaCategories?[3].rootFolder, "Films - Updated")
        let before = try Data(contentsOf: file)
        let blocked = base.appendingPathComponent("Blocked Save.json")
        try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: blocked.appendingPathComponent("sentinel"))
        XCTAssertThrowsError(try ProfileSettingsStore.write([legacy], to: blocked))
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try Data(contentsOf: blocked.appendingPathComponent("sentinel")), Data("keep".utf8))
        let bad = base.appendingPathComponent("Unreadable format.json"); try Data("broken JSON".utf8).write(to: bad)
        XCTAssertThrowsError(try ProfileSettingsStore.read(from: bad))
        XCTAssertEqual(try Data(contentsOf: bad), Data("broken JSON".utf8))
        var custom = legacy
        let films = FilingType("Films", aliases: "Movies", folderMask: "Special/{Title}", filenameMask: "Custom - {Title}")
        custom.classifications = [films]
        let compatible = ProfileSetup.addingMissingVideoTypes(custom)
        try compatible.validate()
        XCTAssertEqual(PatternEngine.lookup("Movie", profile: compatible)?.id, films.id)
        XCTAssertEqual(PatternEngine.lookup("Movie", profile: compatible)?.folderMask, films.folderMask)
        XCTAssertEqual(PatternEngine.lookup("Movie", profile: compatible)?.filenameMask, films.filenameMask)
        var renamed = repaired
        let movieIndex = renamed.classifications!.firstIndex { $0.name == "Movie" }!
        renamed.classifications![movieIndex].name = "Personal Layout"; renamed.classifications![movieIndex].aliases = ""
        let renamedRepair = ProfileSetup.addingMissingVideoTypes(renamed)
        try renamedRepair.validate()
        XCTAssertTrue(PatternEngine.lookup("Personal Layout", profile: renamedRepair) != nil)
        XCTAssertTrue(PatternEngine.lookup("Movie", profile: renamedRepair)?.id != renamed.classifications![movieIndex].id)
        let archive = SettingsArchive(profiles: [legacy], general: .suggestedDefaults, activeProfileID: legacy.id)
        XCTAssertEqual(try archive.validatedProfiles()[0].mediaCategories, legacy.mediaCategories)
    }
    func testUnmatchedVideoLibraryRoot() throws {
        var profile = ProfileSetup.configured(.video, name: "Videos")
        profile.root = library.path; profile.mediaRoutingEnabled = true; profile.mediaCategories = []
        profile.folderMask = "{Title}"; profile.filenameMask = "{Title}"
        let url = src.appendingPathComponent("Unknown.mp4"); try Data("bytes".utf8).write(to: url)
        var fields = Fields(); fields.title = "Unmatched"
        let item = Item(url: url, size: 5, fields: fields, evidence: "", reviewed: false)
        XCTAssertFalse(try makeConfirmedFilingPlan(items: [item], profile: profile, mode: .copy, keepCurrentNames: true).rows[0].actionable)
        profile.unmatchedMediaUseLibraryRoot = true
        let plan = try makeConfirmedFilingPlan(items: [item], profile: profile, mode: .copy, keepCurrentNames: true)
        XCTAssertTrue(plan.rows[0].actionable)
        XCTAssertEqual(plan.rows[0].destination, library.appendingPathComponent("Unmatched/Unknown.mp4").path)
        XCTAssertTrue(plan.rows[0].explanation.contains("use Library Root"))
        let saved = base.appendingPathComponent("Root fallback.json")
        try ProfileSettingsStore.write([profile], to: saved)
        XCTAssertEqual(try ProfileSettingsStore.read(from: saved)[0].unmatchedMediaUseLibraryRoot, true)
        XCTAssertEqual(try executor().execute(plan).completed, 1)
        var unknown = item; unknown.fields.mediaCategory = "Unknown Category"
        XCTAssertFalse(try makeConfirmedFilingPlan(items: [unknown], profile: profile, mode: .copy, keepCurrentNames: true).rows[0].actionable)
        var category = MediaCategory("Chosen", type: "Movie", folderMask: "", filenameMask: "{Title}", rules: [.init(keyword: "Unknown")])
        profile.mediaCategories = [category]
        XCTAssertFalse(try makeConfirmedFilingPlan(items: [item], profile: profile, mode: .copy, keepCurrentNames: true).rows[0].actionable) // matched but unmapped cannot fall back
        category.enabled = false; profile.mediaCategories = [category]
        unknown.fields.mediaCategory = "Chosen"
        XCTAssertFalse(try makeConfirmedFilingPlan(items: [unknown], profile: profile, mode: .copy, keepCurrentNames: true).rows[0].actionable)
        profile.defaultMediaCategoryID = category.id
        XCTAssertThrowsError(try profile.validate())
    }
    func testMixedMediaCategoryFiling() throws {
        var profile = ProfileSetup.configured(.video, name: "Mixed Videos")
        profile.root = library.path; profile.mediaRoutingEnabled = true
        let folders = ["Commercials": "Ad Vault", "Documentaries": "Nonfiction", "Home Videos": "Family", "Movies": "Films", "Music Videos": "Concerts", "TV Shows": "Television"]
        for i in profile.mediaCategories!.indices { profile.mediaCategories![i].rootFolder = folders[profile.mediaCategories![i].name] }
        try profile.validate()
        let examples = [("Great Film (2001).mp4", "Films/Great Film (2001)/Great Film (2001).mp4"),
                        ("Series - s01e02 - Pilot.mp4", "Television/Series/Season 01/Series - s01e02 - Pilot.mp4"),
                        ("Documentary - Ocean (2002).mp4", "Nonfiction/Ocean (2002)/Ocean (2002).mp4"),
                        ("Commercial - Camera.mp4", "Ad Vault/Camera.mp4"),
                        ("Home Video Picnic.mp4", "Family/Home Video Picnic.mp4"),
                        ("Music Video Concert.mp4", "Concerts/Music Video Concert/Music Video Concert.mp4")]
        var items: [Item] = []
        for (name, _) in examples {
            let url = src.appendingPathComponent(name); try Data(name.utf8).write(to: url)
            let interpreted = Names.basicInterpret(url, profile)
            items.append(Item(url: url, size: Int64(name.utf8.count), fields: interpreted.0, evidence: interpreted.1, reviewed: true))
        }
        let plan = try makePlan(items: items, profile: profile, mode: .copy, category: "", fileOnly: false)
        XCTAssertEqual(plan.rows.filter(\.actionable).count, 6)
        for (i, example) in examples.enumerated() {
            XCTAssertEqual(plan.rows[i].destination, library.appendingPathComponent(example.1).path)
            XCTAssertFalse(FileManager.default.fileExists(atPath: plan.rows[i].destination))
            XCTAssertTrue(plan.rows[i].explanation.contains("Media Category:"))
        }
        XCTAssertEqual(try executor().execute(plan).completed, 6)
        for (i, example) in examples.enumerated() {
            XCTAssertTrue(FileManager.default.fileExists(atPath: items[i].url.path))
            XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent(example.1)), Data(example.0.utf8))
        }
    }
    func testMediaCategoryPriorityAndCapture() throws {
        var profile = ProfileSetup.configured(.video, name: "Videos"); profile.mediaRoutingEnabled = true
        for i in profile.mediaCategories!.indices { profile.mediaCategories![i].rootFolder = profile.mediaCategories![i].name }
        var kids = MediaCategory("Children", type: "Movie", folderMask: "{Title}", filenameMask: "{Title}", rules: [.init(type: "Movie", keyword: "kids")])
        kids.rootFolder = "Kid Movies"; kids.aliases = "Kids, Family Films"
        profile.mediaCategories!.append(kids) // keyword specificity wins even after generic Movies
        let url = src.appendingPathComponent("Adventure for Kids (2001).mp4")
        let fields = Names.basicInterpret(url, profile).0
        XCTAssertEqual(MediaRouting.resolve(fields: fields, source: url, profile: profile).0?.id, kids.id)
        XCTAssertEqual(MediaRouting.resolve(fields: fields, source: src.appendingPathComponent("Skids.mp4"), profile: profile).0?.name, "Movies")
        var tv = fields; tv.type = "TV Show"
        XCTAssertEqual(MediaRouting.resolve(fields: tv, source: url, profile: profile).0?.name, "TV Shows")
        var explicit = fields; explicit.mediaCategory = "Documentaries"
        XCTAssertEqual(MediaRouting.resolve(fields: explicit, source: url, profile: profile).0?.name, "Documentaries")
        profile.workspacePatterns = [WorkspacePattern("{Title} [{MediaCategory}]")]
        let capturedURL = src.appendingPathComponent("Story [Family Films].mp4")
        let captured = Names.basicInterpret(capturedURL, profile).0
        XCTAssertEqual(captured.mediaCategory, "Family Films")
        let context = try MediaRouting.context(fields: captured, source: capturedURL, profile: profile, requireDestination: true)
        XCTAssertEqual(context.fields.mediaCategory, "Children"); XCTAssertEqual(context.rootFolder, "Kid Movies")
        XCTAssertEqual(context.fields.type, "Movie")
        XCTAssertEqual(try Names.render("{Title} [{MediaCategory}]", fields: context.fields, profile: profile, source: capturedURL, folder: false), "Story [Children]")
        profile.defaultMediaCategoryID = kids.id
        var unknown = Fields(); unknown.title = "Unclassified"
        XCTAssertEqual(MediaRouting.resolve(fields: unknown, source: url, profile: profile).0?.id, kids.id)
        unknown.mediaCategory = "Unknown Category"
        XCTAssertThrowsError(try MediaRouting.context(fields: unknown, source: url, profile: profile, requireDestination: true))
        unknown.mediaCategory = "Children"
        profile.mediaCategories![profile.mediaCategories!.count - 1].enabled = false
        XCTAssertThrowsError(try MediaRouting.context(fields: unknown, source: url, profile: profile, requireDestination: true))
        XCTAssertThrowsError(try profile.validate()) // disabled default must be resolved
    }
    func testMediaCategorySafetyAndArchives() throws {
        var profile = ProfileSetup.configured(.video, name: "Videos"); profile.root = library.path
        let originalMask = profile.folderMask
        let url = src.appendingPathComponent("Example (2001).mp4"); try Data("bytes".utf8).write(to: url)
        let fields = Names.basicInterpret(url, profile).0
        let item = Item(url: url, size: 5, fields: fields, evidence: "", reviewed: false)
        XCTAssertEqual(try MediaRouting.context(fields: fields, source: url, profile: profile).folderMask, PatternEngine.folderMask(for: fields, profile: profile))
        profile.mediaRoutingEnabled = true
        let unmapped = try makeConfirmedFilingPlan(items: [item], profile: profile, mode: .copy, keepCurrentNames: true)
        XCTAssertFalse(unmapped.rows[0].actionable); XCTAssertTrue(unmapped.rows[0].explanation.contains("destination folder for Media Category"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent("Movies").path))
        profile.mediaCategories![3].rootFolder = "../Outside"
        XCTAssertThrowsError(try profile.validate())
        XCTAssertThrowsError(try MediaRouting.context(fields: fields, source: url, profile: profile, requireDestination: true))
        profile.mediaCategories![3].rootFolder = "Shared"
        profile.mediaCategories![3].folderMask = ""
        profile.mediaCategories![3].filenameMask = "{Title}"
        var sibling = MediaCategory("Alternate", type: "Movie", folderMask: "", filenameMask: "{Title}")
        sibling.rootFolder = "Shared"; profile.mediaCategories!.append(sibling)
        let secondURL = src.appendingPathComponent("Second.mp4"); try Data("bytes".utf8).write(to: secondURL)
        var one = item; one.fields.title = "Same"; one.fields.mediaCategory = "Movies"
        var secondFields = one.fields; secondFields.mediaCategory = "Alternate"
        let two = Item(url: secondURL, size: 5, fields: secondFields, evidence: "", reviewed: false)
        let collision = try makeConfirmedFilingPlan(items: [one, two], profile: profile, mode: .copy, keepCurrentNames: false)
        XCTAssertEqual(collision.rows.filter(\.actionable).count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent("Shared").path))
        let archive = SettingsArchive(profiles: [profile], general: .suggestedDefaults, activeProfileID: profile.id)
        let restored = try JSONDecoder().decode(SettingsArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(try restored.validatedProfiles()[0], profile)
        var dictionary = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        dictionary.removeValue(forKey: "mediaCategories"); dictionary.removeValue(forKey: "mediaRoutingEnabled"); dictionary.removeValue(forKey: "defaultMediaCategoryID")
        let legacy = try JSONDecoder().decode(Profile.self, from: JSONSerialization.data(withJSONObject: dictionary))
        XCTAssertFalse(MediaRouting.enabled(legacy)); XCTAssertEqual(legacy.folderMask, originalMask)
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: Data(#"{"title":"Old"}"#.utf8)).mediaCategory, "")
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: Data(#"{"custom":{"MediaCategory":"Kids"}}"#.utf8)).mediaCategory, "Kids")
        var aliasConflict = profile; aliasConflict.mediaCategories![0].aliases = "Movies"
        XCTAssertThrowsError(try aliasConflict.validate())
    }
    func testConfirmedFilingPaths() throws {
        var profile = ProfileSetup.configured(.other, name: "Test")
        profile.extensions = "txt"; profile.root = library.path; profile.folderMask = ""; profile.filenameMask = "{Title}"
        let url = src.appendingPathComponent("Original.txt"); try Data("original bytes".utf8).write(to: url)
        var fields = Fields(); fields.title = "Proposed"
        let item = Item(url: url, size: 14, fields: fields, evidence: "Test", reviewed: false)
        let ordinary = try makePlan(items: [item], profile: profile, mode: .copy, category: "", fileOnly: false)
        XCTAssertFalse(ordinary.rows[0].actionable)
        let keep = try makeConfirmedFilingPlan(items: [item], profile: profile, mode: .copy, keepCurrentNames: true)
        XCTAssertTrue(keep.rows[0].actionable); XCTAssertTrue(keep.rows[0].destination.hasSuffix("/Original.txt"))
        XCTAssertFalse(item.reviewed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: keep.rows[0].destination)) // planning never executes
        let rename = try makeConfirmedFilingPlan(items: [item], profile: profile, mode: .move, keepCurrentNames: false)
        XCTAssertTrue(rename.rows[0].actionable); XCTAssertTrue(rename.rows[0].destination.hasSuffix("/Proposed.txt"))
        XCTAssertEqual(try executor().execute(keep).completed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(try makeConfirmedFilingPlan(items: [item], profile: profile, mode: .copy, keepCurrentNames: true).rows[0].actionable) // collision remains blocked
        var missingFolder = profile; missingFolder.folderMask = "{Author}"
        XCTAssertFalse(try makeConfirmedFilingPlan(items: [item], profile: missingFolder, mode: .copy, keepCurrentNames: true).rows[0].actionable)
        XCTAssertThrowsError(try makeConfirmedFilingPlan(items: [item], profile: profile, mode: .clean, keepCurrentNames: true))
        var noRoot = profile; noRoot.root = ""
        do { _ = try makeConfirmedFilingPlan(items: [item], profile: noRoot, mode: .copy, keepCurrentNames: true); XCTAssertTrue(false) }
        catch { XCTAssertTrue(error.localizedDescription.contains("Library destination not configured")) }
        noRoot.root = library.appendingPathComponent("Missing").path
        do { _ = try makeConfirmedFilingPlan(items: [item], profile: noRoot, mode: .copy, keepCurrentNames: true); XCTAssertTrue(false) }
        catch { XCTAssertTrue(error.localizedDescription.contains("Library destination is unavailable")) }
        noRoot.root = "relative/path"
        do { _ = try makeConfirmedFilingPlan(items: [item], profile: noRoot, mode: .copy, keepCurrentNames: true); XCTAssertTrue(false) }
        catch { XCTAssertTrue(error.localizedDescription.contains("valid absolute folder")) }
        XCTAssertEqual(try executor().execute(rename).completed, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rename.rows[0].destination))
    }
    func testPatternProtectionAndExplicitFiling() throws {
        var music = ProfileSetup.configured(.music, name: "Music"); music.exceptions = "AC-DC"
        let fields = Names.basicInterpret(src.appendingPathComponent("ac - dc - song name.mp3"), music).0
        XCTAssertEqual(fields.artist, "AC-DC"); XCTAssertEqual(fields.title, "Song Name")
        var video = ProfileSetup.configured(.video, name: "Videos"); video.root = library.path
        let url = src.appendingPathComponent("Story (2001).mp4"); try Data("bytes".utf8).write(to: url)
        let scan = try scan(src, profile: video, recursive: false)
        var item = try XCTUnwrap(scan.items.first); XCTAssertTrue(item.alternatives.isEmpty)
        item.reviewed = true; item.fields.resolution = "720p"
        let plan = try makePlan(items: [item], profile: video, mode: .copy, category: "", fileOnly: false)
        XCTAssertTrue(plan.rows[0].destination.hasSuffix("Movies/Story (2001)/Story (2001) [720p].mp4"))
        XCTAssertEqual(try executor().execute(plan).completed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
    func testSpellingProposalReplacement() throws {
        var profile = Profile(.video); profile.titleCase = false; profile.exceptions = "TV, AiDEN"
        let original = "😀 Show - Infomerciallls - s01e11 - Infomerciallls.mp4"
        let stem = URL(fileURLWithPath: original).deletingPathExtension().lastPathComponent
        let corrected = try FilenameSpelling.replacing("Infomerciallls", in: stem, with: "Infomercials", profile: profile)
        XCTAssertEqual(corrected, "😀 Show - Infomercials - s01e11 - Infomercials")
        XCTAssertEqual(try FilenameSpelling.replacing("infomerciallls", in: "Infomerciallls ExtraInfomerciallls", with: "TV", profile: profile), "TV ExtraInfomerciallls")
        XCTAssertEqual(try FilenameSpelling.replacing("wrong", in: "wrong", with: "aiden", profile: profile), "AiDEN")
        XCTAssertThrowsError(try FilenameSpelling.replacing("missing", in: stem, with: "Word", profile: profile))
        XCTAssertThrowsError(try FilenameSpelling.replacing("Show", in: stem, with: "../unsafe", profile: profile))
        XCTAssertThrowsError(try FilenameSpelling.replacing("Show", in: stem, with: "", profile: profile))
    }
    func testExistingFolderCasingAndExplanations() throws {
        var profile = Profile(.video); profile.exceptions = "TV, AC-DC"
        var rules = profile.rules; rules.folderTitleCase = true; rules.folderHyphensToSpaces = true; profile.rules = rules
        XCTAssertEqual(RuleEngine.existingFolder("Best tv series ever", profile: profile).name, "Best TV Series Ever")
        XCTAssertEqual(RuleEngine.existingFolder("ac - dc - live", profile: profile).name, "AC-DC Live")
        let folder = src.appendingPathComponent("Best tv series ever")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let child = folder.appendingPathComponent("Keep_this-name.MP4"); try Data("unchanged".utf8).write(to: child)
        let plan = try planFolders(workspace: src, profile: profile)
        let row = try XCTUnwrap(plan.rows.first)
        XCTAssertTrue(row.actionable); XCTAssertTrue(row.detail.contains("Folder smart title case")); XCTAssertTrue(row.detail.contains(profile.name))
        XCTAssertEqual(try FolderExecutor(journal: executor().journal).execute(plan, included: [row.id]).completed, 1)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: row.destination).appendingPathComponent(child.lastPathComponent)), Data("unchanged".utf8))
        let noChanges = try planFolders(workspace: src, profile: profile)
        XCTAssertFalse(noChanges.rows[0].actionable); XCTAssertTrue(noChanges.rows[0].detail.contains("No applicable folder rule"))
        rules.folderTitleCase = false; profile.rules = rules; profile.exceptions = ""
        XCTAssertEqual(RuleEngine.existingFolder("keep lowercase", profile: profile).name, "keep lowercase")
    }
    func testEpisodeBulkProposalsAndRename() throws {
        var video = Profile(.video); video.titleCase = false
        var rules = video.rules; rules.episodeCapitalization = .lowercase; video.rules = rules
        let names = ["MBL - s01e01 - Pilot.mp4", "My Bset Life - s01e02 - Moving Day.mp4"]
        for name in names { try Data("episode fixture".utf8).write(to: src.appendingPathComponent(name)) }
        let originals = try scan(src, profile: video, recursive: false).items
        XCTAssertEqual(originals.count, 2)
        var edited = originals
        for index in edited.indices {
            XCTAssertEqual(edited[index].fields.title, "")
            XCTAssertEqual(Magic.suggestions(url: edited[index].url, profile: video).first?.fields.title, "")
            edited[index].fields.series = "My Best Life"
            edited[index].fields.season = "02"
            XCTAssertEqual(edited[index].fields.episode, originals[index].fields.episode)
            XCTAssertEqual(edited[index].fields.episodeTitle, originals[index].fields.episodeTitle)
            XCTAssertTrue(FileManager.default.fileExists(atPath: edited[index].url.path))
        }
        XCTAssertEqual(try proposedFilename(edited[0], profile: video), "My Best Life - s02e01 - Pilot.mp4")
        XCTAssertEqual(try proposedFilename(edited[1], profile: video), "My Best Life - s02e02 - Moving Day.mp4")
        let plan = try makeDirectRenamePlan(items: edited, profile: video)
        XCTAssertEqual(try executor().execute(plan).completed, 2)
        for row in plan.rows { XCTAssertTrue(FileManager.default.fileExists(atPath: row.destination)) }
        let movie = Names.basicInterpret(src.appendingPathComponent("My Favorite Movie (1999).mp4"), video).0
        XCTAssertEqual(movie.title, "My Favorite Movie"); XCTAssertEqual(movie.year, "1999")
        var invalid = edited[0]; invalid.fields.season = "wrong"
        XCTAssertThrowsError(try proposedFilename(invalid, profile: video))
    }
    func testManualMagicAndDisplayPreferences() throws {
        var p = Profile(.music); var rules = p.rules; rules.useMagic = true; p.rules = rules
        p.extensions = "mp3"
        let url = src.appendingPathComponent("Artist - Song.mp3")
        try Data("fixture".utf8).write(to: url)
        let discovered = try scan(src, profile: p, recursive: false)
        XCTAssertEqual(discovered.items.count, 1)
        XCTAssertTrue(discovered.items[0].alternatives.isEmpty)
        XCTAssertEqual(discovered.items[0].fields, Names.basicInterpret(url, p).0)
        let analyzed = try Magic.prepare(discovered.items, profile: p, memories: [], cancel: Cancellation())
        XCTAssertFalse(analyzed[0].alternatives.isEmpty)
        let token = Cancellation(); token.cancel()
        XCTAssertThrowsError(try Magic.prepare(discovered.items, profile: p, memories: [], cancel: token))
        XCTAssertTrue(discovered.items[0].alternatives.isEmpty)
        let legacy = try JSONDecoder().decode(UniversalPreferences.self, from: Data(#"{"groups":{},"lowercaseTitleWords":"a, the"}"#.utf8))
        XCTAssertEqual(legacy.filingAction, .copy)
        XCTAssertEqual(legacy.hoverTiming ?? .immediate, .immediate)
        XCTAssertTrue(legacy.showFilenameDifferences ?? true)
        var prefs = legacy; prefs.showFilenameDifferences = false; prefs.hoverTiming = .off; prefs.defaultFilingAction = .move
        XCTAssertEqual(try JSONDecoder().decode(UniversalPreferences.self, from: JSONEncoder().encode(prefs)), prefs)
        XCTAssertEqual(prefs.filingAction, .move)
    }
    func testSuggestedDefaultsAndAppend() throws {
        let defaults = UniversalPreferences.suggestedDefaults
        XCTAssertTrue(defaults.combinedEntries.count > 150)
        XCTAssertTrue(UniversalPreferences.entries(defaults.groups["other"] ?? "").isEmpty)
        for value in defaults.groups.values { XCTAssertFalse(value.contains("\n")) }
        XCTAssertFalse(defaults.combinedEntries.contains("fun.")); XCTAssertFalse(defaults.combinedEntries.contains("HAIM"))
        var existing = UniversalPreferences(existingExceptions: "custom, dj, AC-DC")
        let beforeOther = existing.groups["other"]
        let result = existing.appendSuggestions()
        XCTAssertTrue(result.added > 0); XCTAssertTrue(result.conflicts > 0); XCTAssertTrue(result.existing > 0)
        XCTAssertEqual(existing.groups["other"], beforeOther)
        XCTAssertFalse(UniversalPreferences.entries(existing.groups["abbreviations"] ?? "").contains("DJ"))
        let first = existing
        XCTAssertEqual(existing.appendSuggestions().added, 0)
        XCTAssertEqual(existing, first)
        try defaults.validate()
    }
    func testProtectedSpellingsAndParsing() throws {
        var music = Profile(.music); music.exceptions = "AC-DC, blink-182, R.E.M."
        var rules = music.rules; rules.hyphensToSpaces = true; rules.dotsToDashes = true; music.rules = rules
        for original in ["ac-dc - song name.mp3", "ac - dc - song name.mp3"] {
            let url = src.appendingPathComponent(original)
            let fields = Names.basicInterpret(url, music).0
            XCTAssertEqual(fields.artist, "AC-DC"); XCTAssertEqual(fields.title, "Song Name")
            let i = Item(url: url, size: 1, fields: fields, evidence: "", reviewed: false)
            XCTAssertEqual(try proposedFilename(i, profile: music), "AC-DC - Song Name.mp3")
            XCTAssertEqual(Magic.suggestions(url: url, profile: music)[0].fields.artist, "AC-DC")
        }
        music.extractionMask = "{Artist} - {Title}"
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("ac - dc - song.mp3"), music).0.artist, "AC-DC")
        music.extractionMask = ""
        rules.hyphensToSpaces = false; music.rules = rules
        XCTAssertEqual(Names.clean("BAC-DCE AC-DCE", music), "Bac-Dce Ac-Dce")
        XCTAssertEqual(Names.clean("r.e.m. blink-182", music), "R.E.M. blink-182")
        rules.formatEpisodes = true; music.rules = rules
        XCTAssertEqual(Names.clean("r.e.m. s01e01 Pilot", music), "R.E.M. - s01e01 - Pilot")
        music.removeTokens = "AC-DC"
        XCTAssertEqual(Names.clean("ac - dc Song", music), "Song")
        music.removeTokens = ""; rules.replacements = [ReplacementRule(find: "1", replacement: "X")]; music.rules = rules
        XCTAssertEqual(Names.clean("blink-182 1", music), "blink-182 X")
    }
    func testBookSubtypesAndNewComponents() throws {
        for subtype in [BookSubtype.general, .ebook, .comic] {
            var book = Profile(.audiobook, bookSubtype: subtype)
            XCTAssertTrue(book.accepted.contains("pdf"))
            var fields = Fields(); fields.author = "Author"; fields.bookTitle = "Book"; fields.publisher = "Publisher"; fields.year = "2024"
            fields.narrator = "Narrator"; fields.illustrator = "Artist"; fields.series = "Series"; fields.seriesNumber = "2"; fields.issueNumber = "3"; fields.volume = "1"
            let url = src.appendingPathComponent("source.epub")
            XCTAssertEqual(try Names.render("{Title} - {Publisher} - {Year}", fields: fields, profile: book, source: url, folder: false), "Book - Publisher - 2024")
            XCTAssertEqual(try Names.render("{Narrator} - {Illustrator} - {IssueNumber} - {Volume} - {SeriesNumber}", fields: fields, profile: book, source: url, folder: false), "Narrator - Artist - 3 - 1 - 2")
            book.extractionMask = "{Author} - {Title} - {Publisher} - {Year}"
            let interpreted = Names.basicInterpret(src.appendingPathComponent("Writer - Story - Press - 2024.epub"), book).0
            XCTAssertEqual(interpreted.bookTitle, "Story"); XCTAssertEqual(interpreted.publisher, "Press"); XCTAssertEqual(interpreted.year, "2024")
            XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: JSONEncoder().encode(fields)), fields)
            XCTAssertThrowsError(try Names.render("{Narrator}", fields: Fields(), profile: book, source: url, folder: false))
        }
        let old = try JSONDecoder().decode(Fields.self, from: Data("{}".utf8))
        XCTAssertEqual(old.publisher, ""); XCTAssertEqual(old.recordingType, "")
        XCTAssertEqual(Profile(.audiobook).effectiveBookSubtype, .audiobook)
        XCTAssertFalse(Profile(.audiobook, bookSubtype: .ebook).supportsEpisodes)
    }
    func testMusicYearTrackAndRecording() throws {
        let music = Profile(.music), url = src.appendingPathComponent("03 - Artist - Song (2024) [Live].mp3")
        let fields = Names.basicInterpret(url, music).0
        XCTAssertEqual(fields.artist, "Artist"); XCTAssertEqual(fields.trackNumber, "03"); XCTAssertEqual(fields.year, "2024"); XCTAssertEqual(fields.recordingType, "Live")
        XCTAssertTrue(fields.title.contains("[Live]"))
        XCTAssertEqual(try Names.render("{TrackNumber:02} - {Artist} - {Year} {Live}", fields: fields, profile: music, source: url, folder: false), "03 - Artist - 2024 (Live)")
        var studio = fields; studio.recordingType = "Studio"
        XCTAssertEqual(try Names.render("{Live}{Artist}", fields: studio, profile: music, source: url, folder: false), "Artist")
        XCTAssertEqual(try Names.render("{Artist} {Live}", fields: studio, profile: music, source: url, folder: false), "Artist")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Artist - Song.mp3"), music).0.recordingType, "")
    }
    func testMissingAndUncertainFields() throws {
        var music = Profile(.music); music.root = library.path
        let i = try item("uninterpreted.mp3"); var unreviewed = i; unreviewed.reviewed = false
        XCTAssertEqual(try makePlan(items: [unreviewed], profile: music, mode: .copy, category: "Reports", fileOnly: false).rows[0].status, "Needs review")
        XCTAssertEqual(try makePlan(items: [i], profile: music, mode: .copy, category: "Reports", fileOnly: false).rows[0].status, "Missing required value")
    }
}

let suite = FilerCoreTests()
do { try suite.setUpWithError(); try suite.testCopyAndGuardedUndo(); try suite.tearDownWithError(); print("Checked testCopyAndGuardedUndo") } catch { failures += 1; print("FAIL testCopyAndGuardedUndo: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testSameVolumeMoveUndoAndOccupiedSource(); try suite.tearDownWithError(); print("Checked testSameVolumeMoveUndoAndOccupiedSource") } catch { failures += 1; print("FAIL testSameVolumeMoveUndoAndOccupiedSource: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testVerifiedCopyMoveEngine(); try suite.tearDownWithError(); print("Checked testVerifiedCopyMoveEngine") } catch { failures += 1; print("FAIL testVerifiedCopyMoveEngine: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testVerificationFailureRetainsSourceAndRecovery(); try suite.tearDownWithError(); print("Checked testVerificationFailureRetainsSourceAndRecovery") } catch { failures += 1; print("FAIL testVerificationFailureRetainsSourceAndRecovery: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testPublicationFailureRetainsBothAndTruthfulState(); try suite.tearDownWithError(); print("Checked testPublicationFailureRetainsBothAndTruthfulState") } catch { failures += 1; print("FAIL testPublicationFailureRetainsBothAndTruthfulState: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testExistingAndLateConflictsNeverOverwrite(); try suite.tearDownWithError(); print("Checked testExistingAndLateConflictsNeverOverwrite") } catch { failures += 1; print("FAIL testExistingAndLateConflictsNeverOverwrite: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testBatchCollisionAndNoOp(); try suite.tearDownWithError(); print("Checked testBatchCollisionAndNoOp") } catch { failures += 1; print("FAIL testBatchCollisionAndNoOp: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testStaleSourceAndReplacedRoot(); try suite.tearDownWithError(); print("Checked testStaleSourceAndReplacedRoot") } catch { failures += 1; print("FAIL testStaleSourceAndReplacedRoot: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testLinksAndTraversal(); try suite.tearDownWithError(); print("Checked testLinksAndTraversal") } catch { failures += 1; print("FAIL testLinksAndTraversal: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testCancellationBetweenFiles(); try suite.tearDownWithError(); print("Checked testCancellationBetweenFiles") } catch { failures += 1; print("FAIL testCancellationBetweenFiles: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testChangedCopyUndoRefused(); try suite.tearDownWithError(); print("Checked testChangedCopyUndoRefused") } catch { failures += 1; print("FAIL testChangedCopyUndoRefused: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testProfilesMixedAndNames(); try suite.tearDownWithError(); print("Checked testProfilesMixedAndNames") } catch { failures += 1; print("FAIL testProfilesMixedAndNames: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testSharedChapterGroupAndNewFolderRace(); try suite.tearDownWithError(); print("Checked testSharedChapterGroupAndNewFolderRace") } catch { failures += 1; print("FAIL testSharedChapterGroupAndNewFolderRace: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMusicAndVideoPlansAndExtensionCase(); try suite.tearDownWithError(); print("Checked testMusicAndVideoPlansAndExtensionCase") } catch { failures += 1; print("FAIL testMusicAndVideoPlansAndExtensionCase: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testNewRulesAndExtensionPreservation(); try suite.tearDownWithError(); print("Checked testNewRulesAndExtensionPreservation") } catch { failures += 1; print("FAIL testNewRulesAndExtensionPreservation: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testSmartTitleAndEpisodeRules(); try suite.tearDownWithError(); print("Checked testSmartTitleAndEpisodeRules") } catch { failures += 1; print("FAIL testSmartTitleAndEpisodeRules: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testArtistBuckets(); try suite.tearDownWithError(); print("Checked testArtistBuckets") } catch { failures += 1; print("FAIL testArtistBuckets: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testManualOverrideAndCorrectionJournal(); try suite.tearDownWithError(); print("Checked testManualOverrideAndCorrectionJournal") } catch { failures += 1; print("FAIL testManualOverrideAndCorrectionJournal: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testCaseOnlyRenameUndoAndInterruptedRecovery(); try suite.tearDownWithError(); print("Checked testCaseOnlyRenameUndoAndInterruptedRecovery") } catch { failures += 1; print("FAIL testCaseOnlyRenameUndoAndInterruptedRecovery: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testFolderCleanUndoAndStaleContents(); try suite.tearDownWithError(); print("Checked testFolderCleanUndoAndStaleContents") } catch { failures += 1; print("FAIL testFolderCleanUndoAndStaleContents: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testFolderConflictsLinksAndSelection(); try suite.tearDownWithError(); print("Checked testFolderConflictsLinksAndSelection") } catch { failures += 1; print("FAIL testFolderConflictsLinksAndSelection: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMagicOriginalEvidenceAndManualPrecedence(); try suite.tearDownWithError(); print("Checked testMagicOriginalEvidenceAndManualPrecedence") } catch { failures += 1; print("FAIL testMagicOriginalEvidenceAndManualPrecedence: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMagicSelectionEvidenceAndRememberedIsolation(); try suite.tearDownWithError(); print("Checked testMagicSelectionEvidenceAndRememberedIsolation") } catch { failures += 1; print("FAIL testMagicSelectionEvidenceAndRememberedIsolation: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testRecommendationsAndAnonymizedReport(); try suite.tearDownWithError(); print("Checked testRecommendationsAndAnonymizedReport") } catch { failures += 1; print("FAIL testRecommendationsAndAnonymizedReport: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testProfileMigrationAndCustomNamesUnchanged(); try suite.tearDownWithError(); print("Checked testProfileMigrationAndCustomNamesUnchanged") } catch { failures += 1; print("FAIL testProfileMigrationAndCustomNamesUnchanged: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testFolderCaseRecoveryAndUndoGuard(); try suite.tearDownWithError(); print("Checked testFolderCaseRecoveryAndUndoGuard") } catch { failures += 1; print("FAIL testFolderCaseRecoveryAndUndoGuard: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testConflictingMagicGroupsAndMissingFields(); try suite.tearDownWithError(); print("Checked testConflictingMagicGroupsAndMissingFields") } catch { failures += 1; print("FAIL testConflictingMagicGroupsAndMissingFields: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMissingAndUncertainFields(); try suite.tearDownWithError(); print("Checked testMissingAndUncertainFields") } catch { failures += 1; print("FAIL testMissingAndUncertainFields: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testDirectRenameAndUndoIndependentOfComponents(); try suite.tearDownWithError(); print("Checked direct rename and independent component confirmation") } catch { failures += 1; print("FAIL direct rename: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testDirectRenameNoopCollisionAndStaleUndo(); try suite.tearDownWithError(); print("Checked direct rename no-op, collisions and stale undo") } catch { failures += 1; print("FAIL direct rename guards: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testDirectCaseOnlyRenameAndUndo(); try suite.tearDownWithError(); print("Checked direct case-only rename and undo") } catch { failures += 1; print("FAIL direct case rename: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testFilenameDifferenceDisplay(); try suite.tearDownWithError(); print("Checked filename display comparison") } catch { failures += 1; print("FAIL filename comparison: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testEpisodeRepairOrderAndTriggeredRules(); try suite.tearDownWithError(); print("Checked episode repair order and actual triggered rules") } catch { failures += 1; print("FAIL episode repair/trace: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testWhitespaceDisplayLabelsAndPreferredCase(); try suite.tearDownWithError(); print("Checked whitespace labels, collisions and preferred-case descriptions") } catch { failures += 1; print("FAIL display labels/casing: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testUniversalPreferencesAndRemovalPrecedence(); try suite.tearDownWithError(); print("Checked universal preferences, conflicts, title words and removal precedence") } catch { failures += 1; print("FAIL universal preferences: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testEpisodeComponentHoverDescriptions(); try suite.tearDownWithError(); print("Checked episode component hover descriptions") } catch { failures += 1; print("FAIL episode hover: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testFilenameSpellingCandidates(); try suite.tearDownWithError(); print("Checked spelling exemptions, boundaries and Unicode ranges") } catch { failures += 1; print("FAIL spelling candidates: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testSuggestedDefaultsAndAppend(); try suite.tearDownWithError(); print("Checked suggestion defaults, append and conflicts") } catch { failures += 1; print("FAIL suggestions: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testProtectedSpellingsAndParsing(); try suite.tearDownWithError(); print("Checked protected spellings and parsing boundaries") } catch { failures += 1; print("FAIL protected entries: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testBookSubtypesAndNewComponents(); try suite.tearDownWithError(); print("Checked book subtypes, extraction, output and legacy fields") } catch { failures += 1; print("FAIL book components: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMusicYearTrackAndRecording(); try suite.tearDownWithError(); print("Checked music year, track and recording type") } catch { failures += 1; print("FAIL music components: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testManualMagicAndDisplayPreferences(); try suite.tearDownWithError(); print("Checked manual Magic, cancellation and preference compatibility") } catch { failures += 1; print("FAIL manual Magic/preferences: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testEpisodeBulkProposalsAndRename(); try suite.tearDownWithError(); print("Checked episode bulk proposals, explicit rename and movie fields") } catch { failures += 1; print("FAIL episode bulk corrections: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testSpellingProposalReplacement(); try suite.tearDownWithError(); print("Checked spelling proposal boundaries, case, Unicode and invalid replacements") } catch { failures += 1; print("FAIL spelling replacements: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testExistingFolderCasingAndExplanations(); try suite.tearDownWithError(); print("Checked folder case preferences, explanations and unchanged child files") } catch { failures += 1; print("FAIL folder casing: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testConfigurablePatternsAndRouting(); try suite.tearDownWithError(); print("Checked pattern routing and precedence") } catch { failures += 1; print("FAIL testConfigurablePatternsAndRouting: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testPatternLiteralsValidationAndCustomFields(); try suite.tearDownWithError(); print("Checked literal pattern validation and custom components") } catch { failures += 1; print("FAIL testPatternLiteralsValidationAndCustomFields: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testRomsForgeAndOtherContentDefaults(); try suite.tearDownWithError(); print("Checked starter profiles and ROM/FORGE/software/photo components") } catch { failures += 1; print("FAIL testRomsForgeAndOtherContentDefaults: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testBookHierarchyAndParentPatterns(); try suite.tearDownWithError(); print("Checked standalone and series book hierarchy and parent-folder input") } catch { failures += 1; print("FAIL testBookHierarchyAndParentPatterns: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testProfileMigrationArchiveAndNotes(); try suite.tearDownWithError(); print("Checked profile migration, archives, notes and legacy decoding") } catch { failures += 1; print("FAIL testProfileMigrationArchiveAndNotes: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testPatternProtectionAndExplicitFiling(); try suite.tearDownWithError(); print("Checked protected spellings and explicit classified copy") } catch { failures += 1; print("FAIL testPatternProtectionAndExplicitFiling: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testConfirmedFilingPaths(); try suite.tearDownWithError(); print("Checked explicit filing bypass, original names, proposed names and destination guards") } catch { failures += 1; print("FAIL testConfirmedFilingPaths: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMixedMediaCategoryFiling(); try suite.tearDownWithError(); print("Checked mixed-category filing to mapped folders") } catch { failures += 1; print("FAIL testMixedMediaCategoryFiling: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMediaCategoryPriorityAndCapture(); try suite.tearDownWithError(); print("Checked category priorities, aliases, captures, defaults and disabled references") } catch { failures += 1; print("FAIL testMediaCategoryPriorityAndCapture: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMediaCategorySafetyAndArchives(); try suite.tearDownWithError(); print("Checked category guards, collisions, archives and legacy settings") } catch { failures += 1; print("FAIL testMediaCategorySafetyAndArchives: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testVideoCategoryCompatibilityAndPersistence(); try suite.tearDownWithError(); print("Checked video compatibility repair, persisted mappings and failed-write propagation") } catch { failures += 1; print("FAIL testVideoCategoryCompatibilityAndPersistence: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testUnmatchedVideoLibraryRoot(); try suite.tearDownWithError(); print("Checked unmatched Library Root fallback and explicit-category guards") } catch { failures += 1; print("FAIL testUnmatchedVideoLibraryRoot: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testGroupedDestinations(); try suite.tearDownWithError(); print("Checked testGroupedDestinations") } catch { failures += 1; print("FAIL testGroupedDestinations: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMoveCompletionAndRefresh(); try suite.tearDownWithError(); print("Checked testMoveCompletionAndRefresh") } catch { failures += 1; print("FAIL testMoveCompletionAndRefresh: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testReplacementRootRepreview(); try suite.tearDownWithError(); print("Checked testReplacementRootRepreview") } catch { failures += 1; print("FAIL testReplacementRootRepreview: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testArtistTheToEnd(); try suite.tearDownWithError(); print("Checked testArtistTheToEnd") } catch { failures += 1; print("FAIL testArtistTheToEnd: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMP3ReadOnlyReference(); try suite.tearDownWithError(); print("Checked testMP3ReadOnlyReference") } catch { failures += 1; print("FAIL testMP3ReadOnlyReference: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testID3VersionsAndValues(); try suite.tearDownWithError(); print("Checked testID3VersionsAndValues") } catch { failures += 1; print("FAIL testID3VersionsAndValues: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testID3LegacyAndAPECoexist(); try suite.tearDownWithError(); print("Checked testID3LegacyAndAPECoexist") } catch { failures += 1; print("FAIL testID3LegacyAndAPECoexist: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testID3FlagsAndMalformedInput(); try suite.tearDownWithError(); print("Checked testID3FlagsAndMalformedInput") } catch { failures += 1; print("FAIL testID3FlagsAndMalformedInput: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testVideoMaskMetadataAndConflicts(); try suite.tearDownWithError(); print("Checked testVideoMaskMetadataAndConflicts") } catch { failures += 1; print("FAIL testVideoMaskMetadataAndConflicts: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testVideoMagicAndManualPrecedence(); try suite.tearDownWithError(); print("Checked testVideoMagicAndManualPrecedence") } catch { failures += 1; print("FAIL testVideoMagicAndManualPrecedence: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try await suite.testNativeVideoMetadata(); try suite.tearDownWithError(); print("Checked testNativeVideoMetadata") } catch { failures += 1; print("FAIL testNativeVideoMetadata: \(error)"); try? suite.tearDownWithError() }
print("\(failures) failures across 68 fixture scenarios"); exit(failures == 0 ? 0 : 1)
