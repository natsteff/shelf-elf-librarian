import SwiftUI
import AppKit
import FilerCore

/// One opaque, non-activating, click-through native panel for all application hover help.
final class HoverHelp {
    static let shared = HoverHelp()
    private let panel: NSPanel
    private let label: NSTextField
    private weak var owner: NSView?
    private var monitor: Any?
    private var observer: NSObjectProtocol?
    private var geometryObservers: [NSObjectProtocol] = []
    private var currentMessage = ""
    private var pending: DispatchWorkItem?
    var timing: HoverTiming = .immediate { didSet { hide() } }
    private init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = true; panel.alphaValue = 1
        panel.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1)
        panel.hasShadow = true; panel.ignoresMouseEvents = true
        panel.level = .popUpMenu; panel.hidesOnDeactivate = true
        label = NSTextField(wrappingLabelWithString: "")
        label.font = .systemFont(ofSize: 12); label.textColor = .black
        let background = OpaqueHelpBackground()
        background.addSubview(label); panel.contentView = background
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type != .mouseMoved { self.hide() }
            else if let owner = self.owner {
                let point = owner.convert(event.locationInWindow, from: nil)
                if event.window !== owner.window || !owner.visibleRect.contains(point) { self.hide() }
            }
            return event
        }
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            geometryObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let changed = note.object as? NSWindow, changed === self.owner?.window else { return }
                self.hide()
            })
        }
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] _ in self?.hide() }
    }
    func show(_ message: String?, owner: NSView) {
        guard timing != .off, let message, !message.isEmpty, owner.window?.isKeyWindow == true else { hide(owner: owner); return }
        if self.owner === owner && currentMessage == message && (panel.isVisible || pending != nil) { return }
        hide()
        self.owner = owner; currentMessage = message
        if timing == .shortDelay {
            let work = DispatchWorkItem { [weak self, weak owner] in
                guard let self, let owner, self.owner === owner, owner.window?.isKeyWindow == true,
                      let window = owner.window,
                      owner.visibleRect.contains(owner.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)) else { self?.hide(); return }
                self.pending = nil
                self.present(message, owner: owner)
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        } else { present(message, owner: owner) }
    }
    private func present(_ message: String, owner: NSView) {
        label.stringValue = message
        guard let window = owner.window else { return }
        let screen = window.screen?.visibleFrame ?? window.frame
        let bounds = window.frame.intersection(screen).insetBy(dx: 12, dy: 12)
        guard bounds.width > 30, bounds.height > 30 else { hide(); return }
        let maximumWidth = min(CGFloat(340), bounds.width)
        let natural = (message as NSString).size(withAttributes: [.font: label.font!]).width
        let width = min(maximumWidth, max(CGFloat(60), ceil(natural) + 24))
        let rect = (message as NSString).boundingRect(with: NSSize(width: width - 20, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: label.font!])
        let height = min(bounds.height, ceil(rect.height) + 22)
        let mouse = NSEvent.mouseLocation
        let x = max(bounds.minX, min(mouse.x + 12, bounds.maxX - width))
        var y = mouse.y - height - 18
        if y < bounds.minY { y = mouse.y + 20 }
        y = max(bounds.minY, min(y, bounds.maxY - height))
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        label.frame = NSRect(x: 10, y: 10, width: width - 20, height: height - 20)
        panel.orderFrontRegardless()
    }
    func hide(owner: NSView? = nil) {
        if let owner, self.owner !== owner { return }
        pending?.cancel(); pending = nil
        panel.orderOut(nil); self.owner = nil; currentMessage = ""
    }
}
private final class OpaqueHelpBackground: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.97, alpha: 1).setFill(); bounds.fill()
        NSColor(calibratedWhite: 0.55, alpha: 1).setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
    }
}
struct HelpRegion: NSViewRepresentable {
    let message: String
    func makeNSView(context: Context) -> HelpRegionView { HelpRegionView() }
    func updateNSView(_ view: HelpRegionView, context: Context) {
        if view.message != message { HoverHelp.shared.hide(owner: view) }
        view.message = message
    }
    static func dismantleNSView(_ view: HelpRegionView, coordinator: ()) { HoverHelp.shared.hide(owner: view) }
}
final class HelpRegionView: NSView {
    var message = ""
    private var tracking: NSTrackingArea?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); HoverHelp.shared.hide(owner: self)
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) { HoverHelp.shared.show(message, owner: self) }
    override func mouseExited(with event: NSEvent) { HoverHelp.shared.hide(owner: self) }
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); HoverHelp.shared.hide(owner: self) }
}
