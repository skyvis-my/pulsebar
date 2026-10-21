import AppKit
import SwiftUI

/// A plain borderless panel that drops down from the status item. Used instead of NSPopover, which on
/// recent macOS allocates ~130 MB of graphics memory every time it opens; this panel costs a few MB.
/// Closes on a click elsewhere, Esc, or when Pulsebar loses focus. Content is built on open and freed on close.
@MainActor
final class DropdownPanel: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var clickMonitor: Any?

    var isShown: Bool { panel != nil }
    /// True just after the panel closed itself, so the status item click that caused it doesn't reopen it.
    var closedRecently: Bool { lastClosed.map { Date().timeIntervalSince($0) < 0.3 } ?? false }
    private var lastClosed: Date?
    var window: NSWindow? { panel }

    func show<Content: View>(below button: NSStatusBarButton, content: Content) {
        close()
        let host = NSHostingController(rootView: content
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)))
        host.sizingOptions = [.preferredContentSize]

        let p = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .popUpMenu
        p.isReleasedWhenClosed = false
        p.contentViewController = host
        p.delegate = self
        panel = p

        anchor(to: button)
        p.makeKeyAndOrderFront(nil)
        p.makeFirstResponder(nil) // don't land in the host field with its text selected

        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        self.button = button
    }

    func close() {
        if panel != nil { lastClosed = Date() }
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        guard let closing = panel else { return }
        closing.orderOut(nil)
        closing.contentViewController = nil
        panel = nil
        // The view's memory is freed, but malloc keeps the pages; hand them back once teardown settles.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { malloc_zone_pressure_relief(nil, 0) }
    }

    private weak var button: NSStatusBarButton?

    /// Top-centered under the status item, kept on screen. Re-run when the content changes height.
    private func anchor(to button: NSStatusBarButton) {
        guard let panel, let itemFrame = button.window?.frame,
              let screen = button.window?.screen ?? NSScreen.main else { return }
        let size = panel.contentViewController?.preferredContentSize ?? panel.frame.size
        let visible = screen.visibleFrame
        var x = itemFrame.midX - size.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: itemFrame.minY - size.height - 4, width: size.width, height: size.height),
                       display: true)
    }

    func windowDidResize(_ notification: Notification) {
        // Keep the top edge pinned under the menu bar when the content grows or shrinks.
        if let button, let panel, let itemFrame = button.window?.frame,
           abs(panel.frame.maxY - (itemFrame.minY - 4)) > 0.5 {
            anchor(to: button)
        }
    }

    func windowDidResignKey(_ notification: Notification) { close() }
}

/// Borderless panels can't take keyboard focus by default; the host field needs it.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { (delegate as? DropdownPanel)?.close() }
}
