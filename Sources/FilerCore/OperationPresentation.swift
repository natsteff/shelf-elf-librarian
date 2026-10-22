import Foundation

public struct DestinationPreviewGroup: Identifiable {
    public var id: String
    public var title: String
    public var rows: [PlanRow]
    public var blocked: Bool
}
public enum OperationPresentation {
    public static func groups(_ plan: Plan) -> [DestinationPreviewGroup] {
        var folders: [String: [PlanRow]] = [:]
        let blocked = plan.rows.filter { !$0.actionable }
        for row in plan.rows where row.actionable {
            folders[URL(fileURLWithPath: row.destination).deletingLastPathComponent().path, default: []].append(row)
        }
        let root = plan.profile.root
        func sorted(_ rows: [PlanRow]) -> [PlanRow] {
            rows.sorted {
                let order = URL(fileURLWithPath: $0.destination).lastPathComponent.localizedStandardCompare(URL(fileURLWithPath: $1.destination).lastPathComponent)
                return order == .orderedSame ? $0.source.localizedStandardCompare($1.source) == .orderedAscending : order == .orderedAscending
            }
        }
        var result = folders.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { folder in
            let relative = folder == root ? "Library root" : folder.hasPrefix(root + "/") ? String(folder.dropFirst(root.count + 1)).components(separatedBy: "/").joined(separator: " / ") : folder
            return DestinationPreviewGroup(id: folder, title: relative, rows: sorted(folders[folder] ?? []), blocked: false)
        }
        if !blocked.isEmpty { result.append(DestinationPreviewGroup(id: "@blocked", title: "Needs attention", rows: sorted(blocked), blocked: true)) }
        return result
    }
    /// Events are newest-first. A failed copy publication or incomplete move is not success.
    public static func completedSources(plan: Plan, events: [Event]) -> Set<String> {
        var seen = Set<UUID>(), completed = Set<String>()
        for event in events where event.operation == plan.id {
            guard seen.insert(event.row.id).inserted else { continue }
            if event.state == (plan.mode == .copy ? "Copied" : "Moved") { completed.insert(event.row.source) }
        }
        return completed
    }
    /// Preserve all edits/review state for surviving source paths; new files use fresh interpretation.
    public static func reconcile(existing: [Item], scanned: [Item], selected: Set<String>, completed: Set<String>, rememberNew: Bool) -> (items: [Item], selected: Set<String>) {
        let before = Dictionary(uniqueKeysWithValues: existing.filter { !completed.contains($0.id) }.map { ($0.id, $0) })
        let items = scanned.map { fresh in
            if var prior = before[fresh.id] { prior.size = fresh.size; prior.url = fresh.url; return prior }
            var added = fresh; added.rememberCorrection = rememberNew; return added
        }
        return (items, selected.subtracting(completed).intersection(Set(items.map(\.id))))
    }
}
