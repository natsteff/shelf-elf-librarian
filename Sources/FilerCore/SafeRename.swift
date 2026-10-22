import Foundation
import Darwin

// All mutations use no-replace renames. The caller supplies a frozen-identity/content verifier.
// Case-only names use a journaled intermediate so case-insensitive volumes do not overwrite the source.
public func exclusivePathRename(source: URL, destination: URL, faultAfterStage: Bool = false,
    verify: (URL) throws -> Void, record: (String, String?) throws -> Void) throws {
    let from = try Directory(source.deletingLastPathComponent().path)
    let to = try Directory(destination.deletingLastPathComponent().path)
    let isCaseOnly = source.path != destination.path && collisionKey(source.path) == collisionKey(destination.path) && from.matches(to)
    try checkCollision(destination.deletingLastPathComponent(), name: destination.lastPathComponent, excluding: isCaseOnly ? source.lastPathComponent : nil)
    try verify(source)
    if !isCaseOnly {
        try record("Exclusive rename prepared", nil)
        guard renameatx_np(from.fd, source.lastPathComponent, to.fd, destination.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw fail("Exclusive rename failed: \(String(cString: strerror(errno)))") }
        _ = fsync(from.fd); _ = fsync(to.fd)
        do { try verify(destination) }
        catch {
            try record("Rename validation failed; rollback requested", destination.path)
            let restored = renameatx_np(to.fd, destination.lastPathComponent, from.fd, source.lastPathComponent, UInt32(RENAME_EXCL)) == 0
            _ = fsync(from.fd); _ = fsync(to.fd)
            throw fail("Rename validation failed. \(restored ? "Restored original location." : "Rollback blocked; retained at: " + destination.path) \(error.localizedDescription)")
        }
        return
    }
    let temporaryName = ".shelf-elf-case-\(UUID().uuidString)"
    let temporary = source.deletingLastPathComponent().appendingPathComponent(temporaryName)
    try record("Case rename prepared", temporary.path)
    guard renameatx_np(from.fd, source.lastPathComponent, from.fd, temporaryName, UInt32(RENAME_EXCL)) == 0 else { throw fail("Cannot claim case-only rename; no overwrite performed.") }
    _ = fsync(from.fd)
    do { try record("Case rename staged", temporary.path) }
    catch { throw fail("Journal write failed after staging. Recovery file/folder: \(temporary.path)") }
    if faultAfterStage { throw fail("Injected interruption after case staging. Recovery file/folder: \(temporary.path)") }
    do {
        try verify(temporary)
        try checkCollision(destination.deletingLastPathComponent(), name: destination.lastPathComponent)
        try record("Publishing case rename", temporary.path)
        guard renameatx_np(from.fd, temporaryName, to.fd, destination.lastPathComponent, UInt32(RENAME_EXCL)) == 0 else { throw fail("Exclusive case publication failed.") }
    } catch {
        let restored = renameatx_np(from.fd, temporaryName, from.fd, source.lastPathComponent, UInt32(RENAME_EXCL)) == 0
        _ = fsync(from.fd)
        throw fail("\(error.localizedDescription) \(restored ? "Original location restored." : "Rollback blocked; recovery path: " + temporary.path)")
    }
    _ = fsync(from.fd); _ = fsync(to.fd)
    do { try verify(destination) }
    catch { throw fail("Case rename needs recovery at \(destination.path): \(error.localizedDescription)") }
}
