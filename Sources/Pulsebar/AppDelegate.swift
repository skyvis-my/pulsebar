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
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [monitor] in
                Snapshot.render(monitor: monitor, to: dir)
                NSApp.terminate(nil)
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
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
