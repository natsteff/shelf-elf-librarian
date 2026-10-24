import AppKit
import SwiftUI

/// Panels belong to the window that initiated the action, including nested settings sheets.
@MainActor enum WindowPresentation {
    static var activeWindow: NSWindow? {
        var candidate = NSApp.keyWindow ?? NSApp.mainWindow
        if candidate is NSSavePanel { candidate = candidate?.sheetParent ?? NSApp.mainWindow }
        if candidate?.identifier?.rawValue.hasPrefix("shelf.info.") == true { candidate = candidate?.parent ?? NSApp.mainWindow }
        if candidate == nil { candidate = NSApp.orderedWindows.first { $0.isVisible && $0.canBecomeMain } }
        while let attached = candidate?.attachedSheet, !(attached is NSSavePanel) { candidate = attached }
        return candidate
    }
    static func choose(_ panel: NSSavePanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        HoverHelp.shared.hide()
        // Run follow-up UI after the chooser has detached; otherwise a confirmation
        // can attach to the closing chooser and disappear with it.
        let finished: (NSApplication.ModalResponse) -> Void = { response in
            DispatchQueue.main.async { completion(response) }
        }
        if let parent = activeWindow { panel.beginSheetModal(for: parent, completionHandler: finished) }
        else { panel.begin(completionHandler: finished) }
    }
    static func confirm(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        HoverHelp.shared.hide()
        if let parent = activeWindow { alert.beginSheetModal(for: parent, completionHandler: completion) }
        else { completion(alert.runModal()) }
    }
    private static var infoWindows: [String: InfoWindowController] = [:]
    static func about() {
        showInfo("about", title: "About " + AppIdentity.name, size: NSSize(width: 440, height: 460)) { window in
            AnyView(AboutShelfElfView { window.close() })
        }
    }
    static func help() {
        showInfo("help", title: "Shelf Elf Help", size: NSSize(width: 660, height: 580)) { window in
            AnyView(ShelfElfHelpView { window.close() })
        }
    }
    private static func showInfo(_ key: String, title: String, size: NSSize, content: (NSWindow) -> AnyView) {
        HoverHelp.shared.hide()
        let parent = activeWindow
        infoWindows[key]?.close()
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.identifier = NSUserInterfaceItemIdentifier("shelf.info." + key)
        panel.title = title; panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: content(panel))
        let controller = InfoWindowController(window: panel)
        controller.onClose = { infoWindows.removeValue(forKey: key) }
        infoWindows[key] = controller
        if let parent {
            let screen = parent.screen?.visibleFrame ?? parent.frame
            let target = parent.frame.intersection(screen)
            let width = panel.frame.width, height = panel.frame.height
            let x = max(screen.minX + 8, min(target.midX - width / 2, screen.maxX - width - 8))
            let y = max(screen.minY + 8, min(target.midY - height / 2, screen.maxY - height - 8))
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            parent.addChildWindow(panel, ordered: .above)
        } else { panel.center() }
        controller.showWindow(nil); panel.makeKeyAndOrderFront(nil)
    }
}
@MainActor private final class InfoWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    override init(window: NSWindow?) { super.init(window: window); window?.delegate = self }
    required init?(coder: NSCoder) { return nil }
    func windowWillClose(_ notification: Notification) {
        if let window { window.parent?.removeChildWindow(window); window.contentView = nil }
        onClose?(); onClose = nil
    }
}
/// Keeps the accessibility/window title, while preventing its duplicate visual rendering beside the brand.
struct MainWindowAppearance: NSViewRepresentable {
    func makeNSView(context: Context) -> AppearanceView { AppearanceView() }
    func updateNSView(_ view: AppearanceView, context: Context) { view.apply() }
    final class AppearanceView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); apply() }
        func apply() { window?.titleVisibility = .hidden }
    }
}
/// On macOS 26 hide automatic group capsules on custom toolbar content; earlier systems stay native.
struct UnsharedToolbarItem<Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let content: Content
    init(placement: ToolbarItemPlacement, @ViewBuilder content: () -> Content) { self.placement = placement; self.content = content() }
    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: placement) { content }.sharedBackgroundVisibility(.hidden)
        } else { ToolbarItem(placement: placement) { content } }
    }
}
