import Foundation
import IOKit.ps

/// "Keep running with lid closed": toggles `pmset -a disablesleep` with `sudo -n`, so the safety guards can
/// turn it back off unattended (in a bag, nobody can type a password). Pulsebar never installs privileges
/// itself: it works only if the user (or an app like Amphetamine) already allows these two exact commands
/// without a password. The README documents the one-line rule to add by hand.
enum KeepAwake {
    static let batteryFloor = 20

    /// Whether this user can run both pmset commands without a password.
    static var canToggle: Bool {
        run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "1"]) == 0
            && run("/usr/bin/sudo", ["-n", "-l", "/usr/bin/pmset", "-a", "disablesleep", "0"]) == 0
    }

    /// Returns true if pmset accepted the change.
    @discardableResult
    static func set(_ disableSleep: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", disableSleep ? "1" : "0"]) == 0
    }

    enum StopReason: Equatable {
        case lowBattery(Int)
        case hot

        /// Shown after the guard switched keep-running off.
        var offNote: String {
            switch self {
            case .lowBattery(let pct): "Turned off at \(pct)% battery."
            case .hot: "Turned off because the Mac was running hot."
            }
        }

        /// Shown when the guard stops keep-running from switching on.
        var blockedNote: String {
            switch self {
            case .lowBattery(let pct): "Battery is at \(pct)%. Charge above \(KeepAwake.batteryFloor)% first."
            case .hot: "The Mac is running hot. Try again once it cools down."
            }
        }
    }

    /// Why keep-running must switch off now, or nil if it's safe to stay on.
    static func stopReason(onBattery: Bool, batteryPercent: Int?, thermal: ProcessInfo.ThermalState) -> StopReason? {
        if onBattery, let pct = batteryPercent, pct <= batteryFloor { return .lowBattery(pct) }
        if thermal == .serious || thermal == .critical { return .hot }
        return nil
    }

    static var battery: (onBattery: Bool, percent: Int?) {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return (false, nil) }
        let onBattery = (IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?) == kIOPMBatteryPowerKey
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let cur = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return (onBattery, cur * 100 / max)
        }
        return (onBattery, nil)
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
