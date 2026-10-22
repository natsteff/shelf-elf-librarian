import Foundation
import FilerCore
import Darwin

extension Model {
    func prepareMP3Tags(_ action: MP3TagAction) {
        guard !busy, active.kind == .music, !visibleSelected.isEmpty else { return }
        let chosen = visibleSelected, profile = active
        busy = true; progress = "Preparing MP3 tag review…"; invalidate(); cancellation = Cancellation(); let token = cancellation
        Task {
            let plan = await Task.detached { MP3TagPlan(action: action, profile: profile, items: chosen, cancel: token) }.value
            busy = false; progress = ""
            if token.cancelled { status = "MP3 tag preview cancelled; no files changed."; return }
            mp3TagPlan = plan; showMP3Tags = true
        }
    }
    func applyMP3Tags(_ selection: Set<UUID>) {
        guard !busy, let plan = mp3TagPlan else { return }
        let chosen = plan.files.filter { $0.blocked == nil && $0.changes.contains { selection.contains($0.id) } }
        guard !chosen.isEmpty else { return }
        busy = true; showMP3Tags = false; cancellation = Cancellation(); let token = cancellation
        progress = plan.action == .update ? "Updating MP3 tags…" : "Purging MP3 tags…"
        let db = support.appendingPathComponent("operations.sqlite")
        Task {
            let result = await Task.detached { () -> ([String], [String]) in
                var completed: [String] = [], errors: [String] = []
                do {
                    let journal = try Journal(url: db), operation = UUID()
                    for file in chosen {
                        if token.cancelled { break }
                        let row = MP3TagWriter.historyRow(file)
                        do {
                            try journal.record(operation, row: row, state: "Preparing MP3 tag change", detail: "No Undo or retained backup")
                            try MP3TagWriter.execute(file, action: plan.action, selected: selection)
                            completed.append(file.id)
                            do { try journal.record(operation, row: row, state: plan.action == .update ? "MP3 tags updated" : "MP3 tags purged", detail: "No Undo or retained backup") }
                            catch { errors.append(file.id + ": Tags changed, but history could not be saved. " + error.localizedDescription) }
                        } catch {
                            errors.append(file.id + ": " + error.localizedDescription)
                            try? journal.record(operation, row: row, state: "Failed MP3 tag operation / inspect details", detail: error.localizedDescription)
                        }
                    }
                } catch { errors.append(error.localizedDescription) }
                return (completed, errors)
            }.value
            for id in result.0 {
                if let i = items.firstIndex(where: { $0.id == id }) {
                    items[i].metadata = MP3Metadata.read(items[i].url)
                    items[i].size = Int64((try? items[i].url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                selected.remove(id); tagEditsBefore.removeValue(forKey: id); directRenameUndo.removeValue(forKey: id)
            }
            if !result.1.isEmpty { error = result.1.joined(separator: "\n\n") }
            status = "\(result.0.count) MP3 files changed • \(result.1.count) issues" + (token.cancelled ? " • Cancelled between files" : "")
            busy = false; progress = ""; mp3TagPlan = nil; loadHistory()
        }
    }
}
