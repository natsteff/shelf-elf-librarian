import Foundation
import Darwin

public enum LibraryStorage {
    public static let smbNotice = "SMB network library: Interrupted transfers may leave incomplete destination files. Move sources are deleted only after verification. Existing files will not be overwritten."
    public static func availableBytes(_ path: String) throws -> UInt64 {
        var info = statfs()
        guard statfs(path, &info) == 0 else {
            throw fail("Cannot check library free space: " + String(cString: strerror(errno)) + ". No files transferred.")
        }
        let result = UInt64(info.f_bavail).multipliedReportingOverflow(by: UInt64(info.f_bsize))
        guard info.f_bsize > 0, !result.overflow else { throw fail("Library free space could not be determined. No files transferred.") }
        return result.partialValue
    }
    public static func isSMB(_ path: String) -> Bool {
        guard !path.isEmpty else { return false }
        var info = statfs()
        guard statfs(path, &info) == 0 else { return false }
        return withUnsafeBytes(of: info.f_fstypename) { bytes in
            String(cString: bytes.baseAddress!.assumingMemoryBound(to: CChar.self)) == "smbfs"
        }
    }
}
