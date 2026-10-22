import SwiftUI
import AppKit

/// Measures saved content at its actual wrapping width. Editing never makes the form jump.
struct ContentSizedNotesEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NotesScrollView {
        let scroll = NotesScrollView()
        let editor = NSTextView(frame: .zero)
        editor.isRichText = false; editor.allowsUndo = true
        editor.font = .systemFont(ofSize: NSFont.systemFontSize)
        editor.textColor = .labelColor; editor.backgroundColor = .textBackgroundColor
        editor.isHorizontallyResizable = false; editor.isVerticallyResizable = true
        editor.minSize = .zero; editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.autoresizingMask = [.width]
        editor.textContainerInset = NSSize(width: 6, height: 8)
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.containerSize = NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude)
        editor.setAccessibilityLabel("Description / Notes")
        editor.string = text; editor.delegate = context.coordinator
        scroll.documentView = editor; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.borderType = .noBorder; scroll.backgroundColor = .textBackgroundColor
        scroll.snapshot = text
        scroll.measured = { value in DispatchQueue.main.async { height = value } }
        return scroll
    }
    func updateNSView(_ scroll: NotesScrollView, context: Context) {
        context.coordinator.parent = self
        if let editor = scroll.documentView as? NSTextView, editor.string != text {
            editor.string = text; scroll.snapshot = text; scroll.lastWidth = 0; scroll.needsLayout = true
        }
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ContentSizedNotesEditor
        init(_ parent: ContentSizedNotesEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            parent.text = editor.string
        }
    }
    final class NotesScrollView: NSScrollView {
        var snapshot = ""
        var lastWidth: CGFloat = 0
        var measured: ((CGFloat) -> Void)?
        override func layout() {
            super.layout()
            let width = contentSize.width
            guard width > 30, abs(width - lastWidth) > 1 else { return }
            lastWidth = width
            let storage = NSTextStorage(string: snapshot, attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize)])
            let manager = NSLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: width - 12, height: CGFloat.greatestFiniteMagnitude))
            storage.addLayoutManager(manager); manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            measured?(min(300, max(100, ceil(manager.usedRect(for: container).height) + 16)))
        }
    }
}
