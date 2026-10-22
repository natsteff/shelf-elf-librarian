import SwiftUI
import AppKit
import FilerCore

/// Receives contextual clicks on unknown source words only. Ordinary clicks and hover pass through.
struct SpellingContextMenu: NSViewRepresentable {
    let text: String
    let words: [FilenameSpellingWord]
    let bold: Set<Int>
    let choose: (String, String?) -> Void
    func makeNSView(context: Context) -> SpellingContextView { SpellingContextView() }
    func updateNSView(_ view: SpellingContextView, context: Context) {
        view.text = text; view.words = words; view.bold = bold; view.choose = choose
    }
}
final class SpellingContextView: NSView {
    var text = ""
    var words: [FilenameSpellingWord] = []
    var bold: Set<Int> = []
    var choose: ((String, String?) -> Void)?
    override var isFlipped: Bool { true }
    private func word(at point: NSPoint) -> String? {
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        var offset = 0
        for (index, character) in text.enumerated() {
            let length = String(character).utf16.count
            if bold.contains(index) { storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 14), range: NSRange(location: offset, length: length)) }
            offset += length
        }
        let layout = NSLayoutManager(), container = NSTextContainer(size: NSSize(width: max(1, bounds.width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0; storage.addLayoutManager(layout); layout.addTextContainer(container)
        layout.ensureLayout(for: container)
        let glyph = layout.glyphIndex(for: point, in: container)
        guard glyph < layout.numberOfGlyphs,
              layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(point) else { return nil }
        let character = layout.characterIndexForGlyph(at: glyph)
        return words.first { NSLocationInRange(character, $0.range) }?.word
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control)),
              word(at: convert(point, from: superview)) != nil else { return nil }
        return self
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let word = word(at: convert(event.locationInWindow, from: nil)) else { return nil }
        HoverHelp.shared.hide()
        let menu = NSMenu(title: "Spelling suggestions")
        let title = NSMenuItem(title: "Suggestions for “\(word)”", action: nil, keyEquivalent: ""); title.isEnabled = false; menu.addItem(title)
        let guesses = FilenameSpellChecker.shared.suggestions(for: word)
        if guesses.isEmpty { let empty = NSMenuItem(title: "No suggestions found", action: nil, keyEquivalent: ""); empty.isEnabled = false; menu.addItem(empty) }
        for guess in guesses { menu.addItem(SpellingMenuItem(guess) { [weak self] in self?.choose?(word, guess) }) }
        menu.addItem(.separator())
        menu.addItem(SpellingMenuItem("Enter replacement…") { [weak self] in self?.choose?(word, nil) })
        return menu
    }
}
private final class SpellingMenuItem: NSMenuItem {
    let perform: () -> Void
    init(_ title: String, perform: @escaping () -> Void) {
        self.perform = perform; super.init(title: title, action: #selector(invoke), keyEquivalent: ""); target = self
    }
    required init(coder: NSCoder) { fatalError("Not used") }
    @objc private func invoke() { perform() }
}
