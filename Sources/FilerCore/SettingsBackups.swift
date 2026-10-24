import Foundation

public struct SettingsBackup: Identifiable {
    public var id: URL { url }
    public let url: URL
    public let date: Date
    public let reason: String
}

/// Bounded local pre-change snapshots. Manual export remains the portable backup method.
public struct SettingsBackupStore {
    public let directory: URL
    public init(support: URL) { directory = support.appendingPathComponent("Settings Backups", isDirectory: true) }
    public func entries() throws -> [SettingsBackup] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Settings-") && $0.pathExtension == "json" }
            .map { url in
                let archive = try? JSONDecoder().decode(SettingsArchive.self, from: Data(contentsOf: url))
                return SettingsBackup(url: url, date: archive?.created ?? .distantPast, reason: archive?.backupReason ?? "Settings snapshot (details unavailable)")
            }
            .sorted { $0.date == $1.date ? $0.url.lastPathComponent > $1.url.lastPathComponent : $0.date > $1.date }
    }
    @discardableResult
    public func save(_ current: SettingsArchive, reason: String, now: Date = Date()) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var snapshot = current; snapshot.created = now; snapshot.backupReason = reason
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(snapshot)
        guard data.count <= 20_000_000 else { throw fail("Settings exceed the supported backup size; settings were not saved.") }
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.calendar = Calendar(identifier: .gregorian); stamp.dateFormat = "yyyy.MM.dd-HH.mm.ss.SSS"
        let url = directory.appendingPathComponent("Settings-\(stamp.string(from: now))-\(UUID()).json")
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard try Data(contentsOf: url) == data else { throw fail("Settings backup verification failed; settings were not saved.") }
        // Never prune before a new snapshot has been written and verified.
        for old in try entries().dropFirst(10) { try FileManager.default.removeItem(at: old.url) }
        return url
    }
    /// Write the pre-change snapshot before the atomic profile replacement.
    @discardableResult
    public func writeProfiles(_ next: [Profile], current: SettingsArchive, to url: URL, reason: String) throws -> URL {
        let data = try JSONEncoder().encode(next)
        let backup = try save(current, reason: reason)
        try data.write(to: url, options: .atomic)
        return backup
    }
    public func read(_ url: URL) throws -> SettingsArchive {
        guard url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { throw fail("Choose a backup from this app's backup folder.") }
        let data = try Data(contentsOf: url)
        guard data.count <= 20_000_000 else { throw fail("Settings backup is too large.") }
        let archive = try JSONDecoder().decode(SettingsArchive.self, from: data)
        _ = try archive.validatedProfiles()
        return archive
    }
}
