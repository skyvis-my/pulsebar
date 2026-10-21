import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor()
    private var item: NSStatusItem!
    private let view = StatusItemView()
    private let dropdown = DropdownPanel()

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

        monitor.onChange = { [weak self] in self?.refresh() }
        monitor.start()
        refresh()

        // Memory testing: PULSEBAR_POPOVER_SECONDS=N opens the popover 2 s after launch for N seconds.
        if let seconds = ProcessInfo.processInfo.environment["PULSEBAR_POPOVER_SECONDS"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [self] in dropdown.close() }
            }
        }

        if let dir = Snapshot.directory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [self] in
                Snapshot.render(monitor: monitor, to: dir)
                // Also capture the real status item and popover windows as AppKit draws them.
                toggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [self] in
                    if let w = item.button?.window { Snapshot.capture(w, to: dir.appendingPathComponent("live-item.png")) }
                    if let w = dropdown.window {
                        Snapshot.capture(w, to: dir.appendingPathComponent("live-popover.png"))
                    }
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// Routes SIGTERM/SIGINT through a normal quit so the keep-running guard always restores sleep.
    private var signalSources: [DispatchSourceSignal] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { NSApp.terminate(nil) }
            source.resume()
            signalSources.append(source)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stopKeepRunning(note: nil)
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
        if dropdown.isShown || dropdown.closedRecently {
            dropdown.close()
        } else {
            // Built on open and freed on close: a closed dropdown costs no memory and no rendering.
            dropdown.show(below: button, content: PopoverView(monitor: monitor))
        }
    }
}
