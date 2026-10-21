import Charts
import SwiftUI

private enum Window: Int, CaseIterable, Identifiable {
    case m1 = 60, m5 = 300, m15 = 900, h1 = 3600
    var id: Int { rawValue }
    var label: String {
        switch self { case .m1: "1m"; case .m5: "5m"; case .m15: "15m"; case .h1: "1h" }
    }
}

private struct Point: Identifiable {
    let id: Int
    let date: Date
    let up: Double
    let down: Double
    let ping: Double?
    /// Increments across gaps (app not running, sleep) so lines don't bridge missing time.
    let segment: Int
}

private let downColor = Color(red: 0.36, green: 0.79, blue: 0.65)
private let upColor = Color(red: 0.62, green: 0.55, blue: 0.95)
private let pingColor = Color(red: 0.36, green: 0.79, blue: 0.65)
private let mono = Font.system(size: 11, weight: .medium, design: .monospaced)

struct PopoverView: View {
    @ObservedObject var monitor: Monitor
    @AppStorage("window") private var windowRaw = Window.m5.rawValue

    private var window: Window { Window(rawValue: windowRaw) ?? .m5 }

    var body: some View {
        let now = Date()
        let domain = now.addingTimeInterval(-Double(window.rawValue))...now
        // Select by time, not count: restored history has gaps, so the last N samples can reach further back.
        let raw = monitor.samples.suffix(window.rawValue).filter { $0.date >= domain.lowerBound }
        let points = Self.bucket(Array(raw), maxPoints: 180)

        VStack(alignment: .leading, spacing: 14) {
            header
            Picker("", selection: $windowRaw) {
                ForEach(Window.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            pingSection(Array(raw), points, domain)
            bandwidthSection(Array(raw), points, domain)
            Divider()
            settings
        }
        .padding(16)
        .frame(width: 340)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Format.pingLong(monitor.ping))
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .foregroundStyle(monitor.ping == nil ? Color.red : Color.primary)
                .contentTransition(.numericText())
            Text(monitor.host)
                .font(mono)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("↓ " + Format.rate(monitor.down)).foregroundStyle(downColor)
                Text("↑ " + Format.rate(monitor.up)).foregroundStyle(upColor)
            }
            .font(mono)
        }
    }

    // MARK: - Ping

    private func pingSection(_ raw: [Sample], _ pts: [Point], _ domain: ClosedRange<Date>) -> some View {
        let ok = raw.compactMap(\.ping)
        let loss = raw.isEmpty ? 0 : Double(raw.count - ok.count) / Double(raw.count) * 100
        let jitter = zip(ok, ok.dropFirst()).map { abs($1 - $0) }
        return VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Ping", unit: "ms")
            Chart {
                ForEach(pts) { p in
                    if let ms = p.ping {
                        AreaMark(x: .value("t", p.date), y: .value("ms", ms), series: .value("seg", p.segment))
                            .foregroundStyle(pingColor.opacity(0.15))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("t", p.date), y: .value("ms", ms), series: .value("seg", p.segment))
                            .foregroundStyle(pingColor)
                            .lineStyle(StrokeStyle(lineWidth: 1.4))
                            .interpolationMethod(.monotone)
                    } else {
                        RuleMark(x: .value("t", p.date))
                            .foregroundStyle(Color.red.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }
            }
            .chartXScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel().font(.system(size: 9, design: .monospaced))
            } }
            .frame(height: 96)
            statRow([
                ("min", ok.min().map { Format.pingLong($0) } ?? "–"),
                ("avg", ok.isEmpty ? "–" : Format.pingLong(ok.reduce(0, +) / Double(ok.count))),
                ("max", ok.max().map { Format.pingLong($0) } ?? "–"),
                ("jitter", jitter.isEmpty ? "–" : Format.pingLong(jitter.reduce(0, +) / Double(jitter.count))),
                ("loss", String(format: "%.0f%%", loss)),
            ])
        }
    }

    // MARK: - Bandwidth

    private func bandwidthSection(_ raw: [Sample], _ pts: [Point], _ domain: ClosedRange<Date>) -> some View {
        let peakDown = raw.map(\.down).max() ?? 0
        let peakUp = raw.map(\.up).max() ?? 0
        // Each sample is one second, so the sum of rates is bytes transferred.
        let total = raw.reduce(0) { $0 + $1.down + $1.up }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionTitle("Bandwidth", unit: "per second")
                Spacer()
                legend("down", downColor)
                legend("up", upColor)
            }
            Chart {
                ForEach(pts) { p in
                    AreaMark(x: .value("t", p.date), y: .value("B/s", p.down),
                             series: .value("seg", "a\(p.segment)"), stacking: .unstacked)
                        .foregroundStyle(downColor.opacity(0.22))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", p.date), y: .value("B/s", p.down), series: .value("dir", "d\(p.segment)"))
                        .foregroundStyle(downColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("t", p.date), y: .value("B/s", p.up), series: .value("dir", "u\(p.segment)"))
                        .foregroundStyle(upColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.4))
                        .interpolationMethod(.monotone)
                }
            }
            .chartXScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.2))
                AxisValueLabel {
                    Text(Format.axisRate(v.as(Double.self) ?? 0)).font(.system(size: 9, design: .monospaced))
                }
            } }
            .frame(height: 96)
            statRow([
                ("peak ↓", Format.axisRate(peakDown)),
                ("peak ↑", Format.axisRate(peakUp)),
                ("moved", Format.axisRate(total).replacingOccurrences(of: "/s", with: "") + "B"),
            ])
        }
    }

    // MARK: - Settings

    private var settings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Menu bar").foregroundStyle(.secondary)
                Spacer()
                Picker("", selection: $monitor.style) {
                    ForEach(MenuStyle.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                Text("Ping host").foregroundStyle(.secondary)
                Spacer()
                TextField("1.1.1.1", text: $monitor.host)
                    .textFieldStyle(.roundedBorder)
                    .font(mono)
                    .frame(width: 150)
            }
            VStack(alignment: .leading, spacing: 2) {
                Toggle("Keep running with lid closed", isOn: Binding(
                    get: { monitor.keepRunning },
                    set: { monitor.setKeepRunning($0) }
                ))
                .toggleStyle(.checkbox)
                Text(keepRunningCaption)
                    .font(.system(size: 10))
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(monitor.keepRunningNote == nil ? Color.secondary.opacity(0.7) : Color.orange)
                    .padding(.leading, 20)
            }
            Toggle("Screen off when lid closes", isOn: $monitor.lidDisplayOff)
                .toggleStyle(.checkbox)
            HStack {
                Toggle("Open at login", isOn: $monitor.launchAtLogin)
                    .toggleStyle(.checkbox)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .font(.system(size: 12))
    }

    private var keepRunningCaption: String {
        if let note = monitor.keepRunningNote { return note }
        if monitor.keepRunning {
            return "Turns off at \(KeepAwake.batteryFloor)% battery, if the Mac runs hot, or when Pulsebar quits."
        }
        return monitor.sleepDisabled
            ? "Another app is keeping sleep disabled."
            : "Closing the lid sleeps the Mac."
    }

    // MARK: - Bits

    private func sectionTitle(_ title: String, unit: String) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold))
            Text(unit).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 8, height: 2)
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func statRow(_ items: [(String, String)]) -> some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.0) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.0).font(.system(size: 9)).foregroundStyle(.tertiary)
                    Text(item.1).font(mono)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Averages runs of samples so long windows stay cheap to draw. A bucket counts as a
    /// timeout only if every probe in it timed out.
    private static func bucket(_ samples: [Sample], maxPoints: Int) -> [Point] {
        let size = max(1, Int((Double(samples.count) / Double(maxPoints)).rounded(.up)))
        let gapLimit = Double(size) * 2 + 2
        var points: [Point] = []
        var segment = 0
        for start in stride(from: 0, to: samples.count, by: size) {
            let chunk = samples[start..<min(start + size, samples.count)]
            let last = chunk.last!
            if let prev = points.last, last.date.timeIntervalSince(prev.date) > gapLimit { segment += 1 }
            let n = Double(chunk.count)
            let pings = chunk.compactMap(\.ping)
            points.append(Point(
                id: last.id,
                date: last.date,
                up: chunk.reduce(0) { $0 + $1.up } / n,
                down: chunk.reduce(0) { $0 + $1.down } / n,
                ping: pings.isEmpty ? nil : pings.reduce(0, +) / Double(pings.count),
                segment: segment
            ))
        }
        return points
    }
}
