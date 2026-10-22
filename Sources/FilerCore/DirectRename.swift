import Foundation

/// A direct row action approves only the basename, never the interpretation used for filing.
/// The temporary reviewed flag satisfies the clean planner without mutating the caller's items.
public func makeDirectRenamePlan(items: [Item], profile: Profile) throws -> Plan {
    let approved = try items.compactMap { item -> Item? in
        let filename = try proposedFilename(item, profile: profile)
        guard !filename.utf8.elementsEqual(item.url.lastPathComponent.utf8) else { return nil }
        var copy = item
        copy.reviewed = true
        return copy
    }
    guard !approved.isEmpty else { throw fail("No filename changes to apply.") }
    return try makePlan(items: approved, profile: profile, mode: .clean, category: "", fileOnly: false)
}
