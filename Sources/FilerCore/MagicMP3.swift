import Foundation
import Darwin

public struct MagicMP3Recipe: Codable {
    public var update: Bool
    public var purge: Bool
    public var keep: Set<MP3KeepTag>
    public var fields: Fields
    public var changes: [String]
    public var willChange: Bool { !changes.isEmpty }
}
public func makeMagicFilingPlan(items: [Item], profile: Profile, mode: Mode, cancel: Cancellation? = nil) throws -> Plan {
    var plan = try makeConfirmedFilingPlan(items: items, profile: profile, mode: mode, keepCurrentNames: false)
    plan.magicRun = true
    if cancel?.cancelled == true { throw fail("Magic preview cancelled; no files changed.") }
    guard profile.kind == .music, profile.magicUpdateMP3Tags == true || profile.magicPurgeMP3Tags == true else { return plan }
    let indexed = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    for i in plan.rows.indices where plan.rows[i].actionable {
        if cancel?.cancelled == true { throw fail("Magic preview cancelled; no files changed.") }
        guard let item = indexed[plan.rows[i].source], item.url.pathExtension.lowercased() == "mp3" else { continue }
        do {
            let recipe = try MP3TagWriter.magicRecipe(item, profile: profile)
            let check = try sourceFD(item.url); defer { close(check) }
            guard try Fingerprint(fd: check) == plan.rows[i].fingerprint, try digest(fd: check) == plan.rows[i].hash else { throw fail("Source changed while preparing Magic. Preview again.") }
            plan.rows[i].magicMP3 = recipe
        } catch {
            plan.rows[i].status = "MP3 tag steps blocked"
            plan.rows[i].explanation += "\n" + error.localizedDescription
        }
    }
    if cancel?.cancelled == true { throw fail("Magic preview cancelled; no files changed.") }
    return plan
}

extension MP3TagWriter {
    static func magicRecipe(_ item: Item, profile: Profile) throws -> MagicMP3Recipe {
        let update = profile.magicUpdateMP3Tags == true, purge = profile.magicPurgeMP3Tags == true
        let keep = profile.mp3TagsToKeep ?? Set(MP3KeepTag.allCases)
        var summary: [String] = []
        if update {
            let preview = self.preview(item, action: .update, keep: keep)
            if let blocked = preview.blocked { throw fail("Update tags: " + blocked) }
            summary += preview.changes.map { "Update " + $0.label + " to “" + String($0.after.prefix(160)) + "”" }
            if purge {
                for change in preview.changes {
                    if let category = MP3KeepTag.allCases.first(where: { $0.component == change.key }), !keep.contains(category) {
                        summary.append("Purge updated " + category.label + " afterward (not in keep list)")
                    }
                }
            }
        }
        if purge {
            let preview = self.preview(item, action: .purge, keep: keep)
            if let blocked = preview.blocked { throw fail("Purge tags: " + blocked) }
            summary += preview.changes.map { "Remove " + String($0.label.prefix(160)) }
        }
        return MagicMP3Recipe(update: update, purge: purge, keep: keep, fields: item.fields, changes: summary)
    }
    /// Only called on Executor's private copy. Never run these steps on a workspace original.
    static func executeMagic(_ recipe: MagicMP3Recipe, temporary: URL, failBeforePurge: Bool = false) throws {
        guard temporary.lastPathComponent.hasPrefix(".library-filer-"), temporary.pathExtension == "partial" else { throw fail("Magic tag preparation requires a private library staging file.") }
        for action in [MP3TagAction.update, .purge] where action == .update ? recipe.update : recipe.purge {
            if action == .purge && failBeforePurge { throw fail("Injected purge failure after private tag update. Workspace source retained; final library file not published.") }
            let item = Item(url: temporary, size: 0, fields: recipe.fields, evidence: "Confirmed Magic components", reviewed: true)
            let preview = previewFile(item, action: action, keep: recipe.keep, temporary: true)
            if let blocked = preview.blocked { throw fail(blocked) }
            try execute(preview, action: action, selected: Set(preview.changes.map(\.id)))
        }
    }
}
