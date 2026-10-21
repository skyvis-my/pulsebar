import AppKit
import ServiceManagement

// `Pulsebar --open-at-login` / `--no-open-at-login`: same as the popover checkbox, scriptable. Prints the result and exits.
let args = CommandLine.arguments
if args.contains("--open-at-login") || args.contains("--no-open-at-login") {
    let service = SMAppService.mainApp
    do {
        if args.contains("--open-at-login") { try service.register() } else { try service.unregister() }
    } catch {
        print("Couldn't change open at login: \(error.localizedDescription)")
        exit(1)
    }
    switch service.status {
    case .enabled: print("Open at login: on")
    case .requiresApproval: print("Open at login: waiting for approval in System Settings › General › Login Items")
    case .notRegistered: print("Open at login: off")
    default: print("Open at login: unavailable")
    }
    exit(0)
}

// `Pulsebar --diagnose-keep-running`: read-only report of what the keep-running switch checks.
if args.contains("--diagnose-keep-running") {
    let power = KeepAwake.battery
    print("canToggle=\(KeepAwake.canToggle) onBattery=\(power.onBattery) battery=\(power.percent.map(String.init) ?? "nil")",
          "thermal=\(ProcessInfo.processInfo.thermalState.rawValue) sleepDisabled=\(LidWatcher.sleepDisabled)")
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
