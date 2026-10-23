import Foundation
import FilerCore

extension FilerCoreTests {
    func testDocumentDefinedComponents() throws {
        var profile = ProfileSetup.configured(.documents, name: "Resources")
        profile.workspacePatterns = [WorkspacePattern("{GameTitle} - {ResourceName}")]
        profile.folderMask = "{GameTitle}/{Collection?}"; profile.filenameMask = "{GameTitle} - {ResourceName}"
        try profile.validate()
        XCTAssertEqual(PatternEngine.customComponents(profile), ["GameTitle", "ResourceName"])
        let url = src.appendingPathComponent("Catan - Quick Reference.pdf")
        let fields = Names.basicInterpret(url, profile).0
        XCTAssertEqual(fields.custom?["GameTitle"], "Catan")
        XCTAssertEqual(fields.custom?["ResourceName"], "Quick Reference")
        profile.folderMask = "{GameTitle}/{ResourceName?}"
        var edited = fields; FieldCatalog.set("ResourceName", "", &edited)
        XCTAssertEqual(try Names.render(profile.folderMask, fields: edited, profile: profile, source: url, folder: true), "Catan")
        XCTAssertEqual(try JSONDecoder().decode(Fields.self, from: JSONEncoder().encode(fields)), fields)
        let archive = SettingsArchive(profiles: [profile], general: .suggestedDefaults, activeProfileID: profile.id)
        XCTAssertEqual(try JSONDecoder().decode(SettingsArchive.self, from: JSONEncoder().encode(archive)).validatedProfiles()[0], profile)
        for kind in [Kind.music, .video] {
            var fixed = ProfileSetup.configured(kind, name: "Fixed")
            fixed.workspacePatterns = profile.workspacePatterns
            XCTAssertThrowsError(try fixed.validate())
        }
        var malicious = fields; FieldCatalog.set("GameTitle", "../escape", &malicious)
        XCTAssertThrowsError(try Names.render("{GameTitle}", fields: malicious, profile: profile, source: url, folder: true))
    }
    func testRemovedLegacySettingsAndSeriesAlias() throws {
        var profile = ProfileSetup.configured(.documents, name: "Documents")
        profile.extractionMask = "{Artist} - {Title}"
        profile.workspacePatterns = [WorkspacePattern("Old parser", compatibility: true), WorkspacePattern("{Title}")]
        let migrated = try ProfileSetup.migrate(profile)
        XCTAssertEqual(migrated.extractionMask, "")
        XCTAssertFalse(migrated.workspacePatterns!.contains { $0.compatibility })
        XCTAssertEqual(try ProfileSetup.migrate(migrated), migrated)
        var audio = ProfileSetup.configured(.audiobook, name: "Audio")
        audio.titleCase = false
        let url = src.appendingPathComponent("Author - Great Series - Book Title.m4b")
        let f = Names.basicInterpret(url, audio).0
        XCTAssertEqual(f.series, "Great Series"); XCTAssertEqual(f.bookTitle, "Book Title")
        XCTAssertEqual(try Names.render("{Author}/{SeriesName?}/{BookTitle}", fields: f, profile: audio, source: url, folder: true), "Author/Great Series/Book Title")
        var standalone = f; standalone.series = ""
        XCTAssertEqual(try Names.render("{Author}/{SeriesName?}/{BookTitle}", fields: standalone, profile: audio, source: url, folder: true), "Author/Book Title")
    }
    func testROMExtensionRoutingAndPreservation() throws {
        var rom = ProfileSetup.configured(.roms, name: "ROMs"); rom.root = library.path
        let url = src.appendingPathComponent("My_Game (USA) v1.2.NES")
        try Data("fixture".utf8).write(to: url)
        let result = Names.basicInterpret(url, rom)
        XCTAssertEqual(result.0.system, "NES")
        let item = Item(url: url, size: 7, fields: result.0, evidence: result.1, reviewed: true)
        rom.titleCase = true; rom.replaceUnderscores = true
        XCTAssertEqual(try proposedFilename(item, profile: rom), url.lastPathComponent)
        rom.classifications?[0].folderMask = "Nintendo Games"
        let plan = try makePlan(items: [item], profile: rom, mode: .copy, category: "", fileOnly: false)
        XCTAssertEqual(plan.rows[0].status, "Will copy")
        XCTAssertEqual(plan.rows[0].destination, library.appendingPathComponent("Nintendo Games/" + url.lastPathComponent).path)
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Unknown.iso"), rom).0.system, "")
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Game [SNES].nes"), rom).0.system, "SNES")
        rom.romExtensionMappings = [.init("iso", system: "PlayStation")]
        XCTAssertEqual(Names.basicInterpret(src.appendingPathComponent("Game.iso"), rom).0.system, "PlayStation")
        XCTAssertEqual(try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(rom)), rom)
        rom.romExtensionMappings?.append(.init("ISO", system: "PlayStation 2"))
        XCTAssertThrowsError(try rom.validate())
    }
    func testROMLinkedSetGuard() throws {
        var rom = ProfileSetup.configured(.roms, name: "ROMs"); rom.root = library.path
        let url = src.appendingPathComponent("Disc.bin")
        try Data("fixture".utf8).write(to: url)
        try Data("FILE Disc.bin BINARY".utf8).write(to: src.appendingPathComponent("Game.cue"))
        var fields = Fields(); fields.system = "PlayStation"; fields.title = "Disc"
        var item = Item(url: url, size: 7, fields: fields, evidence: "", reviewed: true)
        for mode in [Mode.copy, .move] {
            let plan = try makePlan(items: [item], profile: rom, mode: mode, category: "", fileOnly: true)
            XCTAssertEqual(plan.rows[0].status, "Needs review")
            XCTAssertTrue(plan.rows[0].explanation.contains("Linked ROM set"))
        }
        item.overrideBasename = "Renamed"
        XCTAssertEqual(try makeDirectRenamePlan(items: [item], profile: rom).rows[0].status, "Needs review")
        XCTAssertEqual(try Data(contentsOf: url), Data("fixture".utf8))
    }
}
