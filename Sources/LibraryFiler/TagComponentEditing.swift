import Foundation
import FilerCore

extension Model {
    func useMP3Tag(_ tag: EmbeddedTag, for id: String) {
        guard !busy, let index = items.firstIndex(where: { $0.id == id }), items[index].url.pathExtension.lowercased() == "mp3" else { return }
        do {
            let value = try EmbeddedMetadata.fieldValue(tag)
            guard let key = tag.component else { return }
            if tagEditsBefore[id] == nil { tagEditsBefore[id] = items[index] }
            FieldCatalog.set(key, value, &items[index].fields)
            items[index].fields.artist = RuleEngine.artistName(items[index].fields.artist, profile: active)
            items[index].overrideBasename = nil; items[index].reviewed = false
            invalidate()
        } catch { self.error = error.localizedDescription }
    }
    func cancelTagEdits(_ id: String) {
        if let before = tagEditsBefore.removeValue(forKey: id), let i = items.firstIndex(where: { $0.id == id }) { items[i] = before; invalidate() }
        if filenameFocusID == id { filenameFocusID = nil }
    }
    func reviewTagProposal(_ id: String) {
        filenameFocusID = id; filenameFocusRequest = UUID()
    }
}
