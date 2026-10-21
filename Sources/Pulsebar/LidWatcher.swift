import CoreGraphics
import Foundation
import IOKit

/// Backpack mode helper. When sleep is disabled (`pmset disablesleep 1`), closing the lid keeps macOS
/// running but leaves the built-in display lit. This turns the display off once the lid is closed,
/// leaving the system and network running. No admin rights needed.
final class LidWatcher {
    private var closedSince: Date?
    private var lastSleepRequest: Date?

    /// Call once a second.
    func tick(enabled: Bool) {
        guard enabled, Self.lidClosed else { closedSince = nil; return }
        let now = Date()
        if closedSince == nil { closedSince = now }
        // Give macOS a moment to handle the close itself, and don't spam if something keeps waking the display.
        guard now.timeIntervalSince(closedSince!) >= 2,
              lastSleepRequest.map({ now.timeIntervalSince($0) >= 5 }) ?? true,
              Self.builtinDisplayAwake, !Self.externalDisplayAwake else { return }
        lastSleepRequest = now
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
    }

    /// True when macOS will keep running with the lid closed (`pmset disablesleep 1`, set by any app).
    static var sleepDisabled: Bool { rootDomainBool("SleepDisabled") ?? false }

    static var lidClosed: Bool { rootDomainBool("AppleClamshellState") ?? false }

    private static func rootDomainBool(_ key: String) -> Bool? {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }
        return IORegistryEntryCreateCFProperty(root, key as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? Bool
    }

    private static var onlineDisplays: [CGDirectDisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        return Array(ids.prefix(Int(n)))
    }

    private static var builtinDisplayAwake: Bool {
        onlineDisplays.contains { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    /// Lid closed with an awake external monitor is normal clamshell desk use: leave it alone.
    private static var externalDisplayAwake: Bool {
        onlineDisplays.contains { CGDisplayIsBuiltin($0) == 0 && CGDisplayIsAsleep($0) == 0 }
    }
}
