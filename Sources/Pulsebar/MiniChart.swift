import SwiftUI

/// A small line chart built from plain SwiftUI shapes. Swift Charts and Canvas both hold ~140 MB of
/// graphics memory when redrawn every second on recent macOS; shapes draw the same picture for ~1 MB.
struct MiniChart: View {
    struct Series {
        let values: [Double?]   // one per x; nil leaves a gap
        let color: Color
        var fill = false
    }

    let xs: [Double]            // 0...1 across the time window, one per point
    let segments: [Int]         // lines never join points from different segments (gaps in history)
    let series: [Series]
    var markers: [Double] = []  // x positions of red timeout rules
    var bytes = false           // round the axis top in 1024-based units, so labels read 20M, not 19M
    let label: (Double) -> String

    private static let labelWidth: CGFloat = 34
    private static let inset: CGFloat = 6

    var body: some View {
        let peak = series.flatMap { $0.values.compactMap { $0 } }.max() ?? 0
        let top = bytes ? Self.niceByteCeiling(peak) : Self.niceCeiling(peak)
        GeometryReader { geo in
            let plot = CGRect(x: 0, y: Self.inset, width: geo.size.width - Self.labelWidth,
                              height: geo.size.height - Self.inset * 2)
            ZStack(alignment: .topLeading) {
                Path { p in
                    for f in [0.0, 0.5, 1.0] {
                        let y = plot.maxY - plot.height * f
                        p.move(to: CGPoint(x: plot.minX, y: y))
                        p.addLine(to: CGPoint(x: plot.maxX, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)

                Path { p in
                    for m in markers {
                        let x = plot.minX + plot.width * m
                        p.move(to: CGPoint(x: x, y: plot.minY))
                        p.addLine(to: CGPoint(x: x, y: plot.maxY))
                    }
                }
                .stroke(Color.red.opacity(0.55), lineWidth: 1.5)

                ForEach(series.indices, id: \.self) { i in
                    let s = series[i]
                    let runs = runs(s.values).filter { $0.count > 1 }
                    let point = { (j: Int) in
                        CGPoint(x: plot.minX + plot.width * xs[j],
                                y: plot.maxY - plot.height * CGFloat(s.values[j]! / top))
                    }
                    if s.fill {
                        Path { p in
                            for run in runs {
                                p.move(to: CGPoint(x: point(run[0]).x, y: plot.maxY))
                                run.forEach { p.addLine(to: point($0)) }
                                p.addLine(to: CGPoint(x: point(run[run.count - 1]).x, y: plot.maxY))
                                p.closeSubpath()
                            }
                        }
                        .fill(s.color.opacity(0.18))
                    }
                    Path { p in
                        for run in runs { p.addLines(run.map(point)) }
                    }
                    .stroke(s.color, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                }

                ForEach([0.0, 0.5, 1.0], id: \.self) { f in
                    Text(label(top * f))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: Self.labelWidth - 2, alignment: .trailing)
                        .position(x: geo.size.width - (Self.labelWidth - 2) / 2, y: plot.maxY - plot.height * f)
                }
            }
        }
    }

    /// Index runs of consecutive non-nil values within one segment.
    private func runs(_ values: [Double?]) -> [[Int]] {
        var result: [[Int]] = [], current: [Int] = []
        for i in values.indices {
            if values[i] == nil || (current.last.map { segments[$0] != segments[i] } ?? false) {
                if !current.isEmpty { result.append(current) }
                current = []
            }
            if values[i] != nil { current.append(i) }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// niceCeiling within the value's own K/M/G unit (1024-based), matching how rates are labelled.
    static func niceByteCeiling(_ v: Double) -> Double {
        var unit = 1.0
        while v / unit >= 1000 { unit *= 1024 }
        return niceCeiling(v / unit) * unit
    }

    /// Rounds up to 1, 2 or 5 × 10^n so axis labels stay tidy.
    static func niceCeiling(_ v: Double) -> Double {
        guard v > 0 else { return 1 }
        let magnitude = pow(10, floor(log10(v)))
        for step in [1.0, 2.0, 5.0, 10.0] where step * magnitude >= v { return step * magnitude }
        return 10 * magnitude
    }
}
