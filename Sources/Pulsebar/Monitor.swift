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
    @Published private(set) var ping: Double?
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
        ping = latestPing
        append(Sample(id: nextID, date: Date(), up: up, down: down, ping: latestPing))
        if nextID % 60 == 0 { saveHistory() }
        let disabled = LidWatcher.sleepDisabled
        if disabled != sleepDisabled { sleepDisabled = disabled }
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
