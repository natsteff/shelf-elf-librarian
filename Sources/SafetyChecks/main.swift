
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
do { try suite.setUpWithError(); try suite.testMissingAndUncertainFields(); try suite.tearDownWithError(); print("Checked testMissingAndUncertainFields") } catch { failures += 1; print("FAIL testMissingAndUncertainFields: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testSharedChapterGroupAndNewFolderRace(); try suite.tearDownWithError(); print("Checked testSharedChapterGroupAndNewFolderRace") } catch { failures += 1; print("FAIL testSharedChapterGroupAndNewFolderRace: \(error)"); try? suite.tearDownWithError() }
do { try suite.setUpWithError(); try suite.testMusicAndVideoPlansAndExtensionCase(); try suite.tearDownWithError(); print("Checked testMusicAndVideoPlansAndExtensionCase") } catch { failures += 1; print("FAIL testMusicAndVideoPlansAndExtensionCase: \(error)"); try? suite.tearDownWithError() }
print("\(failures) failures across 15 fixture scenarios"); exit(failures == 0 ? 0 : 1)
