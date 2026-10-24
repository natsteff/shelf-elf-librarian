import Foundation
import FilerCore

extension FilerCoreTests {
    func testSettingsBackupRetentionAndRestore() throws {
        let store = SettingsBackupStore(support: base)
        XCTAssertTrue(try store.entries().isEmpty)
        for index in 0..<12 {
            var profile = p!; profile.name = "Custom \(index)"; profile.rules.numericBucket = "Numbers \(index)"
            var general = UniversalPreferences.suggestedDefaults; general.lowercaseTitleWords = "word\(index)"
            let archive = SettingsArchive(profiles: [profile], general: general, activeProfileID: profile.id)
            try store.save(archive, reason: "Save \(index)", now: Date(timeIntervalSince1970: 1_000 + Double(index)))
        }
        let entries = try store.entries(); XCTAssertEqual(entries.count, 10)
        XCTAssertEqual(entries.first?.reason, "Save 11"); XCTAssertEqual(entries.last?.reason, "Save 2")
        let oldest = try store.read(try XCTUnwrap(entries.last?.url))
        XCTAssertEqual(oldest.profiles[0].name, "Custom 2")
        XCTAssertEqual(oldest.profiles[0].rules.numericBucket, "Numbers 2")
        XCTAssertEqual(oldest.general.titleWords, "word2")
        XCTAssertEqual(oldest.activeProfileID, oldest.profiles[0].id)
        // Restoring the oldest snapshot can rotate it out safely after it has been decoded.
        let current = SettingsArchive(profiles: [p], general: .suggestedDefaults, activeProfileID: p.id)
        let recovery = try store.save(current, reason: "Restore backup")
        let target = base.appendingPathComponent("restored-profiles.json")
        try ProfileSettingsStore.write(oldest.validatedProfiles(), to: target)
        XCTAssertEqual(try ProfileSettingsStore.read(from: target)[0].name, "Custom 2")
        XCTAssertEqual(try store.read(recovery).profiles, current.profiles)
        XCTAssertEqual(try store.entries().count, 10)
        // Manual archives remain compatible with snapshots and pre-backup metadata archives.
        let manual = base.appendingPathComponent("manual.json")
        try JSONEncoder().encode(current).write(to: manual)
        XCTAssertThrowsError(try store.read(manual))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(current)) as? [String: Any])
        legacy.removeValue(forKey: "backupReason")
        let decoded = try JSONDecoder().decode(SettingsArchive.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(decoded.profiles, current.profiles)
    }
    func testSettingsBackupFailureAndIsolation() throws {
        let archive = SettingsArchive(profiles: [p], general: .suggestedDefaults, activeProfileID: p.id)
        let blocked = SettingsBackupStore(support: base)
        try Data("blocked".utf8).write(to: blocked.directory)
        let profilesURL = base.appendingPathComponent("profiles.json")
        try ProfileSettingsStore.write([p], to: profilesURL)
        var changed = p!; changed.name = "Must not be saved"
        XCTAssertThrowsError(try blocked.writeProfiles([changed], current: archive, to: profilesURL, reason: "Must fail"))
        XCTAssertEqual(try ProfileSettingsStore.read(from: profilesURL), [p!])
        XCTAssertEqual(try Data(contentsOf: blocked.directory), Data("blocked".utf8))
        let test = SettingsBackupStore(support: base.appendingPathComponent("isolated-test"))
        let sameDate = Date()
        try test.save(archive, reason: "First", now: sameDate)
        try test.save(archive, reason: "Second", now: sameDate)
        XCTAssertEqual(try test.entries().count, 2)
        let corrupt = test.directory.appendingPathComponent("Settings-corrupt.json")
        try Data("bad json".utf8).write(to: corrupt)
        XCTAssertThrowsError(try test.read(corrupt))
        XCTAssertEqual(try Data(contentsOf: blocked.directory), Data("blocked".utf8))
    }
}
