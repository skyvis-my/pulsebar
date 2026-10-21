import AppKit
import Combine
import ServiceManagement

enum MenuStyle: String, CaseIterable, Identifiable {
    case twin, spark, line, pingOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .twin: "Twin stack"
        case .spark: "Stack + spark"
        case .line: "Single line"
        case .pingOnly: "Ping only"
        }
    }
}

struct Sample: Identifiable, Codable {
    let id: Int
    let date: Date
    let up: Double
    let down: Double
    let ping: Double?
}

enum Quality {
    case good, fair, poor
    init(_ ms: Double?) {
        guard let ms else { self = .poor; return }
        self = ms < 60 ? .good : ms < 150 ? .fair : .poor
    }
    var color: NSColor {
        switch self {
        case .good: .systemGreen
        case .fair: .systemOrange
        case .poor: .systemRed
        }
    }
}

@MainActor
final class Monitor: ObservableObject {
    static let capacity = 3600 // one hour at 1 Hz

    @Published private(set) var samples: [Sample] = []
    @Published private(set) var up = 0.0
    @Published private(set) var down = 0.0
    /// Menu bar ping (steadied, see `steadied`); nil means the last probe timed out.
    @Published private(set) var ping: Double?
    /// Every raw reading, for the popover's live number.
    @Published private(set) var livePing: Double?
    @Published var style: MenuStyle {
        didSet { UserDefaults.standard.set(style.rawValue, forKey: "style"); onChange?() }
    }
    @Published var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "host") }
    }
    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    /// Turn the built-in display off when the lid closes but macOS keeps running (backpack mode).
    @Published var lidDisplayOff: Bool {
        didSet { UserDefaults.standard.set(lidDisplayOff, forKey: "lidDisplayOff") }
    }
    /// Whether macOS keeps running with the lid closed (`pmset disablesleep 1`, set by any app).
    @Published private(set) var sleepDisabled = LidWatcher.sleepDisabled

    /// Pulsebar's own "keep running with lid closed" switch. Always starts off.
    @Published private(set) var keepRunning = false
    /// Why keep-running switched itself off, or why it couldn't switch on.
    @Published private(set) var keepRunningNote: String?
    private static let ownedKey = "keepRunningOwned"

    var onChange: (() -> Void)?

    private let lidWatcher = LidWatcher()
    private let sampler = NetworkSampler()
    private let pinger = Pinger()
    private var timer: Timer?
    private var nextID = 0
    private var latestPing: Double?

    init() {
        let d = UserDefaults.standard
        style = d.string(forKey: "style").flatMap(MenuStyle.init) ?? .spark
        host = d.string(forKey: "host") ?? "1.1.1.1"
        lidDisplayOff = d.object(forKey: "lidDisplayOff") as? Bool ?? true
        loadHistory()
        // Crash guard: if we left sleep disabled last time (no clean quit), undo it now.
        if d.bool(forKey: Self.ownedKey) {
            KeepAwake.set(false)
            d.removeObject(forKey: Self.ownedKey)
            keepRunningNote = "Turned off because Pulsebar didn't quit cleanly."
            sleepDisabled = LidWatcher.sleepDisabled
            logKeepRunning("crash recovery: restored sleep, sleepDisabled=\(sleepDisabled)")
        }
    }

    // MARK: - Keep running with lid closed

    func setKeepRunning(_ on: Bool) {
        guard on else { stopKeepRunning(note: nil); return }
        keepRunningNote = nil
        let power = KeepAwake.battery
        if let reason = KeepAwake.stopReason(onBattery: power.onBattery, batteryPercent: power.percent,
                                             thermal: ProcessInfo.processInfo.thermalState) {
            keepRunningNote = reason.blockedNote
        } else if !KeepAwake.canToggle {
            keepRunningNote = "Needs a one-time permission. See the Pulsebar README."
        } else if !KeepAwake.set(true) {
            keepRunningNote = "macOS refused the change, so sleep is unchanged."
        } else {
            UserDefaults.standard.set(true, forKey: Self.ownedKey)
            keepRunning = true
        }
        sleepDisabled = LidWatcher.sleepDisabled
        logKeepRunning("on requested: keepRunning=\(keepRunning) sleepDisabled=\(sleepDisabled) note=\(keepRunningNote ?? "-")")
        onChange?()
    }

    /// Last 20 keep-running events, readable with `defaults read com.skyvis.pulsebar keepRunningLog`.
    private func logKeepRunning(_ event: String) {
        let d = UserDefaults.standard
        let stamp = ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withTime, .withColonSeparatorInTime])
        // Array(...): an ArraySlice isn't a property-list type, and UserDefaults silently drops it.
        d.set(Array(((d.stringArray(forKey: "keepRunningLog") ?? []) + ["\(stamp) \(event)"]).suffix(20)),
              forKey: "keepRunningLog")
    }

    /// Restores normal sleep if Pulsebar turned it off. Called by the guards and on quit.
    func stopKeepRunning(note: String?) {
        guard keepRunning || UserDefaults.standard.bool(forKey: Self.ownedKey) else { return }
        KeepAwake.set(false)
        UserDefaults.standard.removeObject(forKey: Self.ownedKey)
        keepRunning = false
        keepRunningNote = note
        sleepDisabled = LidWatcher.sleepDisabled
        logKeepRunning("stopped: sleepDisabled=\(sleepDisabled) note=\(note ?? "-")")
        onChange?()
    }

    private func checkKeepRunningGuards() {
        guard keepRunning else { return }
        let power = KeepAwake.battery
        if let reason = KeepAwake.stopReason(onBattery: power.onBattery, batteryPercent: power.percent,
                                             thermal: ProcessInfo.processInfo.thermalState) {
            stopKeepRunning(note: reason.offNote)
        } else if !sleepDisabled {
            // Something else re-enabled sleep; don't fight it.
            keepRunning = false
            UserDefaults.standard.removeObject(forKey: Self.ownedKey)
            keepRunningNote = "Sleep was turned back on outside Pulsebar."
            logKeepRunning("stepped aside: sleep re-enabled outside Pulsebar")
        }
    }

    /// The menu bar ping: holds the shown value until a reading differs from it by at least 5 ms
    /// and by more than 10%, so the number doesn't flicker between 12 and 15. Timeouts and recoveries
    /// always show at once. The popover and graphs use every raw reading.
    static func steadied(shown: Double?, latest: Double?) -> Double? {
        guard let latest, let shown, shown > 0 else { return latest }
        let change = abs(latest - shown)
        return change >= 5 && change / shown > 0.10 ? latest : shown
    }

    /// Most recent pings, oldest first, for the menu bar sparkline/bars.
    func recentPings(_ n: Int) -> [Double?] { samples.suffix(n).map(\.ping) }

    func recentRates(_ n: Int) -> [(up: Double, down: Double)] { samples.suffix(n).map { ($0.up, $0.down) } }

    // MARK: - History on disk (last hour survives quit/relaunch)

    private static var historyURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pulsebar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }

    func saveHistory() {
        guard let data = try? JSONEncoder().encode(samples) else { return }
        try? data.write(to: Self.historyURL, options: .atomic)
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: Self.historyURL),
              let saved = try? JSONDecoder().decode([Sample].self, from: data) else { return }
        let cutoff = Date().addingTimeInterval(-Double(Self.capacity))
        samples = saved.filter { $0.date > cutoff }.suffix(Self.capacity).enumerated().map { i, s in
            Sample(id: i, date: s.date, up: s.up, down: s.down, ping: s.ping)
        }
        nextID = samples.count
    }

    func start() {
        _ = sampler.sample() // prime the counters
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common) // keep ticking while the popover/menu is tracking
        timer = t
        firePing()
    }

    private func tick() {
        // Record the probe sent a second ago alongside this second's bandwidth, then send the next one.
        if let rate = sampler.sample() { up = rate.up; down = rate.down }
        ping = Self.steadied(shown: ping, latest: latestPing)
        livePing = latestPing
        append(Sample(id: nextID, date: Date(), up: up, down: down, ping: latestPing))
        if nextID % 60 == 0 { saveHistory() }
        let disabled = LidWatcher.sleepDisabled
        if disabled != sleepDisabled { sleepDisabled = disabled }
        checkKeepRunningGuards()
        lidWatcher.tick(enabled: lidDisplayOff)
        firePing()
        onChange?()
    }

    private func firePing() {
        latestPing = nil
        let target = host.trimmingCharacters(in: .whitespaces)
        pinger.ping(target.isEmpty ? "1.1.1.1" : target) { [weak self] ms in
            MainActor.assumeIsolated { self?.latestPing = ms }
        }
    }

    private func append(_ s: Sample) {
        nextID += 1
        samples.append(s)
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }
}
