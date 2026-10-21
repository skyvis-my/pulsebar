import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor()
    private var item: NSStatusItem!
    private let view = StatusItemView()
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: StatusItemView.width(for: monitor.style))
        item.autosaveName = "Pulsebar"
        if let button = item.button {
            view.frame = button.bounds
            view.autoresizingMask = [.width, .height]
            button.addSubview(view)
            button.target = self
            button.action = #selector(toggle)
            button.setAccessibilityLabel("Network monitor")
        }

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = NSHostingController(rootView: PopoverView(monitor: monitor))

        monitor.onChange = { [weak self] in self?.refresh() }
        monitor.start()
        refresh()

        if let dir = Snapshot.directory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [self] in
                Snapshot.render(monitor: monitor, to: dir)
                // Also capture the real status item and popover windows as AppKit draws them.
                toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                    if let w = item.button?.window { Snapshot.capture(w, to: dir.appendingPathComponent("live-item.png")) }
                    if let w = popover.contentViewController?.view.window {
                        Snapshot.capture(w, to: dir.appendingPathComponent("live-popover.png"))
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.saveHistory()
    }

    private func refresh() {
        let width = StatusItemView.width(for: monitor.style)
        if item.length != width { item.length = width } // only changes when you switch style
        view.style = monitor.style
        view.up = monitor.up
        view.down = monitor.down
        view.ping = monitor.ping
        view.recent = monitor.recentPings(20)
        view.recentRates = monitor.recentRates(30)
        view.needsDisplay = true
        item.button?.setAccessibilityValue(
            "Download \(Format.rate(monitor.down)), upload \(Format.rate(monitor.up)), ping \(Format.pingLong(monitor.ping)) milliseconds"
        )
    }

    @objc private func toggle() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            let window = popover.contentViewController?.view.window
            window?.makeKey()
            window?.makeFirstResponder(nil) // don't land in the host field with its text selected
        }
    }
}
