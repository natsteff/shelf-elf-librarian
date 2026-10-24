import Foundation
import Darwin

@_silgen_name("sqlite3_open") private func sqlOpen(_ path: UnsafePointer<CChar>!, _ db: UnsafeMutablePointer<OpaquePointer?>!) -> Int32
@_silgen_name("sqlite3_close") private func sqlClose(_ db: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_exec") private func sqlExec(_ db: OpaquePointer!, _ sql: UnsafePointer<CChar>!, _ cb: UnsafeMutableRawPointer?, _ ctx: UnsafeMutableRawPointer?, _ err: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32
@_silgen_name("sqlite3_prepare_v2") private func sqlPrepare(_ db: OpaquePointer!, _ sql: UnsafePointer<CChar>!, _ n: Int32, _ statement: UnsafeMutablePointer<OpaquePointer?>!, _ tail: UnsafeMutablePointer<UnsafePointer<CChar>?>?) -> Int32
@_silgen_name("sqlite3_step") private func sqlStep(_ s: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_finalize") private func sqlFinalize(_ s: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_changes") private func sqlChanges(_ db: OpaquePointer!) -> Int32
@_silgen_name("sqlite3_column_text") private func sqlText(_ s: OpaquePointer!, _ i: Int32) -> UnsafePointer<UInt8>!
public struct Event: Codable, Identifiable {
    public var id = UUID(); public var date = Date(); public var operation: UUID; public var row: PlanRow; public var state: String; public var detail: String; public var temporary: String?
    public var resultIdentity: Fingerprint?
    public var hasMagicTagChanges: Bool { row.magicMP3?.willChange == true }
}
public final class Journal {
    private var db: OpaquePointer?
    public init(url: URL) throws {
        guard sqlOpen(url.path, &db) == 0 else { throw fail("Cannot open journal.") }
        try exec("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS events (seq INTEGER PRIMARY KEY, json TEXT NOT NULL); CREATE TABLE IF NOT EXISTS plans (id TEXT PRIMARY KEY, json TEXT NOT NULL); CREATE TABLE IF NOT EXISTS folder_events (seq INTEGER PRIMARY KEY, json TEXT NOT NULL); CREATE TABLE IF NOT EXISTS remembered_corrections (id TEXT PRIMARY KEY, json TEXT NOT NULL);")
    }
    deinit { _ = sqlClose(db) }
    private func quoted(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "''") + "'" }
    private func exec(_ sql: String) throws { guard sqlExec(db, sql, nil, nil, nil) == 0 else { throw fail("Journal write failed; operation stopped.") } }
    /// Prune records only. Never remove any source, destination or recovery file.
    public func pruneHistory(now: Date = Date()) throws {
        let cutoff = now.addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSinceReferenceDate
        try exec("BEGIN IMMEDIATE")
        var removed = 0
        do {
            let all = try events()
            let oldCorrections = Set(all.filter { $0.date.timeIntervalSinceReferenceDate < cutoff }.compactMap { $0.row.correction?.id })
            for correction in Learning.observations(events: all) where correction.remember && oldCorrections.contains(correction.id) {
                let json = String(decoding: try JSONEncoder().encode(correction), as: UTF8.self)
                try exec("INSERT OR IGNORE INTO remembered_corrections VALUES (\(quoted(correction.id.uuidString)), \(quoted(json)))")
            }
            for table in ["events", "folder_events"] {
                try exec("DELETE FROM \(table) WHERE json_extract(json, '$.date') < \(cutoff)"); removed += Int(sqlChanges(db))
            }
            try exec("DELETE FROM plans WHERE json_extract(json, '$.created') < \(cutoff) AND id NOT IN (SELECT json_extract(json, '$.operation') FROM events)")
            removed += Int(sqlChanges(db)); try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
        if removed > 0 { try? exec("VACUUM"); try? exec("PRAGMA wal_checkpoint(TRUNCATE)") }
    }
    public func rememberedCorrections() throws -> [ConfirmedCorrection] {
        var stmt: OpaquePointer?
        guard sqlPrepare(db, "SELECT json FROM remembered_corrections", -1, &stmt, nil) == 0 else { throw fail("Remembered corrections could not be loaded.") }
        defer { _ = sqlFinalize(stmt) }; var result: [ConfirmedCorrection] = []
        while sqlStep(stmt) == 100 { if let text = sqlText(stmt, 0) { result.append(try JSONDecoder().decode(ConfirmedCorrection.self, from: Data(String(cString: text).utf8))) } }
        return result
    }
    public func plan(_ p: Plan) throws { let data = try JSONEncoder().encode(p); try exec("INSERT INTO plans VALUES (\(quoted(p.id.uuidString)), \(quoted(String(decoding: data, as: UTF8.self))));") }
    public func record(_ op: UUID, row: PlanRow, state: String, detail: String = "", temporary: String? = nil, identity: Fingerprint? = nil, date: Date = Date()) throws {
        var e = Event(operation: op, row: row, state: state, detail: detail, temporary: temporary, resultIdentity: identity)
        e.date = date
        let data = try JSONEncoder().encode(e); try exec("INSERT INTO events(json) VALUES (\(quoted(String(decoding: data, as: UTF8.self))));")
    }
    public func recordFolder(_ event: FolderEvent) throws {
        let data = try JSONEncoder().encode(event)
        try exec("INSERT INTO folder_events(json) VALUES (\(quoted(String(decoding: data, as: UTF8.self))));")
    }
    public func folderEvents() throws -> [FolderEvent] {
        var stmt: OpaquePointer?
        guard sqlPrepare(db, "SELECT json FROM folder_events ORDER BY seq DESC", -1, &stmt, nil) == 0 else { throw fail("Folder journal read failed.") }
        defer { _ = sqlFinalize(stmt) }
        var result: [FolderEvent] = []
        while sqlStep(stmt) == 100 { if let text = sqlText(stmt, 0) { result.append(try JSONDecoder().decode(FolderEvent.self, from: Data(String(cString: text).utf8))) } }
        return result
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
public enum Fault: String { case none, afterCopy, verification, afterPublish, beforeDelete, afterCaseStage, magicTagFailure, magicPurgeFailure }
public struct ExecutionResult { public var completed = 0; public var failed = 0; public var details: [String] = [] }
public final class Executor {
    public let journal: Journal
    public init(journal: Journal) { self.journal = journal }
    public func execute(_ plan: Plan, cancel: Cancellation = Cancellation(), fault: Fault = .none, forceCopyMoveForTests: Bool = false, forceSMBForTests: Bool = false, availableSMBBytesForTests: UInt64? = nil, progress: (Int, Int) -> Void = { _, _ in }) throws -> ExecutionResult {
        if plan.mode != .clean && (forceSMBForTests || LibraryStorage.isSMB(plan.profile.root)) {
            // Estimate the whole batch, including staging plus final output for tag-changing files.
            // This is a preflight guard, not a reservation; runtime verification remains mandatory.
            var required: UInt64 = 0
            for row in plan.rows.filter(\.actionable) {
                let size = UInt64(max(0, row.fingerprint?.size ?? 0))
                let bytes = size.multipliedReportingOverflow(by: row.magicMP3?.willChange == true ? 2 : 1)
                let total = required.addingReportingOverflow(bytes.partialValue)
                guard !bytes.overflow, !total.overflow else { throw fail("Transfer size exceeds the supported space estimate. No files transferred.") }
                required = total.partialValue
            }
            let available = try availableSMBBytesForTests ?? LibraryStorage.availableBytes(plan.profile.root)
            guard available >= required else {
                throw fail("Not enough reported free space on the SMB library. Estimated need: \(required.formatted()) bytes; available: \(available.formatted()) bytes. No files transferred; sources retained.")
            }
        }
        try journal.plan(plan)
        var createdDirectories: [String: DirectoryIdentity] = [:]
        var result = ExecutionResult(); let rows = plan.rows.filter(\.actionable)
        for (i, row) in rows.enumerated() {
            if cancel.cancelled { result.details.append("Cancelled between files. Completed files remain completed."); break }
            do { try run(row, plan: plan, fault: fault, forceCopyMove: forceCopyMoveForTests, forceSMB: forceSMBForTests, createdDirectories: &createdDirectories); result.completed += 1 }
            catch { result.failed += 1; result.details.append("\(row.source): \(error.localizedDescription)"); try journal.record(plan.id, row: row, state: "Failed / inspect recovery", detail: error.localizedDescription) }
            progress(i + 1, rows.count)
        }
        return result
    }
    private func run(_ row: PlanRow, plan: Plan, fault: Fault, forceCopyMove: Bool, forceSMB: Bool, createdDirectories: inout [String: DirectoryIdentity]) throws {
        let sourceURL = URL(fileURLWithPath: row.source), destURL = URL(fileURLWithPath: row.destination)
        let srcParent = try Directory(sourceURL.deletingLastPathComponent().path)
        guard srcParent.device == row.sourceParentDevice, srcParent.inode == row.sourceParentInode else { throw fail("Source directory changed since preview.") }
        let source = try sourceFD(sourceURL); defer { close(source) }
        guard try Fingerprint(fd: source) == row.fingerprint, try digest(fd: source) == row.hash else { throw fail("Source changed since preview; preview again.") }
        let root = try Directory(plan.mode == .clean ? srcParent.path : plan.profile.root)
        guard plan.mode == .clean || (root.device == plan.rootDevice && root.inode == plan.rootInode) else { throw fail("Destination root/volume changed since preview.") }
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
        try checkCollision(destURL.deletingLastPathComponent(), name: destURL.lastPathComponent, excluding: row.caseOnly == true ? sourceURL.lastPathComponent : nil)
        guard try Fingerprint(fd: source) == row.fingerprint else { throw fail("Source changed before execution.") }
        let smb = forceSMB || LibraryStorage.isSMB(target.path)
        let magicTagChanges = row.magicMP3?.willChange == true
        let directSMB = smb && !magicTagChanges
        if plan.mode != .copy && srcParent.device == target.device && !forceCopyMove && !magicTagChanges && !smb {
            try exclusivePathRename(source: sourceURL, destination: destURL, faultAfterStage: fault == .afterCaseStage, verify: { url in
                let check = try sourceFD(url); defer { close(check) }
                let actual = try Fingerprint(fd: check), held = try Fingerprint(fd: source)
                guard actual == held, try digest(fd: check) == row.hash else { throw fail("Source identity/content changed during rename.") }
            }, record: { state, temporary in
                try self.journal.record(plan.id, row: row, state: state, temporary: temporary, identity: try Fingerprint(fd: source))
            })
            let identity = try Fingerprint(fd: source)
            try journal.record(plan.id, row: row, state: "Moved", identity: identity)
            return
        }
        let tempName = directSMB ? destURL.lastPathComponent : ".library-filer-\(UUID().uuidString).partial"
        let tempPath = destURL.deletingLastPathComponent().appendingPathComponent(tempName).path
        try journal.record(plan.id, row: row, state: directSMB ? "Creating SMB destination" : "Creating temporary copy", temporary: tempPath)
        var temp = openat(target.fd, tempName, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
        guard temp >= 0 else { throw fail("Cannot exclusively create copy: \(String(cString: strerror(errno))). Source retained; destination: \(tempPath)") }; defer { if temp >= 0 { close(temp) } }
        try journal.record(plan.id, row: row, state: "Copying", temporary: tempPath, identity: try Fingerprint(fd: temp))
        guard lseek(source, 0, SEEK_SET) >= 0 else { throw fail("Source seek failed.") }
        // fcopyfile copies payload, stat data, resource forks and extended attributes supported by the target.
        guard fcopyfile(source, temp, nil, copyfile_flags_t(COPYFILE_ALL)) == 0 else { throw fail("Copy or metadata preservation failed. Source retained; recovery file: \(tempPath)") }
        guard fsync(temp) == 0 else { throw fail("Cannot flush copied file. Source retained; recovery file: \(tempPath)") }
        if fault == .afterCopy { throw fail("Injected interruption after copy. Temporary: \(tempPath)") }
        guard fault != .verification, try Fingerprint(fd: temp).size == row.fingerprint?.size, try digest(fd: temp) == row.hash, try Fingerprint(fd: source) == row.fingerprint, try digest(fd: source) == row.hash else { throw fail("Verification failed. Source retained; recovery file: \(tempPath)") }
        var completedRow = row
        if magicTagChanges, let recipe = row.magicMP3 {
            try journal.record(plan.id, row: row, state: "Preparing Magic MP3 tags", detail: (recipe.update ? "Update tags. " : "") + (recipe.purge ? "Purge unchecked tags. " : "") + "Prepared before library publication. No tag Undo or retained backup.", temporary: tempPath)
            guard fault != .magicTagFailure else { throw fail("Injected Magic tag failure. Library file not published; workspace source retained.") }
            close(temp); temp = -1
            do { try MP3TagWriter.executeMagic(recipe, temporary: URL(fileURLWithPath: tempPath), failBeforePurge: fault == .magicPurgeFailure) }
            catch { throw fail("Magic MP3 preparation failed; workspace source retained and final library file not published. Staging file: " + tempPath + ". " + error.localizedDescription) }
            temp = try sourceFD(URL(fileURLWithPath: tempPath))
            completedRow.hash = try digest(fd: temp)
            guard try Fingerprint(fd: source) == row.fingerprint, try digest(fd: source) == row.hash else { throw fail("Source changed during library preparation; no library file published. Temporary: \(tempPath)") }
        }
        try journal.record(plan.id, row: row, state: "Publishing verified copy", temporary: tempPath, identity: try Fingerprint(fd: temp))
        let currentRoot = try Directory(plan.mode == .clean ? srcParent.path : plan.profile.root)
        let currentTarget = try Directory(target.path)
        guard currentRoot.matches(root), currentTarget.matches(target) else { throw fail("Destination changed before publication. Source retained; recovery file: \(tempPath)") }
        if !directSMB {
            try checkCollision(destURL.deletingLastPathComponent(), name: destURL.lastPathComponent)
            if smb {
                // Magic tags are prepared privately before copying to an exclusively created final name.
                try journal.record(plan.id, row: completedRow, state: "Copying prepared SMB file", detail: "Staging: " + tempPath, temporary: destURL.path)
                let published = openat(target.fd, destURL.lastPathComponent, O_CREAT | O_EXCL | O_RDWR | O_NOFOLLOW, 0o600)
                guard published >= 0 else { throw fail("SMB destination creation failed: \(String(cString: strerror(errno))). Source retained; staging: \(tempPath)") }
                defer { close(published) }
                guard lseek(temp, 0, SEEK_SET) >= 0,
                      fcopyfile(temp, published, nil, copyfile_flags_t(COPYFILE_ALL)) == 0,
                      fsync(published) == 0 else { throw fail("SMB copy failed. Source and staging retained: \(tempPath). Inspect incomplete destination: \(destURL.path)") }
                guard try digest(fd: published) == completedRow.hash else { throw fail("SMB verification failed. Source retained; inspect destination: \(destURL.path). Staging: \(tempPath)") }
                close(temp); temp = dup(published)
                guard temp >= 0 else { throw fail("Cannot retain verified SMB destination handle. Source retained.") }
                _ = unlinkat(target.fd, tempName, 0)
            } else {
                guard renameatx_np(target.fd, tempName, target.fd, destURL.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw fail("Exclusive publish failed: \(String(cString: strerror(errno))). Source retained; recovery file: \(tempPath)") }
            }
        }
        let publishedCheck = try sourceFD(destURL); defer { close(publishedCheck) }
        guard try Fingerprint(fd: publishedCheck) == Fingerprint(fd: temp),
              try digest(fd: publishedCheck) == completedRow.hash,
              try Fingerprint(fd: source) == row.fingerprint,
              try digest(fd: source) == row.hash else { throw fail("Publication/source verification failed. Source retained; inspect destination: \(destURL.path)") }
        _ = fsync(target.fd)
        try journal.record(plan.id, row: completedRow, state: "Copied", detail: plan.mode == .copy ? "Source retained" : "Move pending source removal", identity: try Fingerprint(fd: temp))
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
            try journal.record(plan.id, row: completedRow, state: "Moved", identity: try Fingerprint(fd: temp))
        }
    }
    public func recoverCaseStage(_ event: Event) throws {
        guard event.state == "Case rename staged", let path = event.temporary,
            URL(fileURLWithPath: path).lastPathComponent.hasPrefix(".shelf-elf-case-"), let expected = event.resultIdentity else { throw fail("This event is not a staged file rename.") }
        let staged = URL(fileURLWithPath: path), original = URL(fileURLWithPath: event.row.source)
        guard staged.deletingLastPathComponent().path == original.deletingLastPathComponent().path else { throw fail("Recovery path is outside the original parent.") }
        let parent = try Directory(original.deletingLastPathComponent().path)
        guard parent.device == event.row.sourceParentDevice, parent.inode == event.row.sourceParentInode else { throw fail("Recovery parent changed.") }
        let fd = try sourceFD(staged); defer { close(fd) }
        guard try Fingerprint(fd: fd) == expected, try digest(fd: fd) == event.row.hash else { throw fail("Staged file changed; recovery refused.") }
        try exclusivePathRename(source: staged, destination: original, verify: { url in
            let check = try sourceFD(url); defer { close(check) }
            guard try Fingerprint(fd: check) == Fingerprint(fd: fd), try digest(fd: check) == event.row.hash else { throw fail("Recovery identity/content changed.") }
        }, record: { state, temporary in
            try self.journal.record(event.operation, row: event.row, state: "Recovery: " + state, temporary: temporary, identity: try Fingerprint(fd: fd))
        })
        try journal.record(event.operation, row: event.row, state: "Recovered original location", identity: try Fingerprint(fd: fd))
    }
    public func undo(_ event: Event, allowDeleteCopy: Bool) throws {
        guard !event.hasMagicTagChanges else { throw fail("Magic included MP3 tag changes. This operation has no automatic Undo or retained tag backup.") }
        guard event.date >= Date().addingTimeInterval(-30 * 24 * 60 * 60) else { throw fail("This operation’s 30-day Undo period has expired.") }
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
            try exclusivePathRename(source: dest, destination: src, verify: { url in
                let check = try sourceFD(url); defer { close(check) }
                guard try Fingerprint(fd: check) == Fingerprint(fd: fd), try digest(fd: check) == row.hash else { throw fail("Undo identity/content changed; refusing.") }
            }, record: { state, temporary in
                try self.journal.record(event.operation, row: row, state: "Undo: " + state, temporary: temporary, identity: try Fingerprint(fd: fd))
            })
        }
        _ = fsync(parent.fd)
        try journal.record(event.operation, row: row, state: "Undone")
    }
}
