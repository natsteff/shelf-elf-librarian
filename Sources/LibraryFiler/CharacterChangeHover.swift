import SwiftUI
import AppKit
import FilerCore

/// Tracking-only overlay: it never intercepts clicks or takes focus from the editor.
struct CharacterChangeHover: NSViewRepresentable {
    let text: String
    let changes: Set<Int>
    let source: Bool
    let fontSize: CGFloat
    var comparison: FilenameDifference? = nil
    func makeNSView(context: Context) -> ChangeTrackingView { ChangeTrackingView() }
    static func dismantleNSView(_ view: ChangeTrackingView, coordinator: ()) { HoverHelp.shared.hide(owner: view) }
    func updateNSView(_ view: ChangeTrackingView, context: Context) {
        if view.text != text || view.changes != changes { HoverHelp.shared.hide(owner: view) }
        view.text = text; view.changes = changes; view.source = source
        view.comparison = comparison
        view.fontSize = fontSize
    }
}
final class ChangeTrackingView: NSView {
    var text = ""
    var changes = Set<Int>()
    var source = false
    var fontSize: CGFloat = 13
    var comparison: FilenameDifference?
    private func callback(_ message: String?) { HoverHelp.shared.show(message, owner: self) }
    private var tracking: NSTrackingArea?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); HoverHelp.shared.hide(owner: self)
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); HoverHelp.shared.hide(owner: self) }
    override func mouseExited(with event: NSEvent) { callback(nil) }
    override func mouseMoved(with event: NSEvent) {
        guard !text.isEmpty, !changes.isEmpty, bounds.width > 0 else { callback(nil); return }
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize)])
        var offsets: [Int] = [], offset = 0
        for (i, character) in text.enumerated() {
            offsets.append(offset)
            let length = String(character).utf16.count
            if changes.contains(i) { storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: fontSize), range: NSRange(location: offset, length: length)) }
            offset += length
        }
        let layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: max(1, bounds.width - (source ? 0 : 12)), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layout); layout.addTextContainer(container); layout.ensureLayout(for: container)
        var point = convert(event.locationInWindow, from: nil)
        if !source { point.x -= 6; point.y -= 4 }
        let glyph = layout.glyphIndex(for: point, in: container)
        guard glyph < layout.numberOfGlyphs, layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).insetBy(dx: -1, dy: -1).contains(point) else { callback(nil); return }
        let char = layout.characterIndexForGlyph(at: glyph)
        guard let index = offsets.lastIndex(where: { $0 <= char }), changes.contains(index) else { callback(nil); return }
        if let message = comparison?.episodeChangeDescription(at: index, sourceSide: source) { callback(message); return }
        if let message = comparison?.preferredCaseDescription(at: index, sourceSide: source) {
            callback(message); return
        }
        let characters = Array(text)
        var start = index, end = index + 1
        let whitespace = characters[index].isWhitespace
        while start > 0 && changes.contains(start - 1) && characters[start - 1].isWhitespace == whitespace { start -= 1 }
        while end < characters.count && changes.contains(end) && characters[end].isWhitespace == whitespace { end += 1 }
        if whitespace {
            callback("\(source ? "Remove" : "Add") \(end - start) whitespace character\(end - start == 1 ? "" : "s").")
        } else {
            callback("\(source ? "Removed or replaced" : "Added or replacement"): “\(String(characters[start..<end]))”.")
        }
    }
}
struct ChangedTextHover: ViewModifier {
    let text: String
    let changes: Set<Int>
    let source: Bool
    let fontSize: CGFloat
    var comparison: FilenameDifference? = nil
    func body(content: Content) -> some View {
        content.overlay { CharacterChangeHover(text: text, changes: changes, source: source, fontSize: fontSize, comparison: comparison) }
    }
}
extension View {
    func changedTextHover(text: String, changes: Set<Int>, source: Bool, fontSize: CGFloat, comparison: FilenameDifference? = nil) -> some View {
        modifier(ChangedTextHover(text: text, changes: changes, source: source, fontSize: fontSize, comparison: comparison))
    }
}
