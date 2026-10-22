import AppKit
import SwiftUI

/// Reveals the rendered error after native form layout, including repeated identical failures.
/// The request counter changes on every failed Save; no timing delay is assumed.
struct ValidationScrollAnchor: NSViewRepresentable {
    let request: Int
    func makeNSView(context: Context) -> AnchorView { AnchorView() }
    func updateNSView(_ view: AnchorView, context: Context) {
        view.request = request
        view.scheduleReveal()
    }
    final class AnchorView: NSView {
        var request = 0
        private var revealed = 0
        private var scheduled = false
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); scheduleReveal() }
        override func layout() { super.layout(); scheduleReveal() }
        func scheduleReveal() {
            guard request > revealed, !scheduled else { return }
            scheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.scheduled = false
                guard self.window != nil, self.bounds.height > 0, self.request > self.revealed else { return }
                self.revealed = self.request
                var ancestor = self.superview
                while let current = ancestor {
                    if let scroll = current as? NSScrollView, let document = scroll.documentView {
                        document.scrollToVisible(self.convert(self.bounds, to: document).insetBy(dx: 0, dy: -8))
                        scroll.reflectScrolledClipView(scroll.contentView)
                    }
                    ancestor = current.superview
                }
            }
        }
    }
}
