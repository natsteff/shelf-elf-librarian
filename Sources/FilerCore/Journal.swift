import Foundation
import Darwin

@_silgen_name("sqlite3_open") private func sqlOpen(_ path: UnsafePointer<CChar>!, _ db: UnsafeMutablePointer<OpaquePointer?>!) -> Int32
@_silgen_name("sqlite3_close") private func sqlClose(_ db: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_exec") private func sqlExec(_ db: OpaquePointer!, _ sql: UnsafePointer<CChar>!, _ cb: UnsafeMutableRawPointer?, _ ctx: UnsafeMutableRawPointer?, _ err: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
@_silgen_name("sqlite3_prepare_v2") private func sqlPrepare(_ db: OpaquePointer!, _ sql: UnsafePointer<CChar>!, _ n: Int32, _ statement: UnsafeMutablePointer<OpaquePointer?>!, _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
@_silgen_name("sqlite3_step") private func sqlStep(_ s: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_finalize") private func sqlFinalize(_ s: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_column_text") private func sqlText(_ s: OpaquePointer!, _ i: Int32) -> UnsafePointer<UInt8>!
public struct Event: Codable, Identifiable {
    public var id = UUID(); public var date = Date(); public var operation: UUID; public var row: PlanRow; public var state: String; public var detail: String; public var temporary: String?
    public var resultIdentity: Fingerprint?
}
public final class Journal {
    private var db: OpaquePointer?
    public init(url: URL) throws {
        guard sqlOpen(url.path, &db) == 0 else { throw fail("Cannot open journal.") }
        try exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS events (seq INTEGER PRIMARY KEY, json TEXT NOT NULL); CREATE TABLE IF NOT EXISTS plans (id TEXT PRIMARY KEY, json TEXT NOT NULL);")
    }
    deinit { _ = sqlClose(db) }
    private func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
    private func exec(_ sql: String) throws { guard sqlExec(db, sql, nil, nil, nil) == 0 else { throw fail("Journal write failed; operation stopped.") } }
    public func plan(_ p: Plan) throws { let data = try JSONEncoder().encode(p); try exec("INSERT INTO plans VALUES (\(quoted(p.id.uuidString)), \(quoted(String(decoding: data, as: UTF8.self))));") }
    public func record(_ op: UUID, row: PlanRow, state: String, detail: String = "", temporary: String? = nil, identity: Fingerprint? = nil) throws {
        let e = Event(operation: op, row: row, state: state, detail: detail, temporary: temporary, resultIdentity: identity)
        let data = try JSONEncoder().encode(e); try exec("INSERT INTO events(json) VALUES (\(quoted(String(decoding: data, as: UTF8.self))));")
    }
    public func events() throws -> [Event] {
        var stmt: OpaquePointer?; guard sqlPrepare(db, "SELECT json FROM events ORDER BY seq DESC", -1, &stmt, nil) == 0 else { throw fail("Journal read failed.") }; defer { _ = sqlFinalize(stmt) }
        var result: [Event] = []
        while sqlStep(stmt) == 100 { if let t = sqlText(stmt, 0) { result.append(try JSONDecoder().decode(Event.self, from: Data(String(cString: t).utf8))) } }
        return result
    }
}
public final class Cancellation: @unchecked Sendable {
    private let lock = NSLock(); private var value = false
    public init() {}
    public func cancel() { lock.lock(); value = true; lock.unlock() }
    public var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}
public enum Fault: String { case none, afterCopy, verification, afterPublish, beforeDelete }
public struct ExecutionResult { public var completed = 0; public var failed = 0; public var details: [String] = [] }
public final class Executor {
    public let journal: Journal
    public init(journal: Journal) { self.journal = journal }
    public func execute(_ plan: Plan, cancel: Cancellation = Cancellation(), fault: Fault = .none, forceCopyMoveForTests: Bool = false, progress: (Int, Int) -> Void = { _, _ in }) throws -> ExecutionResult {
        try journal.plan(plan)
        var createdDirectories: [String: DirectoryIdentity] = [:]
        var result = ExecutionResult(); let rows = plan.rows.filter(\.actionable)
        for (i, row) in rows.enumerated() {
            if cancel.cancelled { result.details.append("Cancelled between files. Completed files remain completed."); break }
            do { try run(row, plan: plan, fault: fault, forceCopyMove: forceCopyMoveForTests, createdDirectories: &createdDirectories); result.completed += 1 }
            catch { result.failed += 1; result.details.append("\(row.source): \(error.localizedDescription)"); try journal.record(plan.id, row: row, state: "Failed / inspect recovery", detail: error.localizedDescription) }
            progress(i + 1, rows.count)
        }
        return result
    }
    private func run(_ row: PlanRow, plan: Plan, fault: Fault, forceCopyMove: Bool, createdDirectories: inout [String: DirectoryIdentity]) throws {
        let sourceURL = URL(fileURLWithPath: row.source), destURL = URL(fileURLWithPath: row.destination)
        let srcParent = try Directory(sourceURL.deletingLastPathComponent().path)
        guard srcParent.device == row.sourceParentDevice, srcParent.inode == row.sourceParentInode else { throw fail("Source directory changed since preview.") }
        let source = try sourceFD(sourceURL); defer { close(source) }
        guard try Fingerprint(fd: source) == row.fingerprint, try digest(fd: source) == row.hash else { throw fail("Source changed since preview; preview again.") }
        let root = try Directory(plan.mode == .clean ? srcParent.path : plan.profile.root)
        guard root.device == plan.rootDevice, root.inode == plan.rootInode else { throw fail("Destination root/volume changed since preview.") }
        for (path, identity) in row.existingDirectories { let d = try Directory(path); guard d.device == identity.device, d.inode == identity.inode else { throw fail("Destination directory changed since preview.") } }
        try journal.record(plan.id, row: row, state: "Prepared")
        // Open each new directory relative to a verified parent. Never follow links.
        for path in row.newFolders {
            let p = try Directory(URL(fileURLWithPath: path).deletingLastPathComponent().path)
            if let identity = createdDirectories[path] {
                let existing = try Directory(path)
                guard existing.device == identity.device, existing.inode == identity.inode else { throw fail("App-created destination folder was replaced: \(path)") }
            } else {
                guard mkdirat(p.fd, URL(fileURLWithPath: path).lastPathComponent, 0o755) == 0 else { throw fail("New destination folder appeared or cannot be created; preview again: \(path)") }
                let d = try Directory(path)
                createdDirectories[path] = DirectoryIdentity(device: d.device, inode: d.inode)
            }
        }
        let target = try Directory(destURL.deletingLastPathComponent().path)
        try checkCollision(destURL.deletingLastPathComponent(), name: destURL.lastPathComponent)
        guard try Fingerprint(fd: source) == row.fingerprint else { throw fail("Source changed before execution.") }
        if plan.mode != .copy && srcParent.device == target.device && !forceCopyMove {
            try journal.record(plan.id, row: row, state: "Moving", detail: "Exclusive same-volume rename")
            guard renameatx_np(srcParent.fd, sourceURL.lastPathComponent, target.fd, destURL.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw fail("Exclusive rename failed: \(String(cString: strerror(errno)))") }
            let moved = openat(target.fd, destURL.lastPathComponent, O_RDONLY | O_NOFOLLOW)
            guard moved >= 0 else { throw fail("Moved path unavailable; inspect destination: \(row.destination)") }; defer { close(moved) }
            let movedID = try Fingerprint(fd: moved), heldID = try Fingerprint(fd: source)
            guard movedID == heldID, try digest(fd: moved) == row.hash else {
                let restored = renameatx_np(target.fd, destURL.lastPathComponent, srcParent.fd, sourceURL.lastPathComponent, UInt32(RENAME_EXCL)) == 0
                throw fail("Source changed during rename. No deletion. \(restored ? "Restored source." : "Recovery destination: " + row.destination)")
            }
            _ = fsync(srcParent.fd); _ = fsync(target.fd)
            let identity = try Fingerprint(fd: source)
            try journal.record(plan.id, row: row, state: "Moved", identity: identity)
            return
        }
        let tempName = ".library-filer-\(UUID().uuidString).partial"
        let tempPath = destURL.deletingLastPathComponent().appendingPathComponent(tempName).path
        try journal.record(plan.id, row: row, state: "Creating temporary copy", temporary: tempPath)
        let temp = openat(target.fd, tempName, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
        guard temp >= 0 else { throw fail("Cannot exclusively create temporary copy.") }; defer { close(temp) }
        try journal.record(plan.id, row: row, state: "Copying", temporary: tempPath, identity: try Fingerprint(fd: temp))
        guard lseek(source, 0, SEEK_SET) >= 0 else { throw fail("Source seek failed.") }
        // fcopyfile copies payload, stat data, resource forks and extended attributes supported by the target.
        guard fcopyfile(source, temp, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else { throw fail("Copy or metadata preservation failed. Source retained; temporary: \(tempPath)") }
        guard fsync(temp) == 0 else { throw fail("Cannot flush copied file. Source retained; temporary: \(tempPath)") }
        if fault == .afterCopy { throw fail("Injected interruption after copy. Temporary: \(tempPath)") }
        guard fault != .verification, try Fingerprint(fd: temp).size == row.fingerprint?.size, try digest(fd: temp) == row.hash, try Fingerprint(fd: source) == row.fingerprint, try digest(fd: source) == row.hash else { throw fail("Verification failed. Source retained; temporary: \(tempPath)") }
        try journal.record(plan.id, row: row, state: "Publishing verified copy", temporary: tempPath, identity: try Fingerprint(fd: temp))
        let currentRoot = try Directory(plan.mode == .clean ? srcParent.path : plan.profile.root)
        let currentTarget = try Directory(target.path)
        guard currentRoot.matches(root), currentTarget.matches(target) else { throw fail("Destination changed before publication. Source retained; temporary: \(tempPath)") }
        try checkCollision(destURL.deletingLastPathComponent(), name: destURL.lastPathComponent)
        guard renameatx_np(target.fd, tempName, target.fd, destURL.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw fail("Exclusive publish failed. Source retained; temporary: \(tempPath)") }
        _ = fsync(target.fd)
        try journal.record(plan.id, row: row, state: "Copied", detail: plan.mode == .copy ? "Source retained" : "Move pending source removal", identity: try Fingerprint(fd: temp))
        if fault == .afterPublish { throw fail("Injected interruption after publication; both copies retained.") }
        if plan.mode != .copy {
            // Removing an open file by pathname cannot be made conditional on inode on macOS.
            // Claim the exact original through an exclusive rename first; inspect its identity before unlinking.
            guard fault != .beforeDelete, try Fingerprint(fd: source) == row.fingerprint, try digest(fd: source) == row.hash else { throw fail("Source revalidation failed; verified destination and source retained.") }
            let holding = ".library-filer-source-\(UUID().uuidString)"
            let holdingPath = sourceURL.deletingLastPathComponent().appendingPathComponent(holding).path
            try journal.record(plan.id, row: row, state: "Claiming source for removal", temporary: holdingPath, identity: try Fingerprint(fd: source))
            guard renameatx_np(srcParent.fd, sourceURL.lastPathComponent, srcParent.fd, holding, UInt32(RENAME_EXCL)) == 0 else { throw fail("Cannot claim source; destination copied, move incomplete.") }
            let claimed = openat(srcParent.fd, holding, O_RDONLY | O_NOFOLLOW)
            guard claimed >= 0 else { throw fail("Claimed source unavailable at \(holdingPath); inspect recovery.") }; defer { close(claimed) }
            let claimedID = try Fingerprint(fd: claimed), openID = try Fingerprint(fd: source)
            guard claimedID == openID, try digest(fd: claimed) == row.hash else {
                let restored = renameatx_np(srcParent.fd, holding, srcParent.fd, sourceURL.lastPathComponent, UInt32(RENAME_EXCL)) == 0
                throw fail("Source identity changed; no deletion. \(restored ? "Restored original path." : "Recovery file: " + holdingPath)")
            }
            try journal.record(plan.id, row: row, state: "Removing verified claimed source", temporary: holdingPath, identity: claimedID)
            guard unlinkat(srcParent.fd, holding, 0) == 0 else { throw fail("Verified copy published, source retained at \(holdingPath).") }
            _ = fsync(srcParent.fd)
            try journal.record(plan.id, row: row, state: "Moved", identity: try Fingerprint(fd: temp))
        }
    }
    public func undo(_ event: Event, allowDeleteCopy: Bool) throws {
        guard ["Copied", "Moved"].contains(event.state), event.resultIdentity != nil else { throw fail("This event cannot be automatically undone.") }
        let row = event.row; let dest = URL(fileURLWithPath: row.destination); let parent = try Directory(dest.deletingLastPathComponent().path)
        let fd = try sourceFD(dest); defer { close(fd) }
        guard try Fingerprint(fd: fd) == event.resultIdentity, try digest(fd: fd) == row.hash else { throw fail("Destination changed; undo refused.") }
        let all = try journal.events()
        guard !all.contains(where: { $0.operation == event.operation && $0.row.id == row.id && ($0.state == "Undone" || ($0.date > event.date && $0.state == "Moved")) }) else { throw fail("This event was superseded or undone.") }
        // Use the same exclusive rename to claim the item before any guarded copy deletion.
        if event.state == "Copied" {
            guard allowDeleteCopy else { throw fail("Deleting a completed copy requires explicit confirmation.") }
            let holding = ".library-filer-undo-\(UUID().uuidString)"
            let path = dest.deletingLastPathComponent().appendingPathComponent(holding).path
            try journal.record(event.operation, row: row, state: "Undo claiming copy", temporary: path, identity: event.resultIdentity)
            guard renameatx_np(parent.fd, dest.lastPathComponent, parent.fd, holding, UInt32(RENAME_EXCL)) == 0 else { throw fail("Cannot claim destination for undo.") }
            let check = openat(parent.fd, holding, O_RDONLY | O_NOFOLLOW)
            guard check >= 0 else { throw fail("Undo requires recovery at \(path)") }; defer { close(check) }
            let actual = try Fingerprint(fd: check), expected = try Fingerprint(fd: fd)
            guard actual == expected, try digest(fd: check) == row.hash else {
                let restored = renameatx_np(parent.fd, holding, parent.fd, dest.lastPathComponent, UInt32(RENAME_EXCL)) == 0
                throw fail("Undo identity mismatch. \(restored ? "Destination restored." : "Inspect: " + path)")
            }
            guard unlinkat(parent.fd, holding, 0) == 0 else { throw fail("Undo copy remains at \(path)") }
        } else {
            let src = URL(fileURLWithPath: row.source), original = try Directory(src.deletingLastPathComponent().path)
            guard original.device == parent.device else { throw fail("Cross-volume move undo requires a new reviewed operation. No files changed.") }
            guard original.device == row.sourceParentDevice, original.inode == row.sourceParentInode else { throw fail("Original directory changed; undo refused.") }
            try checkCollision(src.deletingLastPathComponent(), name: src.lastPathComponent)
            try journal.record(event.operation, row: row, state: "Undo moving")
            guard renameatx_np(parent.fd, dest.lastPathComponent, original.fd, src.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw fail("Undo exclusive move failed.") }
            _ = fsync(original.fd)
        }
        _ = fsync(parent.fd)
        try journal.record(event.operation, row: row, state: "Undone")
    }
}
