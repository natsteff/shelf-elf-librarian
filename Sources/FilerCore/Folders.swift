import Foundation
import Darwin

public struct FolderMember: Codable, Equatable {
    public let relativePath: String
    public let directory: DirectoryIdentity?
    public let file: Fingerprint?
    public let hash: String?
}
public struct FolderRow: Codable, Identifiable {
    public var id = UUID()
    public let source: String
    public var destination: String
    public let parent: DirectoryIdentity
    public let identity: DirectoryIdentity
    public var members: [FolderMember]
    public var status: String
    public var detail: String
    public var actionable: Bool { status == "Will rename folder" }
}
public struct FolderPlan: Codable {
    public var id = UUID()
    public let profileID: UUID
    public let rows: [FolderRow]
}
public struct FolderEvent: Codable, Identifiable {
    public var id = UUID()
    public var date = Date()
    public let operation: UUID
    public let row: FolderRow
    public let state: String
    public let detail: String
    public let temporary: String?
    public init(operation: UUID, row: FolderRow, state: String, detail: String = "", temporary: String? = nil) { self.operation = operation; self.row = row; self.state = state; self.detail = detail; self.temporary = temporary }
}
public func folderManifest(_ root: URL, cancel: Cancellation? = nil) throws -> (DirectoryIdentity, [FolderMember]) {
    let directory = try Directory(root.path)
    var entries: [FolderMember] = []
    var enumerationFailure = false
    guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey], options: [], errorHandler: { _, _ in enumerationFailure = true; return false }) else { throw fail("Cannot read folder contents.") }
    // FileEnumerator's error handler does not throw; separately verify every directory is readable.
    while let url = enumerator.nextObject() as? URL {
        if cancel?.cancelled == true { throw fail("Folder preview cancelled.") }
        let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey])
        guard v.isSymbolicLink != true, v.isAliasFile != true else { throw fail("Folder contains a link/alias and is excluded: \(url.path)") }
        let relative = String(url.path.dropFirst(root.path.count + 1))
        if v.isDirectory == true {
            let child = try Directory(url.path)
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            entries.append(FolderMember(relativePath: relative, directory: DirectoryIdentity(device: child.device, inode: child.inode), file: nil, hash: nil))
        } else {
            let fd = try sourceFD(url); defer { close(fd) }
            let baseline = try Fingerprint(fd: fd), hash = try digest(fd: fd)
            guard baseline == (try Fingerprint(fd: fd)) else { throw fail("A folder member changed during preview.") }
            entries.append(FolderMember(relativePath: relative, directory: nil, file: baseline, hash: hash))
        }
    }
    _ = try FileManager.default.contentsOfDirectory(atPath: root.path)
    if enumerationFailure { throw fail("Folder enumeration was incomplete.") }
    let after = try Directory(root.path)
    guard after.matches(directory) else { throw fail("Folder changed during preview.") }
    return (DirectoryIdentity(device: directory.device, inode: directory.inode), entries.sorted { $0.relativePath < $1.relativePath })
}
public func planFolders(workspace: URL, profile: Profile, selectedPaths: Set<String>? = nil, cancel: Cancellation? = nil) throws -> FolderPlan {
    let parent = try Directory(workspace.path)
    let children = try FileManager.default.contentsOfDirectory(at: workspace, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey], options: [.skipsHiddenFiles])
    var rows: [FolderRow] = []
    for url in children.sorted(by: { $0.path < $1.path }) {
        if cancel?.cancelled == true { throw fail("Folder preview cancelled.") }
        if let selectedPaths, !selectedPaths.contains(url.path) { continue }
        let v = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey])
        guard v.isDirectory == true, v.isSymbolicLink != true, v.isAliasFile != true else { continue }
        let d = try Directory(url.path)
        var row = FolderRow(source: url.path, destination: url.path, parent: DirectoryIdentity(device: parent.device, inode: parent.inode), identity: DirectoryIdentity(device: d.device, inode: d.inode), members: [], status: "No change needed", detail: "Rename this direct child folder only; child names and file bytes stay unchanged.")
        do {
            let result = RuleEngine.existingFolder(url.lastPathComponent, profile: profile)
            let name = result.name; try component(name)
            row.detail += " Profile: " + profile.name + ". "
            row.detail += name == url.lastPathComponent ? "No applicable folder rule changes this name; it already matches the enabled rules." : "Rules applied: " + result.rules.joined(separator: " · ")
            row.destination = workspace.appendingPathComponent(name).path
            if row.destination != row.source {
                try checkCollision(workspace, name: name, excluding: collisionKey(row.destination) == collisionKey(row.source) ? url.lastPathComponent : nil)
                let (identity, members) = try folderManifest(url, cancel: cancel)
                guard identity == row.identity else { throw fail("Folder changed during preview.") }
                row.members = members; row.status = "Will rename folder"
                row.detail += " \(members.filter { $0.file != nil }.count) files and \(members.filter { $0.directory != nil }.count) subfolders move with it (including hidden entries)."
            }
        } catch { row.status = "Needs review"; row.detail += "\n" + error.localizedDescription }
        rows.append(row)
    }
    let duplicates = Dictionary(grouping: rows, by: { collisionKey($0.destination) }).filter { $0.value.count > 1 }
    for i in rows.indices where duplicates[collisionKey(rows[i].destination)] != nil { rows[i].status = "Destination conflict"; rows[i].detail += " Another folder produces the same output." }
    return FolderPlan(profileID: profile.id, rows: rows)
}
public final class FolderExecutor {
    public let journal: Journal
    public init(journal: Journal) { self.journal = journal }
    private func verify(_ url: URL, row: FolderRow) throws {
        let parent = try Directory(url.deletingLastPathComponent().path)
        guard parent.device == row.parent.device, parent.inode == row.parent.inode else { throw fail("Folder parent changed since preview.") }
        let (identity, members) = try folderManifest(url)
        guard identity == row.identity, members == row.members else { throw fail("Folder identity/contents changed; preview again.") }
    }
    public func execute(_ plan: FolderPlan, included: Set<UUID>, cancel: Cancellation = Cancellation(), faultAfterStage: Bool = false) throws -> ExecutionResult {
        var result = ExecutionResult()
        for row in plan.rows where included.contains(row.id) && row.actionable {
            if cancel.cancelled { result.details.append("Cancelled between folders. Completed folder renames remain completed."); break }
            do {
                try exclusivePathRename(source: URL(fileURLWithPath: row.source), destination: URL(fileURLWithPath: row.destination), faultAfterStage: faultAfterStage, verify: { try self.verify($0, row: row) }, record: { state, temp in
                    try self.journal.recordFolder(FolderEvent(operation: plan.id, row: row, state: state, temporary: temp))
                })
                try journal.recordFolder(FolderEvent(operation: plan.id, row: row, state: "Renamed folder")); result.completed += 1
            } catch {
                result.failed += 1; result.details.append(error.localizedDescription)
                try journal.recordFolder(FolderEvent(operation: plan.id, row: row, state: "Failed / inspect recovery", detail: error.localizedDescription))
            }
        }
        return result
    }
    public func recoverCaseStage(_ event: FolderEvent) throws {
        guard event.state == "Case rename staged", let path = event.temporary,
            URL(fileURLWithPath: path).lastPathComponent.hasPrefix(".shelf-elf-case-") else { throw fail("This event is not a staged folder rename.") }
        let staged = URL(fileURLWithPath: path), original = URL(fileURLWithPath: event.row.source)
        guard staged.deletingLastPathComponent().path == original.deletingLastPathComponent().path else { throw fail("Folder recovery parent is invalid.") }
        try exclusivePathRename(source: staged, destination: original, verify: { try self.verify($0, row: event.row) }, record: { state, temporary in
            try self.journal.recordFolder(FolderEvent(operation: event.operation, row: event.row, state: "Recovery: " + state, temporary: temporary))
        })
        try journal.recordFolder(FolderEvent(operation: event.operation, row: event.row, state: "Recovered original folder"))
    }
    public func undo(_ event: FolderEvent) throws {
        guard event.state == "Renamed folder" else { throw fail("Folder event cannot be undone automatically.") }
        guard !(try journal.folderEvents()).contains(where: { $0.operation == event.operation && $0.row.id == event.row.id && $0.state == "Undone folder" }) else { throw fail("Folder rename was already undone.") }
        try exclusivePathRename(source: URL(fileURLWithPath: event.row.destination), destination: URL(fileURLWithPath: event.row.source), verify: { try self.verify($0, row: event.row) }, record: { state, temp in
            try self.journal.recordFolder(FolderEvent(operation: event.operation, row: event.row, state: "Undo: " + state, temporary: temp))
        })
        try journal.recordFolder(FolderEvent(operation: event.operation, row: event.row, state: "Undone folder"))
    }
}
